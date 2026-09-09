//
//  BookMetadataService.swift
//  Picpic
//
//  Fetches book metadata by ISBN from free open-data sources,
//  directly from the device — no backend involved.
//  Order: Open Library (open data, CC0) → Google Books (fallback).
//

import Foundation

struct BookMetadata {
    var isbn: String
    var title: String
    var authors: [String]
    var description: String?
    var subjects: [String]
    var coverURLString: String?
    var publisher: String?
    var publishedDate: String?
    var pageCount: Int?
    var language: String?
}

enum BookMetadataError: LocalizedError {
    case notFound
    case network(Error)

    var errorDescription: String? {
        switch self {
        // Trois catalogues muets, c'est presque toujours le réseau ou une
        // panne côté source — pas un livre absent. Le message le dit, et
        // propose la seule action utile.
        case .notFound:
            return "Impossible de retrouver ce livre pour l'instant. Vérifie ta connexion et réessaie, ou saisis-le depuis « Ma filière à la BU »."
        case .network: return "Connexion impossible. Vérifie ton réseau."
        }
    }
}

struct BookMetadataService {
    /// Session dédiée : `URLSession.shared` attend 60 s, or la boucle
    /// parallèle ne rend la main qu'une fois toutes les sources retombées.
    /// Un catalogue qui traîne bloquerait l'écran une minute.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    /// Trois catalogues interrogés **en parallèle**, pas en cascade.
    ///
    /// La cascade coûtait trop cher le jour où une source flanche : mesuré le
    /// 04/09/2026, Google Books renvoyait 429 (quota de l'accès sans clé
    /// épuisé) et Open Library échouait 3 fois sur 8 en mettant 8 à 22 s.
    /// L'utilisateur voyait alors « Livre introuvable » sur un livre qui
    /// existe. En parallèle, la latence est celle de la source la plus rapide
    /// et il faut que les trois tombent en même temps pour échouer.
    ///
    /// Le Sudoc est la troisième source : officiel, sans clé, et il n'a pas
    /// bronché — il n'a ni résumé ni couverture, mais un livre correctement
    /// identifié vaut mieux qu'une erreur.
    func fetch(isbn rawISBN: String) async throws -> BookMetadata {
        let isbn = rawISBN.filter { $0.isNumber || $0 == "X" }
        guard !isbn.isEmpty else { throw BookMetadataError.notFound }

        // Rang = richesse de la fiche : Google Books porte le résumé, Open
        // Library la couverture et les thèmes, la BnF l'édition exacte, le
        // Sudoc l'essentiel.
        //
        // La BnF est la quatrième source, ajoutée le 9 septembre 2026 : ce
        // jour-là Google Books renvoyait de nouveau 429 sur son quota partagé,
        // et le dépôt légal ne connaît pas de quota. Elle apporte en plus la
        // collection et le format, que personne d'autre ne donne.
        //
        // On n'attend plus que Google : les quatre réponses sont collectées,
        // la plus riche sert de base et les autres bouchent ses trous. Avant,
        // une fiche sans résumé restait sans résumé même quand une autre
        // source en avait un.
        let collected = await withTaskGroup(of: (Int, BookMetadata?).self) { group in
            group.addTask { (0, try? await self.fetchFromGoogleBooks(isbn: isbn)) }
            group.addTask { (1, try? await self.fetchFromOpenLibrary(isbn: isbn)) }
            group.addTask { (2, await self.fetchFromBnF(isbn: isbn)) }
            group.addTask { (3, await self.fetchFromSudoc(isbn: isbn)) }

            var found: [(rank: Int, metadata: BookMetadata)] = []
            for await (rank, metadata) in group {
                if let metadata { found.append((rank, metadata)) }
            }
            return found.sorted { $0.rank < $1.rank }.map(\.metadata)
        }

        guard var merged = collected.first else { throw BookMetadataError.notFound }
        for other in collected.dropFirst() {
            merged = Self.filling(merged, with: other)
        }

        // Dernier recours pour le résumé : l'article de Wikipédia. C'est ce
        // qu'on regarde en premier quand on tient un livre inconnu, et sans
        // Google Books la fiche n'en avait aucun.
        if merged.description?.isEmpty != false,
           let summary = await WikipediaSummaryService.shared.summary(
               title: merged.title, authors: merged.authors) {
            // Attribution obligatoire : le texte est celui de Wikipédia,
            // publié sous CC BY-SA. Il voyage avec la fiche, donc la mention
            // aussi — la stocker à part demanderait une migration du modèle
            // pour une ligne de texte.
            merged.description = summary.extract + "\n\nRésumé : Wikipédia (CC BY-SA)." 
        }
        return merged
    }

    /// Complète une fiche avec ce qu'une autre source a et qu'elle n'a pas.
    /// Ne remplace jamais une valeur déjà présente : la source la mieux classée
    /// reste la référence.
    static func filling(_ base: BookMetadata, with other: BookMetadata) -> BookMetadata {
        var result = base
        if result.description?.isEmpty != false { result.description = other.description }
        if result.coverURLString?.isEmpty != false { result.coverURLString = other.coverURLString }
        if result.subjects.isEmpty { result.subjects = other.subjects }
        if result.publisher?.isEmpty != false { result.publisher = other.publisher }
        if result.publishedDate?.isEmpty != false { result.publishedDate = other.publishedDate }
        if result.pageCount == nil { result.pageCount = other.pageCount }
        if result.language?.isEmpty != false { result.language = other.language }
        if result.authors.isEmpty { result.authors = other.authors }
        return result
    }

    // MARK: - BnF (le dépôt légal : l'édition exacte, sans quota)

