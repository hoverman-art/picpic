//
//  BookValueService.swift
//  Picpic
//
//  « Ça vaut quoi ? » — ce que Picpic peut honnêtement dire du prix d'un livre
//  scanné, pour qui chine en brocante ou vide sa cave.
//
//  Ce que ce service NE fait PAS : inventer une cote. Aucun catalogue ouvert
//  ne publie de prix d'occasion en France, et les places de marché qui en ont
//  demandent une clé ou interdisent l'aspiration. Sortir un chiffre précis
//  serait une invention présentée comme une mesure.
//
//  Ce qu'il fait à la place : réunir les trois signaux qui font vraiment la
//  valeur d'un exemplaire, tous mesurables et tous d'accès libre —
//
//    l'édition   BnF : collection, pagination, hauteur en centimètres. Un
//                Folio de 18 cm et un grand format de 24 cm ne se vendent pas
//                au même prix, quel que soit le texte.
//    l'âge       année de CETTE édition (BnF), pas de l'œuvre.
//    la rareté   nombre de bibliothèques françaises qui le possèdent (Sudoc),
//                et nombre d'éditions connues (Open Library). « L'Étranger »
//                en Folio : 67 bibliothèques, 468 éditions — un livre qu'on
//                trouve partout. Trois bibliothèques et deux éditions, c'est
//                une autre histoire.
//
//  De ces signaux sort une FOURCHETTE, annoncée comme telle, avec la règle qui
//  l'a produite affichée à côté. Et trois liens pour aller voir les offres
//  réelles, parce que c'est le marché qui décide, pas nous.
//

import Foundation

nonisolated struct BookValuation: Equatable, Sendable {
    /// Fourchette en euros, bornes comprises.
    let low: Int
    let high: Int
    /// Le format retenu, en clair : « poche », « broché », « grand format ».
    let format: BookFormat
    let year: Int?
    let collection: String?
    /// Bibliothèques françaises qui le possèdent (Sudoc). `nil` = non mesuré.
    let libraries: Int?
    /// Éditions connues (Open Library).
    let editions: Int?
    /// Les raisons, dans l'ordre où elles ont joué.
    let reasons: [String]

    var range: String { low == high ? "\(low) €" : "\(low) – \(high) €" }
}

nonisolated enum BookFormat: String, Equatable, Sendable {
    case pocket, paperback, large, unknown

    var label: String {
        switch self {
        case .pocket: return "poche"
        case .paperback: return "broché"
        case .large: return "grand format"
        case .unknown: return "format inconnu"
        }
    }

    /// Fourchette de départ d'un exemplaire courant en bon état, en euros.
    /// Ordres de grandeur du marché français de l'occasion (Rakuten, Momox,
    /// vide-greniers) — c'est le point de départ, pas le résultat.
    var base: (low: Double, high: Double) {
        switch self {
        case .pocket: return (2, 5)
        case .paperback: return (5, 12)
        case .large: return (10, 22)
        case .unknown: return (3, 10)
        }
    }
}

struct BookValueService {

    static let shared = BookValueService()

    /// Les collections de poche françaises, quand la hauteur manque.
    private static let pocketCollections = [
        "folio", "livre de poche", "pocket", "j'ai lu", "points", "10/18",
        "presses pocket", "babel", "garnier-flammarion", "gf", "librio",
    ]

    // MARK: - Mesure

    func valuation(isbn: String, edition: BnFEdition?) async -> BookValuation? {
        async let libraries = holdings(isbn: isbn)
        async let editions = editionCount(isbn: isbn)
        let value = Self.estimate(edition: edition,
                                  libraries: await libraries,
                                  editions: await editions)
        return value
    }

    /// Combien de bibliothèques universitaires françaises le possèdent.
    /// Deux appels au Sudoc : l'ISBN donne un PPN, le PPN donne la liste.
    private func holdings(isbn: String) async -> Int? {
        guard let ppn = await SudocSearchService.shared.ppn(isbn: isbn) else { return nil }
        return await SudocSearchService.shared.libraryCount(ppn: ppn)
    }

