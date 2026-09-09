//
//  SudocSearchService.swift
//  Picpic
//
//  Recherche thématique dans le Sudoc — le catalogue collectif des
//  bibliothèques universitaires françaises (ABES, Licence Ouverte).
//
//  Là où `AvailabilityService` part d'un ISBN déjà scanné pour dire *où* le
//  trouver, ce service part d'un sujet pour dire *quoi* lire : « les livres de
//  ma filière que la BU d'à côté a en rayon ». C'est le service SRU d'ABES,
//  public et sans clé, donc toujours zéro backend.
//
//  Endpoint  : https://www.sudoc.abes.fr/cbs/sru/
//  Index CQL : msu (mots sujet) · mti (mots du titre) · aut (auteur) ·
//              tou (tous les mots) · rbc (RCR d'une bibliothèque) ·
//              apu (année) · lan (langue)
//  Réponse   : UNIMARC/XML — seul schéma qui porte le PPN et l'ISBN, les deux
//              clés dont l'app a besoin (l'ISBN branche le livre sur le reste
//              de Picpic, le PPN sur la notice et les exemplaires).
//

import Foundation

/// Une notice Sudoc telle que l'app l'affiche.
nonisolated struct SudocRecord: Identifiable, Hashable, Sendable {
    let ppn: String
    let title: String
    let subtitle: String?
    let authors: [String]
    let publisher: String?
    let year: String?
    /// ISBN normalisé (chiffres + X), s'il y en a un : c'est lui qui permet
    /// d'ajouter la notice à la bibliothèque avec sa couverture.
    let isbn: String?
    let subjects: [String]

    var id: String { ppn }

    var authorsLabel: String {
        authors.isEmpty ? "Auteur inconnu" : authors.joined(separator: ", ")
    }

    /// « Dunod, 2023 » — ce que porte la ligne de résultat.
    var imprintLabel: String {
        [publisher, year].compactMap { $0 }.joined(separator: ", ")
    }

    var noticeURL: URL? { URL(string: "https://www.sudoc.fr/\(ppn)") }
}

/// Où chercher : le rayon d'à côté, ou toute la France.
nonisolated enum SudocScope: String, CaseIterable, Identifiable, Sendable {
    case laRochelle
    case france

    var id: String { rawValue }

    var label: String {
        switch self {
        case .laRochelle: return "BU de La Rochelle"
        case .france: return "Toute la France"
        }
    }

    var shortLabel: String {
        switch self {
        case .laRochelle: return "À la BU"
        case .france: return "France"
        }
    }

    /// RCR de la bibliothèque (annuaire ABES) — nil = pas de filtre.
    /// 173002101 = LA ROCHELLE-BU (La Rochelle Université).
    var rcr: String? {
        switch self {
        case .laRochelle: return "173002101"
        case .france: return nil
        }
    }
}

/// L'index Sudoc interrogé.
nonisolated enum SudocIndex: String, CaseIterable, Identifiable, Sendable {
    case subject = "msu"
    case title = "mti"
    case author = "aut"
    case everything = "tou"
    /// Recherche par ISBN — pas proposée dans l'écran, utilisée pour compléter
    /// les métadonnées d'un livre scanné.
    case isbn = "isb"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .subject: return "Sujet"
        case .title: return "Titre"
        case .author: return "Auteur"
        case .everything: return "Partout"
        case .isbn: return "ISBN"
        }
    }

    /// Ce que l'écran de recherche propose. `isbn` en est exclu : il sert au
    /// complément de métadonnées d'un livre scanné, pas à une recherche à la main.
    static var browsable: [SudocIndex] { [.subject, .title, .author, .everything] }
}