    private func fetchFromBnF(isbn: String) async -> BookMetadata? {
        guard let edition = await BnFService.shared.edition(isbn: isbn) else { return nil }
        return BookMetadata(
            isbn: isbn,
            title: edition.title,
            authors: edition.authors,
            description: nil,
            subjects: [],
            coverURLString: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg",
            publisher: edition.publisher,
            publishedDate: edition.year,
            pageCount: edition.pageCount,
            language: "fr"
        )
    }

    // MARK: - Sudoc (troisième source, sans résumé ni couverture propre)

    private func fetchFromSudoc(isbn: String) async -> BookMetadata? {
        guard let record = await SudocSearchService.shared.record(isbn: isbn) else { return nil }
        return BookMetadata(
            isbn: isbn,
            title: record.title,
            authors: record.authors,
            description: nil,
            subjects: Array(record.subjects.prefix(8)),
            // La couverture d'Open Library s'obtient par ISBN, sans passer par
            // son API de métadonnées — donc disponible même quand celle-ci tombe.
            coverURLString: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg",
            publisher: record.publisher,
            publishedDate: record.year,
            pageCount: nil,
            language: "fr"
        )
    }

    // MARK: - Open Library

    private struct OLResponse: Decodable {
        struct Author: Decodable { let key: String? }
        struct Work: Decodable { let key: String }
        let title: String?
        let by_statement: String?
        let number_of_pages: Int?
        let publish_date: String?
        let publishers: [String]?
        let subjects: [String]?
        let covers: [Int]?
        let works: [Work]?
        let authors: [Author]?
        let description: OLText?
    }

    /// Open Library "description" is either a string or {type, value}.
    private enum OLText: Decodable {
        case text(String)

        var value: String {
            switch self { case .text(let s): return s }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                self = .text(s)
                return
            }
            struct Typed: Decodable { let value: String }
            let typed = try container.decode(Typed.self)
            self = .text(typed.value)
        }
    }

    private struct OLWork: Decodable {
        let description: OLText?
        let subjects: [String]?
    }

    private nonisolated struct OLAuthor: Decodable { let name: String? }

    private func fetchFromOpenLibrary(isbn: String) async throws -> BookMetadata {
        let url = URL(string: "https://openlibrary.org/isbn/\(isbn).json")!
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BookMetadataError.notFound
        }
        let edition = try JSONDecoder().decode(OLResponse.self, from: data)
        guard let title = edition.title else { throw BookMetadataError.notFound }

        var description = edition.description?.value
        var subjects = edition.subjects ?? []

        // The work record usually carries the description and subjects.
        if description == nil || subjects.isEmpty, let workKey = edition.works?.first?.key {
            if let workURL = URL(string: "https://openlibrary.org\(workKey).json"),
               let (workData, _) = try? await session.data(from: workURL),
               let work = try? JSONDecoder().decode(OLWork.self, from: workData) {
                description = description ?? work.description?.value
                if subjects.isEmpty { subjects = work.subjects ?? [] }
            }
        }

        // Author records resolve concurrently (latency = slowest request,
        // not the sum), order preserved via the original index.
        let authorKeys = (edition.authors ?? []).compactMap(\.key)
        let session = self.session
        var authorNames: [String] = await withTaskGroup(of: (Int, String?).self) { group in
            for (index, key) in authorKeys.enumerated() {
                guard let authorURL = URL(string: "https://openlibrary.org\(key).json") else { continue }
                group.addTask {
                    let name = (try? await session.data(from: authorURL).0)
                        .flatMap { try? JSONDecoder().decode(OLAuthor.self, from: $0) }?
                        .name
                    return (index, name)
                }
            }
            var pairs: [(Int, String)] = []
            for await (index, name) in group {
                if let name { pairs.append((index, name)) }
            }
            return pairs.sorted { $0.0 < $1.0 }.map(\.1)
        }
        if authorNames.isEmpty, let by = edition.by_statement {
            authorNames = [by]
        }

        return BookMetadata(
            isbn: isbn,
            title: title,
            authors: authorNames,
            description: description,
            subjects: Array(subjects.prefix(8)),
            coverURLString: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg",
            publisher: edition.publishers?.first,
            publishedDate: edition.publish_date,
            pageCount: edition.number_of_pages,
            language: nil
        )
    }

    // MARK: - Google Books (no API key needed for volume search by ISBN)

    private struct GBResponse: Decodable {
        struct Item: Decodable {
            struct VolumeInfo: Decodable {
                struct ImageLinks: Decodable { let thumbnail: String? }
                let title: String?
                let authors: [String]?
                let description: String?
                let categories: [String]?
                let publisher: String?
                let publishedDate: String?
                let pageCount: Int?
                let language: String?
                let imageLinks: ImageLinks?
            }
            let volumeInfo: VolumeInfo
        }
        let items: [Item]?
    }

    private func fetchFromGoogleBooks(isbn: String) async throws -> BookMetadata {
        let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)&country=FR")!
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BookMetadataError.notFound
        }
        let decoded = try JSONDecoder().decode(GBResponse.self, from: data)
        guard let info = decoded.items?.first?.volumeInfo, let title = info.title else {
            throw BookMetadataError.notFound
        }
        return BookMetadata(
            isbn: isbn,
            title: title,
            authors: info.authors ?? [],
            description: info.description,
            subjects: info.categories ?? [],
            coverURLString: info.imageLinks?.thumbnail?
                .replacingOccurrences(of: "http://", with: "https://"),
            publisher: info.publisher,
            publishedDate: info.publishedDate,
            pageCount: info.pageCount,
            language: info.language
        )
    }
}
