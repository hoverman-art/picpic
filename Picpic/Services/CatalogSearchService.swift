//
//  CatalogSearchService.swift
//  Picpic
//
//  Chercher un livre qu'on n'a pas encore : « le rouge et le noir », « un
//  roman de Zola », le titre à moitié retenu d'un livre prêté.
//
//  La barre de recherche de l'accueil ne regardait que la bibliothèque déjà
//  scannée — utile pour retrouver ce qu'on possède, muette pour tout le reste.
//  Ce service prend la suite : la recherche par idée continue de classer TES
//  livres (embeddings, sur l'appareil), et les catalogues ouverts complètent
//  avec ce qui existe ailleurs, sans compte ni clé.
//
//  Deux sources en parallèle, comme pour les métadonnées d'un scan : Google
//  Books sans clé s'épuise (quota partagé, HTTP 429 mesuré le 4 septembre
//  2026) et Open Library est lent mais fiable. Interroger les deux et garder
//  ce qui arrive donne un résultat même quand l'une des deux tombe.
//

import Foundation

/// Un livre trouvé dans un catalogue, pas encore dans la bibliothèque.
nonisolated struct CatalogResult: Identifiable, Equatable, Sendable {
    let isbn: String?
    let title: String
    let authors: [String]
    let coverURLString: String?
    let year: String?

    var id: String { isbn ?? "\(title.lowercased())|\(authors.joined().lowercased())" }

    var authorsLabel: String {
        authors.isEmpty ? "Auteur inconnu" : authors.joined(separator: ", ")
    }
}

actor CatalogSearchService {

    static let shared = CatalogSearchService()

    private let session: URLSession
    /// Une frappe revient souvent sur la même requête (effacer, retaper) :
    /// autant ne pas rappeler les catalogues pour rien.
    private var cache: [String: [CatalogResult]] = [:]

    init() {
        let config = URLSessionConfiguration.default
        // Court exprès : la recherche accompagne la frappe, un résultat qui
        // arrive après dix secondes n'intéresse plus personne.
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        session = URLSession(configuration: config)
    }

    /// Cherche dans les catalogues ouverts. Rend au plus `limit` livres,
    /// dédoublonnés, les plus complets d'abord.
    func search(_ query: String, limit: Int = 8) async -> [CatalogResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }
        if ProcessInfo.processInfo.arguments.contains("-uitest-catalog-stub") {
            return Array(Self.stub.prefix(limit))
        }
        if let cached = cache[trimmed.lowercased()] { return cached }

        async let google = searchGoogleBooks(trimmed)
        async let openLibrary = searchOpenLibrary(trimmed)
        let merged = Self.merge(await google, await openLibrary, limit: limit)
        if !merged.isEmpty { cache[trimmed.lowercased()] = merged }
        return merged
    }

    /// Fusionne les deux sources sans doublon. Google d'abord quand il a
    /// répondu : ses fiches françaises portent plus souvent une couverture.
    static func merge(_ primary: [CatalogResult], _ secondary: [CatalogResult],
                      limit: Int) -> [CatalogResult] {
        var seen = Set<String>()
        var results: [CatalogResult] = []
        for result in primary + secondary {
            let key = Self.dedupeKey(result)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(result)
            if results.count == limit { break }
        }
        return results
    }

    /// Deux éditions du même livre ne doivent pas s'afficher deux fois : on
    /// compare le titre et le premier auteur, accents et casse mis de côté.
    static func dedupeKey(_ result: CatalogResult) -> String {
        let title = result.title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .filter { $0.isLetter || $0.isNumber }
        let author = (result.authors.first ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .filter { $0.isLetter || $0.isNumber }
        return "\(title)|\(author)"
    }

    // MARK: - Google Books

    private struct GoogleResponse: Decodable {
        struct Item: Decodable {
            struct VolumeInfo: Decodable {
                struct Identifier: Decodable { let type: String?; let identifier: String? }
                struct ImageLinks: Decodable { let thumbnail: String? }
                let title: String?
                let subtitle: String?
                let authors: [String]?
                let publishedDate: String?
                let industryIdentifiers: [Identifier]?
                let imageLinks: ImageLinks?
            }
            let volumeInfo: VolumeInfo?
        }
        let items: [Item]?
    }

    private func searchGoogleBooks(_ query: String) async -> [CatalogResult] {
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "10"),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "country", value: "FR"),
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(GoogleResponse.self, from: data)
        else { return [] }

        return (decoded.items ?? []).compactMap { item in
            guard let info = item.volumeInfo, let title = info.title else { return nil }
            let isbn = info.industryIdentifiers?
                .first(where: { $0.type == "ISBN_13" })?.identifier
                ?? info.industryIdentifiers?.first(where: { $0.type == "ISBN_10" })?.identifier
            return CatalogResult(
                isbn: isbn,
                title: [title, info.subtitle].compactMap { $0 }.joined(separator: " — "),
                authors: info.authors ?? [],
                // `https` explicite : Google renvoie encore des vignettes en
                // http, qu'ATS refuse de charger.
                coverURLString: info.imageLinks?.thumbnail?
                    .replacingOccurrences(of: "http://", with: "https://"),
                year: info.publishedDate.map { String($0.prefix(4)) }
            )
        }
    }

    // MARK: - Open Library

    private struct OpenLibraryResponse: Decodable {
        struct Doc: Decodable {
            let title: String?
            let author_name: [String]?
            let isbn: [String]?
            let first_publish_year: Int?
            let cover_i: Int?
        }
        let docs: [Doc]?
    }

    private func searchOpenLibrary(_ query: String) async -> [CatalogResult] {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "fields", value: "title,author_name,isbn,first_publish_year,cover_i"),
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(OpenLibraryResponse.self, from: data)
        else { return [] }

        return (decoded.docs ?? []).compactMap { doc in
            guard let title = doc.title else { return nil }
            // Un ISBN-13 se reconnaît à sa longueur : c'est celui qui sert au
            // reste de l'application (scan, disponibilité, couverture).
            let isbn = doc.isbn?.first(where: { $0.count == 13 }) ?? doc.isbn?.first
            return CatalogResult(
                isbn: isbn,
                title: title,
                authors: doc.author_name ?? [],
                coverURLString: doc.cover_i.map { "https://covers.openlibrary.org/b/id/\($0)-M.jpg" },
                year: doc.first_publish_year.map(String.init)
            )
        }
    }

    // MARK: - Bouchon pour les tests UI

    static let stub: [CatalogResult] = [
        CatalogResult(isbn: "9782070413119", title: "Madame Bovary", authors: ["Gustave Flaubert"],
                      coverURLString: nil, year: "1857"),
        CatalogResult(isbn: "9782070360420", title: "La Peste", authors: ["Albert Camus"],
                      coverURLString: nil, year: "1947"),
    ]
}
