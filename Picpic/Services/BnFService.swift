//
//  BnFService.swift
//  Picpic
//
//  La Bibliothèque nationale de France, quatrième catalogue de Picpic — et le
//  seul qui décrive l'ÉDITION plutôt que l'œuvre.
//
//  Pourquoi l'ajouter. Mesuré le 9 septembre 2026 : Google Books sans clé
//  répond HTTP 429 (« Quota exceeded […] Queries per day ») sur le projet
//  anonyme partagé — donc épuisable par n'importe qui, pas seulement par nous.
//  Ce jour-là, un scan perdait son résumé et sa fiche la plus riche. Le dépôt
//  légal, lui, ne connaît pas de quota : tout livre publié en France y est, et
//  l'API SRU est ouverte, sans clé.
//
//  Ce que la BnF apporte que les autres n'ont pas : la collection (« Folio »),
//  la pagination et le format en centimètres. C'est ce qui distingue un poche
//  à trois euros d'un grand format, et c'est la base de l'estimation
//  proposée aux chineurs (voir BookValueService).
//
//  Piège mesuré : le catalogue n'indexe que l'ISBN-10. Interroger avec
//  l'ISBN-13 imprimé sur le livre renvoie zéro notice — il faut convertir.
//

import Foundation

/// Ce que la BnF sait d'une édition précise.
nonisolated struct BnFEdition: Equatable, Sendable {
    let title: String
    let authors: [String]
    let publisher: String?
    /// Année de CETTE édition, pas de l'œuvre.
    let year: String?
    /// « Folio », « Le Livre de poche », « Points »…
    let collection: String?
    let pageCount: Int?
    /// Hauteur en centimètres : 18 cm = poche, 22 cm = broché, 30 cm = beau livre.
    let heightCm: Int?
}

struct BnFService {

    static let shared = BnFService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 12
        return URLSession(configuration: config)
    }()

    /// La notice d'une édition, à partir de l'ISBN imprimé sur le livre.
    func edition(isbn: String) async -> BnFEdition? {
        let digits = isbn.filter { $0.isNumber || $0 == "X" || $0 == "x" }
        guard let isbn10 = Self.isbn10(from: digits) else { return nil }

        var components = URLComponents(string: "https://catalogue.bnf.fr/api/SRU")!
        components.queryItems = [
            URLQueryItem(name: "version", value: "1.2"),
            URLQueryItem(name: "operation", value: "searchRetrieve"),
            URLQueryItem(name: "query", value: "bib.isbn all \"\(isbn10)\""),
            URLQueryItem(name: "recordSchema", value: "dublincore"),
            URLQueryItem(name: "maximumRecords", value: "1"),
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let xml = String(data: data, encoding: .utf8)
        else { return nil }

        return Self.parse(xml)
    }

    // MARK: - ISBN-13 → ISBN-10

    /// Convertit un ISBN-13 en ISBN-10, seule forme indexée par la BnF.
    ///
    /// Seuls les ISBN-13 en 978 ont un équivalent à dix chiffres : ceux en 979
    /// (les plus récents) n'en ont pas, et la BnF ne les trouvera pas — c'est
    /// une limite du catalogue, pas un défaut de conversion.
    static func isbn10(from isbn: String) -> String? {
        let clean = isbn.uppercased().filter { $0.isNumber || $0 == "X" }
        if clean.count == 10 { return clean }
        guard clean.count == 13, clean.hasPrefix("978") else { return nil }

        let body = String(clean.dropFirst(3).dropLast())
        let digits = body.compactMap { $0.wholeNumberValue }
        guard digits.count == 9 else { return nil }

        // Clé de contrôle ISBN-10 : somme pondérée de 10 à 2, modulo 11.
        let sum = digits.enumerated().reduce(0) { total, pair in
            total + (10 - pair.offset) * pair.element
        }
        let remainder = (11 - (sum % 11)) % 11
        let key = remainder == 10 ? "X" : String(remainder)
        return body + key
    }

    // MARK: - Lecture de la notice

    /// Extrait ce qui nous intéresse d'une réponse SRU en Dublin Core.
    ///
    /// Analyse par balise plutôt que par un vrai parseur XML : la réponse tient
    /// en quelques champs plats, tous sans imbrication.
    static func parse(_ xml: String) -> BnFEdition? {
        let titles = values(of: "dc:title", in: xml)
        guard let rawTitle = titles.first else { return nil }

        // La BnF écrit « Titre / Auteur » : la barre sépare la mention de
        // responsabilité, elle ne fait pas partie du titre.
        let title = rawTitle.components(separatedBy: " / ").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawTitle

        // « Camus, Albert (1913-1960). Auteur du texte » → « Albert Camus ».
        let authors = values(of: "dc:creator", in: xml).map(cleanAuthor)

        let descriptions = values(of: "dc:description", in: xml)
        let collection = descriptions
            .first { $0.hasPrefix("Collection :") }
            .map { $0.replacingOccurrences(of: "Collection :", with: "") }
            .map { $0.components(separatedBy: ";").first ?? $0 }?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let format = values(of: "dc:format", in: xml).first { $0.contains("cm") || $0.contains("p") }

        return BnFEdition(
            title: title,
            authors: authors,
            publisher: values(of: "dc:publisher", in: xml).first
                .map { $0.components(separatedBy: " (").first ?? $0 },
            year: values(of: "dc:date", in: xml).first.flatMap { $0.filter(\.isNumber).prefix(4).description }
                .flatMap { $0.count == 4 ? $0 : nil },
            collection: collection?.isEmpty == false ? collection : nil,
            pageCount: format.flatMap(pages(in:)),
            heightCm: format.flatMap(height(in:))
        )
    }

    /// « 1 volume 191 p ; 18 cm » → 191.
    static func pages(in format: String) -> Int? {
        guard let range = format.range(of: #"(\d+)\s*p"#, options: .regularExpression) else { return nil }
        return Int(format[range].filter(\.isNumber))
    }

    /// « 1 volume 191 p ; 18 cm » → 18.
    static func height(in format: String) -> Int? {
        guard let range = format.range(of: #"(\d+)\s*cm"#, options: .regularExpression) else { return nil }
        return Int(format[range].filter(\.isNumber))
    }

    static func cleanAuthor(_ raw: String) -> String {
        // On coupe à la première parenthèse (les dates) ou au premier point
        // suivi d'un rôle (« . Auteur du texte »).
        var name = raw.components(separatedBy: " (").first ?? raw
        name = name.components(separatedBy: ". ").first ?? name
        let parts = name.components(separatedBy: ", ").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2 else { return name.trimmingCharacters(in: .whitespacesAndNewlines) }
        return "\(parts[1]) \(parts[0])"
    }

    private static func values(of tag: String, in xml: String) -> [String] {
        var results: [String] = []
        var cursor = xml.startIndex
        while let open = xml.range(of: "<\(tag)", options: [], range: cursor ..< xml.endIndex),
              let openEnd = xml.range(of: ">", range: open.upperBound ..< xml.endIndex),
              let close = xml.range(of: "</\(tag)>", range: openEnd.upperBound ..< xml.endIndex) {
            let value = String(xml[openEnd.upperBound ..< close.lowerBound])
            results.append(decode(value).trimmingCharacters(in: .whitespacesAndNewlines))
            cursor = close.upperBound
        }
        return results.filter { !$0.isEmpty }
    }

    private static func decode(_ text: String) -> String {
        var result = text
        for (entity, character) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                    ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}