    private func editionCount(isbn: String) async -> Int? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = [
            URLQueryItem(name: "isbn", value: isbn),
            URLQueryItem(name: "fields", value: "edition_count"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        struct Response: Decodable {
            struct Doc: Decodable { let edition_count: Int? }
            let docs: [Doc]?
        }
        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else { return nil }
        return decoded.docs?.first?.edition_count
    }

    // MARK: - Le modèle, en clair

    /// Applique les règles annoncées à l'écran. Pure et testable : c'est elle
    /// qui doit rester lisible, pas la fourchette qu'elle produit.
    static func estimate(edition: BnFEdition?, libraries: Int?, editions: Int?) -> BookValuation {
        let format = self.format(of: edition)
        var (low, high) = format.base
        var reasons: [String] = ["\(format.label.capitalized) : \(Int(low)) à \(Int(high)) € pour un exemplaire courant."]

        let year = edition?.year.flatMap(Int.init)
        if let year {
            if year < 1900 {
                low *= 6; high *= 10
                reasons.append("Édition de \(year) : avant 1900, un exemplaire se vend à la pièce, pas au texte.")
            } else if year < 1950 {
                low *= 2.5; high *= 4
                reasons.append("Édition de \(year) : le papier d'avant-guerre a sa valeur propre.")
            } else if year < 1980 {
                low *= 1.3; high *= 1.8
                reasons.append("Édition de \(year) : tirage ancien, moins courant en rayon.")
            }
        }

        if let libraries {
            if libraries <= 3 {
                low *= 2; high *= 3
                reasons.append("Seulement \(libraries) bibliothèque\(libraries > 1 ? "s" : "") française\(libraries > 1 ? "s" : "") le possède\(libraries > 1 ? "nt" : "") : c'est rare.")
            } else if libraries <= 12 {
                low *= 1.4; high *= 1.8
                reasons.append("\(libraries) bibliothèques françaises le possèdent : peu diffusé.")
            } else if libraries >= 50 {
                low *= 0.8; high *= 0.8
                reasons.append("\(libraries) bibliothèques françaises le possèdent : très diffusé.")
            }
        }

        if let editions, editions >= 200 {
            low *= 0.8; high *= 0.85
            reasons.append("\(editions) éditions connues : réimprimé sans fin, l'occasion abonde.")
        }

        // Plancher : en dessous d'un euro, un livre ne se vend pas, il se donne.
        let lowRounded = max(1, Int(low.rounded()))
        let highRounded = max(lowRounded + 1, Int(high.rounded()))

        return BookValuation(
            low: lowRounded,
            high: highRounded,
            format: format,
            year: year,
            collection: edition?.collection,
            libraries: libraries,
            editions: editions,
            reasons: reasons
        )
    }

    /// Poche, broché ou grand format. La hauteur tranche quand la BnF la
    /// donne ; sinon la collection, qui est presque toujours parlante.
    static func format(of edition: BnFEdition?) -> BookFormat {
        if let height = edition?.heightCm {
            switch height {
            case ..<20: return .pocket
            case 20..<25: return .paperback
            default: return .large
            }
        }
        if let collection = edition?.collection?.lowercased(),
           pocketCollections.contains(where: { collection.contains($0) }) {
            return .pocket
        }
        return .unknown
    }

    // MARK: - Aller voir le marché

    /// Les offres réelles, chez ceux qui les publient. Trois liens de
    /// recherche ordinaires, ouverts dans le navigateur : Picpic n'aspire
    /// aucun site et ne revend rien.
    static func marketLinks(isbn: String) -> [(name: String, url: URL)] {
        [
            ("Rakuten", "https://fr.shopping.rakuten.com/search/\(isbn)"),
            ("AbeBooks", "https://www.abebooks.fr/servlet/SearchResults?isbn=\(isbn)"),
            ("Vinted", "https://www.vinted.fr/catalog?search_text=\(isbn)"),
        ].compactMap { name, raw in
            URL(string: raw).map { (name, $0) }
        }
    }
}
