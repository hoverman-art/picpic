//
//  FreeReadingService.swift
//  Picpic
//
//  « Lire / écouter gratuitement » : pour un livre du domaine public,
//  retrouve un EPUB gratuit (Gutendex, puis Wikisource via ws-export)
//  et un livre audio LibriVox — en direct depuis l'iPhone, zéro backend.
//  Sources et pièges validés par la curation (docs/CURATION-OPEN-DATA-LECTURE.md).
//

import Foundation

// MARK: - Modèles

struct FreeEbook: Equatable {
    enum Source: String { case gutenberg = "Projet Gutenberg", wikisource = "Wikisource" }
    let source: Source
    let title: String
    let epubURL: URL
}

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
    var ebook: FreeEbook?
    var audiobook: FreeAudiobook?

    var isEmpty: Bool { ebook == nil && audiobook == nil }
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
        // Gutendex et LibriVox peuvent mettre >15 s à froid (curation).
        config.timeoutIntervalForRequest = 25
        session = URLSession(configuration: config)
    }

    func match(isbn: String, title: String, authors: [String]) async -> FreeReadingMatch {
        if ProcessInfo.processInfo.arguments.contains("-uitest-freereading-stub") {
            return Self.stubMatch
        }
        if let cached = cache[isbn] { return cached }
        async let ebook = findEbook(title: title, authors: authors)
        async let audio = findAudiobook(title: title, authors: authors)
        let match = FreeReadingMatch(ebook: await ebook, audiobook: await audio)
        cache[isbn] = match
        return match
    }

    // MARK: - Ebooks : Gutendex puis Wikisource

    private struct GutendexResponse: Decodable {
        struct BookItem: Decodable {
            struct Author: Decodable { let name: String? }
            let title: String?
            let authors: [Author]?
            let languages: [String]?
            let formats: [String: String]?
        }
        let results: [BookItem]?
    }

    func findEbook(title: String, authors: [String]) async -> FreeEbook? {
        if let hit = await searchGutendex(title: title, authors: authors) {
            return hit
        }
        return await searchWikisource(title: title)
    }

    private func searchGutendex(title: String, authors: [String]) async -> FreeEbook? {
        var components = URLComponents(string: "https://gutendex.com/books/")!
        let query = ([Self.normalized(title)] + authors.compactMap(Self.familyName))
            .joined(separator: " ")
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "languages", value: "fr"),
        ]
        guard let url = components.url,
              let decoded: GutendexResponse = await get(url) else { return nil }

        for item in decoded.results ?? [] {
            guard let itemTitle = item.title,
                  item.languages?.contains("fr") != false,
                  Self.titlesMatch(query: title, candidate: itemTitle),
                  Self.authorsMatch(query: authors, candidates: item.authors?.compactMap(\.name) ?? []),
                  let epub = item.formats?["application/epub+zip"],
                  let epubURL = URL(string: epub) else { continue }
            return FreeEbook(source: .gutenberg, title: itemTitle, epubURL: epubURL)
        }
        return nil
    }

    private struct WikisourceResponse: Decodable {
        struct Query: Decodable {
            struct Result: Decodable { let title: String? }
            let search: [Result]?
        }
        let query: Query?
    }

    private func searchWikisource(title: String) async -> FreeEbook? {
        var components = URLComponents(string: "https://fr.wikisource.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: "intitle:\"\(Self.normalized(title))\""),
            URLQueryItem(name: "srlimit", value: "10"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url,
              let decoded: WikisourceResponse = await get(url) else { return nil }

        // Les titres avec « / » sont des sous-pages (chapitres) : on garde l'œuvre.
        for result in decoded.query?.search ?? [] {
            guard let page = result.title,
                  !page.contains("/"),
                  Self.titlesMatch(query: title, candidate: page) else { continue }
            var export = URLComponents(string: "https://ws-export.wmcloud.org/")!
            export.queryItems = [
                URLQueryItem(name: "format", value: "epub"),
                URLQueryItem(name: "lang", value: "fr"),
                URLQueryItem(name: "page", value: page.replacingOccurrences(of: " ", with: "_")),
            ]
            guard let epubURL = export.url else { continue }
            return FreeEbook(source: .wikisource, title: page, epubURL: epubURL)
        }
        return nil
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

    // MARK: - Découverte (classiques populaires Gutendex)

    struct DiscoveryBook: Identifiable, Equatable {
        let id: String
        let title: String
        let author: String
        let epubURL: URL
        let coverURL: URL?
    }

    func popularClassics() async -> [DiscoveryBook] {
        if ProcessInfo.processInfo.arguments.contains("-uitest-freereading-stub") {
            return Self.stubDiscovery
        }
        var components = URLComponents(string: "https://gutendex.com/books/")!
        components.queryItems = [URLQueryItem(name: "languages", value: "fr")]
        guard let url = components.url,
              let decoded: GutendexResponse = await get(url) else { return [] }
        return (decoded.results ?? []).compactMap { item in
            guard let title = item.title,
                  let epub = item.formats?["application/epub+zip"],
                  let epubURL = URL(string: epub) else { return nil }
            let cover = item.formats?["image/jpeg"].flatMap(URL.init(string:))
            return DiscoveryBook(
                id: epub,
                title: title,
                author: item.authors?.first?.name ?? "Anonyme",
                epubURL: epubURL,
                coverURL: cover
            )
        }
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
        ebook: FreeEbook(source: .gutenberg,
                         title: "Candide, ou l'optimisme",
                         epubURL: URL(string: "https://www.gutenberg.org/ebooks/4650.epub3.images")!),
        audiobook: FreeAudiobook(
            title: "Candide ou l'optimisme",
            sections: [
                FreeAudiobook.Section(id: 1, title: "Chapitre 01", playtimeStub: "5:12"),
                FreeAudiobook.Section(id: 2, title: "Chapitre 02", playtimeStub: "4:47"),
            ],
            totalTimeLabel: "3:23:11"
        )
    )

    static let stubDiscovery: [DiscoveryBook] = [
        DiscoveryBook(id: "stub-1", title: "Candide, ou l'optimisme", author: "Voltaire",
                      epubURL: URL(string: "https://www.gutenberg.org/ebooks/4650.epub3.images")!,
                      coverURL: nil),
        DiscoveryBook(id: "stub-2", title: "Les Fleurs du mal", author: "Charles Baudelaire",
                      epubURL: URL(string: "https://www.gutenberg.org/ebooks/6099.epub3.images")!,
                      coverURL: nil),
    ]
}

private extension FreeAudiobook.Section {
    /// Section de stub : URL factice jamais jouée dans les tests UI.
    nonisolated init(id: Int, title: String, playtimeStub: String) {
        self.init(id: id, title: title,
                  listenURL: URL(string: "https://example.com/stub.mp3")!,
                  playtime: playtimeStub)
    }
}