nonisolated struct SudocQuery: Hashable, Sendable {
    var terms: String
    var index: SudocIndex = .subject
    var scope: SudocScope = .laRochelle
    /// Ne garder que les documents parus après cette année (exclue).
    var sinceYear: Int?
    var frenchOnly: Bool = true

    /// La requête CQL envoyée au SRU.
    var cql: String {
        // Les guillemets délimitent le terme : on les neutralise dans la saisie
        // plutôt que d'échapper, le SRU d'ABES n'ayant pas de séquence d'échappement.
        let cleaned = terms
            .replacingOccurrences(of: "\"", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var clauses = ["\(index.rawValue)=\"\(cleaned)\""]
        if let rcr = scope.rcr { clauses.append("rbc=\"\(rcr)\"") }
        if let sinceYear { clauses.append("apu>\"\(sinceYear)\"") }
        if frenchOnly { clauses.append("lan=\"fre\"") }
        return clauses.joined(separator: " and ")
    }
}

nonisolated struct SudocSearchResult: Sendable {
    let records: [SudocRecord]
    /// Nombre total de notices correspondant à la requête, tous écrans confondus.
    let totalRecords: Int
}

/// Sérialise les appels : ABES demande de rester sous 1 requête/seconde.
actor SudocSearchService {

    static let shared = SudocSearchService()

    enum Failure: LocalizedError {
        case emptyQuery
        case network
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .emptyQuery: return "Entre un sujet à chercher."
            case .network: return "Le Sudoc n'a pas répondu. Réessaie dans un instant."
            case .malformedResponse: return "Réponse illisible du Sudoc."
            }
        }
    }

    private let session: URLSession
    private var lastRequest: Date = .distantPast
    private let minimumInterval: TimeInterval = 1.0

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Une page de résultats. `startRecord` est 1-indexé, comme dans SRU.
    func search(_ query: SudocQuery, startRecord: Int = 1, pageSize: Int = 20) async throws -> SudocSearchResult {
        guard !query.terms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.emptyQuery
        }
        // Les tests UI ne doivent pas dépendre du réseau d'ABES.
        if ProcessInfo.processInfo.arguments.contains("-uitest-sudoc-stub") {
            return Self.stubResult
        }

        var components = URLComponents(string: "https://www.sudoc.abes.fr/cbs/sru/")!
        components.queryItems = [
            URLQueryItem(name: "operation", value: "searchRetrieve"),
            URLQueryItem(name: "version", value: "1.1"),
            URLQueryItem(name: "query", value: query.cql),
            URLQueryItem(name: "recordSchema", value: "unimarc"),
            URLQueryItem(name: "startRecord", value: String(max(1, startRecord))),
            URLQueryItem(name: "maximumRecords", value: String(pageSize)),
        ]
        guard let url = components.url else { throw Failure.malformedResponse }

        await throttle()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw Failure.network
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.network }

        let parser = SudocUnimarcParser()
        guard let parsed = parser.parse(data) else { throw Failure.malformedResponse }
        return parsed
    }

    /// Jeu de notices figé pour les tests UI et les captures.
    private static let stubResult = SudocSearchResult(
        records: [
            SudocRecord(ppn: "271929774", title: "Que fait l'école des données de nos enfants ?",
                        subtitle: "30 questions que se posent les parents",
                        authors: ["Gilles Braun", "Émilie Kerdelhué"],
                        publisher: "Dunod", year: "2023", isbn: "9782100849857",
                        subjects: ["Éducation et informatique", "Identité numérique"]),
            SudocRecord(ppn: "233968407", title: "Cloud et transformation digitale",
                        subtitle: "SI hybride, protection des données",
                        authors: ["Guillaume Plouin"],
                        publisher: "Dunod", year: "2019", isbn: "9782100790463",
                        subjects: ["Informatique dans les nuages"]),
            SudocRecord(ppn: "262350920", title: "Les data contre la liberté",
                        subtitle: nil, authors: ["Patrick Pharo"],
                        publisher: "PUF", year: "2022", isbn: "9782130833048",
                        subjects: ["Société numérique", "Droit à la vie privée"]),
        ],
        totalRecords: 3
    )

    /// Notice correspondant à un ISBN précis (index `isb`).
    ///
    /// Le Sudoc sert ici de troisième source de métadonnées : il est officiel,
    /// sans clé, et il a tenu tout du long là où Google Books tombe en quota et
    /// Open Library répond une fois sur deux.
    func record(isbn: String) async -> SudocRecord? {
        let digits = isbn.filter { $0.isNumber || $0 == "X" }
        guard !digits.isEmpty else { return nil }
        let query = SudocQuery(terms: digits, index: .isbn, scope: .france, frenchOnly: false)
        return try? await search(query, pageSize: 1).records.first
    }

    // MARK: - Rareté : qui possède ce livre

    /// PPN d'un ISBN, par le service `isbn2ppn` du Sudoc.
    ///
    /// Un même ISBN peut porter plusieurs notices (rééditions décrites
    /// séparément) : on garde la première, celle du signalement principal.
    func ppn(isbn: String) async -> String? {
        let digits = isbn.filter { $0.isNumber || $0 == "X" }
        guard !digits.isEmpty,
              let url = URL(string: "https://www.sudoc.fr/services/isbn2ppn/\(digits)"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let xml = String(data: data, encoding: .utf8)
        else { return nil }
        return Self.firstTag("ppn", in: xml)
    }

    /// Nombre de bibliothèques françaises qui possèdent la notice.
    ///
    /// C'est le signal de rareté le plus honnête dont on dispose : il vient du
    /// catalogue collectif, pas d'une estimation. « L'Étranger » en Folio est
    /// dans 67 bibliothèques ; un tirage confidentiel dans deux ou trois.
    func libraryCount(ppn: String) async -> Int? {
        guard let url = URL(string: "https://www.sudoc.fr/services/multiwhere/\(ppn)"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let xml = String(data: data, encoding: .utf8)
        else { return nil }
        return Self.countTag("shortname", in: xml)
    }

    static func firstTag(_ tag: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(tag)>"),
              let close = xml.range(of: "</\(tag)>", range: open.upperBound ..< xml.endIndex)
        else { return nil }
        let value = String(xml[open.upperBound ..< close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func countTag(_ tag: String, in xml: String) -> Int {
        var count = 0
        var cursor = xml.startIndex
        while let found = xml.range(of: "<\(tag)>", range: cursor ..< xml.endIndex) {
            count += 1
            cursor = found.upperBound
        }
        return count
    }

    private func throttle() async {
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minimumInterval {
            try? await Task.sleep(for: .seconds(minimumInterval - elapsed))
        }
        lastRequest = Date()
    }
}

// MARK: - UNIMARC

/// Extrait les notices d'une réponse SRU en UNIMARC/XML.
///
/// Champs lus : 001 (PPN) · 010$a (ISBN) · 200 $a titre $e sous-titre
/// $f mention de responsabilité · 210/214 $c éditeur $d date ·
/// 700/701/702 $a nom $b prénom · 606$a sujets Rameau.
nonisolated final class SudocUnimarcParser: NSObject, XMLParserDelegate {

    /// Caractères de tri UNIMARC (NSB/NSE) : le Sudoc encadre les articles
    /// initiaux avec, « ␘Les ␜data » doit s'afficher « Les data ».
    private static let nonSorting = CharacterSet(charactersIn: "\u{0088}\u{0089}\u{0098}\u{009C}")

    private var records: [SudocRecord] = []
    private var totalRecords = 0

    private var currentTag: String?
    private var currentSubfieldCode: String?
    private var text = ""
    private var inNumberOfRecords = false

    // Notice en cours de construction.
    private var ppn: String?
    private var title: String?
    private var subtitle: String?
    private var responsibility: String?
    private var authorSurname: String?
    private var authorForename: String?
    private var authors: [String] = []
    private var publisher: String?
    private var year: String?
    private var isbn: String?
    private var subjects: [String] = []

    func parse(_ data: Data) -> SudocSearchResult? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return nil }
        return SudocSearchResult(records: records, totalRecords: totalRecords)
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String]) {
        switch localName(elementName) {
        case "numberOfRecords":
            inNumberOfRecords = true
            text = ""
        case "record":
            // <srw:record> enveloppe <record> : ne réinitialiser que sur la notice.
            if attributeDict.isEmpty { resetCurrentRecord() }
        case "controlfield", "datafield":
            currentTag = attributeDict["tag"]
            text = ""
        case "subfield":
            currentSubfieldCode = attributeDict["code"]
            text = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let name = localName(elementName)
        let value = clean(text)

        switch name {
        case "numberOfRecords":
            if inNumberOfRecords { totalRecords = Int(value) ?? 0 }
            inNumberOfRecords = false

        case "controlfield":
            if currentTag == "001", !value.isEmpty { ppn = value }
            currentTag = nil

        case "subfield":
            store(subfield: currentSubfieldCode, value: value)
            currentSubfieldCode = nil

        case "datafield":
            // Un auteur se compose de deux sous-champs : on le referme ici.
            flushAuthor()
            currentTag = nil

        case "record":
            finishRecord()

        default:
            break
        }
        text = ""
    }

    // MARK: - Construction

    private func store(subfield code: String?, value: String) {
        guard let code, let tag = currentTag, !value.isEmpty else { return }
        switch (tag, code) {
        case ("010", "a"):
            isbn = normalizeISBN(value)
        case ("200", "a"):
            // Une notice peut porter plusieurs $a (titres parallèles) : le premier gagne.
            if title == nil { title = value }
        case ("200", "e"):
            if subtitle == nil { subtitle = value }
        case ("200", "f"):
            if responsibility == nil { responsibility = value }
        case ("210", "c"), ("214", "c"):
            if publisher == nil { publisher = value }
        case ("210", "d"), ("214", "d"):
            if year == nil { year = extractYear(value) }
        case ("700", "a"), ("701", "a"), ("702", "a"):
            flushAuthor()
            authorSurname = value
        case ("700", "b"), ("701", "b"), ("702", "b"):
            authorForename = value
        case ("606", "a"):
            if !subjects.contains(value) { subjects.append(value) }
        default:
            break
        }
    }

    private func flushAuthor() {
        guard let surname = authorSurname else {
            authorForename = nil
            return
        }
        let full = [authorForename, surname].compactMap { $0 }.joined(separator: " ")
        if !authors.contains(full) { authors.append(full) }
        authorSurname = nil
        authorForename = nil
    }

    private func finishRecord() {
        flushAuthor()
        defer { resetCurrentRecord() }
        guard let ppn, let title, !title.isEmpty else { return }
        records.append(SudocRecord(
            ppn: ppn,
            title: title,
            subtitle: subtitle,
            // Sans vedette auteur, la mention de responsabilité fait l'affaire.
            authors: authors.isEmpty ? responsibilityAuthors() : authors,
            publisher: publisher,
            year: year,
            isbn: isbn,
            subjects: subjects
        ))
    }

    private func responsibilityAuthors() -> [String] {
        guard let responsibility else { return [] }
        return responsibility
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func resetCurrentRecord() {
        ppn = nil; title = nil; subtitle = nil; responsibility = nil
        authorSurname = nil; authorForename = nil; authors = []
        publisher = nil; year = nil; isbn = nil; subjects = []
    }

    // MARK: - Nettoyage

    private func localName(_ elementName: String) -> String {
        elementName.split(separator: ":").last.map(String.init) ?? elementName
    }

    private func clean(_ raw: String) -> String {
        String(String.UnicodeScalarView(raw.unicodeScalars.filter { !Self.nonSorting.contains($0) }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :;,/"))
    }

    private func normalizeISBN(_ raw: String) -> String? {
        let digits = raw.uppercased().filter { $0.isNumber || $0 == "X" }
        return (digits.count == 10 || digits.count == 13) ? digits : nil
    }

    /// « DL 2023 », « cop. 1998 », « [2021] » → l'année.
    private func extractYear(_ raw: String) -> String? {
        let digits = raw.compactMap { $0.isNumber ? $0 : " " }
        return String(digits)
            .split(separator: " ")
            .map(String.init)
            .first { $0.count == 4 }
    }
}
