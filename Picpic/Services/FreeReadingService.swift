//
//  FreeReadingService.swift
//  Picpic
//
//  « Écouter gratuitement » : pour un livre du domaine public, retrouve son
//  enregistrement LibriVox — en direct depuis l'iPhone, zéro backend.
//
//  Le pendant écrit — l'EPUB de Gutendex ou de Wikisource, lu dans une liseuse
//  maison — a été retiré le 10 septembre 2026. Le gratuit de Picpic est
//  désormais sonore : c'est ce qui marche sans réserve (le fonds LibriVox est
//  classé par écoutes, les fichiers sont de simples MP3), là où la liseuse
//  demandait d'analyser des EPUB de structures imprévisibles pour un résultat
//  que personne ne réclamait. Voir docs/AUDIO-PLUTOT-QUE-EPUB.md.
//

import Foundation

// MARK: - Modèles

struct FreeAudiobook: Equatable {
    struct Section: Equatable, Identifiable {
        let id: Int
        let title: String
        let listenURL: URL
        let playtime: String?
    }
    let title: String
    let sections: [Section]
    let totalTimeLabel: String?
}

struct FreeReadingMatch: Equatable {
    var audiobook: FreeAudiobook?

    var isEmpty: Bool { audiobook == nil }
}

// MARK: - Service

actor FreeReadingService {
    static let shared = FreeReadingService()

    private let session: URLSession
    /// Résultats (y compris négatifs) par ISBN : les catalogues du domaine
    /// public bougent peu, et ça absorbe les démarrages lents de Gutendex.
    private var cache: [String: FreeReadingMatch] = [:]

    init() {
        let config = URLSessionConfiguration.default
        // 25 s était bien trop long : quand un endpoint ne répond plus (c'est
        // arrivé à la recherche Gutendex), l'écran tourne dans le vide et,
        // pire, les requêtes bloquées saturent la file vers le même hôte et
        // font expirer celles qui, elles, marchent.
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    /// Budget de temps propre à un appel, plus court que celui de la session :
    /// un catalogue lent ne doit pas retenir tout l'écran.
    private func withBudget<T: Sendable>(
        _ seconds: Double,
        operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    func match(isbn: String, title: String, authors: [String]) async -> FreeReadingMatch {
        if ProcessInfo.processInfo.arguments.contains("-uitest-freereading-stub") {
            return Self.stubMatch
        }
        if let cached = cache[isbn] { return cached }
        let match = FreeReadingMatch(audiobook: await findAudiobook(title: title, authors: authors))
        cache[isbn] = match
        return match
    }

    // MARK: - Audio : LibriVox

    private struct LibriVoxResponse: Decodable {
        struct AudioBook: Decodable {
            struct Section: Decodable {
                let section_number: String?
                let title: String?
                let listen_url: String?
                let playtime: String?
            }
            let title: String?
            let language: String?
            let totaltime: String?
            let authors: [Author]?
            let sections: [Section]?
            struct Author: Decodable { let last_name: String? }
        }
        let books: [AudioBook]?
    }

    func findAudiobook(title: String, authors: [String]) async -> FreeAudiobook? {
        // La curation montre que le filtre `language=` de l'API est ignoré et
        // que `title=` est fragile : on cherche par auteur puis on matche ici.
        guard let family = authors.compactMap(Self.familyName).first else { return nil }
        var components = URLComponents(string: "https://librivox.org/api/feed/audiobooks/")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "extended", value: "1"),
            URLQueryItem(name: "author", value: family),
            URLQueryItem(name: "limit", value: "50"),
        ]
        guard let url = components.url,
              let decoded: LibriVoxResponse = await get(url) else { return nil }

        for book in decoded.books ?? [] {
            guard book.language == "French",
                  let bookTitle = book.title,
                  Self.titlesMatch(query: title, candidate: bookTitle) else { continue }
            let sections = (book.sections ?? []).enumerated().compactMap { index, section -> FreeAudiobook.Section? in
                guard let raw = section.listen_url,
                      let listenURL = URL(string: raw.replacingOccurrences(of: " ", with: "%20")) else { return nil }
                return FreeAudiobook.Section(
                    id: Int(section.section_number ?? "") ?? index,
                    title: section.title ?? "Chapitre \(index + 1)",
                    listenURL: listenURL,
                    playtime: section.playtime
                )
            }
            guard !sections.isEmpty else { continue }
            return FreeAudiobook(title: bookTitle, sections: sections, totalTimeLabel: book.totaltime)
        }
        return nil
    }

    // MARK: - Réseau

    private func get<T: Decodable>(_ url: URL) async -> T? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Matching anti-faux-positifs

    /// Minuscules sans diacritiques, articles initiaux et sous-titres retirés
    /// (« Candide, ou l'Optimisme » → « candide »).
    static func normalized(_ title: String) -> String {
        var text = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
        for separator in [" : ", " ; ", " ou ", ", ou "] {
            if let range = text.range(of: separator) {
                text = String(text[..<range.lowerBound])
            }
        }
        for article in ["le ", "la ", "les ", "l'", "l’", "un ", "une ", "des "] {
            if text.hasPrefix(article) {
                text = String(text.dropFirst(article.count))
                break
            }
        }
        let cleaned = text.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    static func familyName(_ author: String) -> String? {
        let parts = author
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .split(whereSeparator: { !$0.isLetter })
            .filter { $0.count >= 2 }
        return parts.last.map { String($0) }
    }

    /// Les deux titres normalisés doivent se contenir l'un l'autre.
    static func titlesMatch(query: String, candidate: String) -> Bool {
        let q = normalized(query), c = normalized(candidate)
        guard q.count >= 3, c.count >= 3 else { return false }
        return c.contains(q) || q.contains(c)
    }

    /// Sans auteur connu on reste prudent ; sinon un nom de famille doit matcher.
    static func authorsMatch(query: [String], candidates: [String]) -> Bool {
        let queryNames = query.compactMap(familyName)
        guard !queryNames.isEmpty else { return true }
        let haystack = candidates
            .map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")) }
            .joined(separator: " ")
        return queryNames.contains { haystack.contains($0) }
    }

    // MARK: - Stubs hors-ligne pour les tests UI

    static let stubMatch = FreeReadingMatch(
        audiobook: FreeAudiobook(
            title: "Candide ou l'optimisme",
            sections: [
                FreeAudiobook.Section(id: 1, title: "Chapitre 01", playtimeStub: "5:12"),
                FreeAudiobook.Section(id: 2, title: "Chapitre 02", playtimeStub: "4:47"),
            ],
            totalTimeLabel: "3:23:11"
        )
    )

}

private extension FreeAudiobook.Section {
    /// Section de stub : URL factice jamais jouée dans les tests UI.
    nonisolated init(id: Int, title: String, playtimeStub: String) {
        self.init(id: id, title: title,
                  listenURL: URL(string: "https://example.com/stub.mp3")!,
                  playtime: playtimeStub)
    }
}
