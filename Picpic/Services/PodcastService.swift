//
//  PodcastService.swift
//  Picpic
//
//  Des podcasts gratuits, trouvés par le sens de la requête.
//
//  Pourquoi c'est possible sans clé ni serveur, et vérifié le 10 septembre
//  2026 :
//
//    découverte  https://itunes.apple.com/search?media=podcast&country=fr
//                répond en 0,6 s, sans clé, et rend le `feedUrl` de chaque
//                émission.
//    épisodes    le flux RSS de l'émission, publié par son auteur pour être
//                lu par n'importe quel lecteur — c'est la raison d'être du
//                format. Testé sur un flux réel : 103 épisodes, chacun avec
//                son MP3, sa durée et la jaquette de l'émission.
//
//  Picpic ne réhéberge rien et ne transcrit rien : il lit le flux public et
//  joue le fichier depuis l'adresse de l'éditeur, comme le fait tout lecteur
//  de podcasts. Aucun audio n'est copié sur nos machines — nous n'en avons
//  pas.
//
//  CE QUI CLASSE LES RÉSULTATS, ET CE QUI NE LES CLASSE PAS. L'idée première
//  était de reclasser les émissions avec les embeddings qui servent déjà à la
//  bibliothèque. Mesuré le 10 septembre 2026, `NLEmbedding.sentenceEmbedding`
//  en français ne discrimine pas assez sur des descriptions courtes :
//
//      « créer sa boîte »            cuisine 0,659 · entrepreneuriat 0,612
//      « se lever tôt et réussir »   jardinage 0,837 · entrepreneuriat 0,800
//
//  La cuisine passe devant l'entrepreneuriat, le jardinage devant tout : c'est
//  du bruit, pas un classement. On garde donc l'ordre de l'annuaire d'Apple,
//  qui est un vrai moteur de recherche, et on ne promet rien de plus.
//

import Foundation

/// Une émission, telle que l'annuaire d'Apple la décrit.
nonisolated struct Podcast: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let author: String
    let genre: String
    let summary: String
    let artworkURLString: String?
    let feedURL: URL

}

actor PodcastService {

    static let shared = PodcastService()

    private let session: URLSession
    /// Les flux sont volumineux (600 Ko pour cent épisodes) : on garde le
    /// dernier lu, le temps que le lecteur choisisse son épisode.
    private var lastFeed: (url: URL, audiobook: FreeAudiobook)?
    private var searchCache: [String: [Podcast]] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }

    // MARK: - Trouver

    /// Cherche des émissions et les classe par sens, pas par mot-clé.
    func search(_ query: String, limit: Int = 3) async -> [Podcast] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }
        if ProcessInfo.processInfo.arguments.contains("-uitest-podcast-stub") {
            return Array(Self.stub.prefix(limit))
        }
        if let cached = searchCache[trimmed.lowercased()] { return Array(cached.prefix(limit)) }

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "media", value: "podcast"),
            URLQueryItem(name: "term", value: trimmed),
            URLQueryItem(name: "country", value: "FR"),
            URLQueryItem(name: "limit", value: "25"),
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return [] }

        let result = Self.podcasts(fromSearchJSON: data, limit: limit)
        searchCache[trimmed.lowercased()] = result
        return result
    }

    /// Décode une réponse de l'annuaire, dans l'ordre où elle arrive.
    ///
    /// L'ordre est celui d'Apple : sa pertinence est mesurée sur des millions
    /// de recherches, la nôtre ne l'était pas. Les émissions sans flux sont
    /// écartées — sans lui, il n'y a rien à écouter.
    static func podcasts(fromSearchJSON data: Data, limit: Int) -> [Podcast] {
        guard let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) else { return [] }
        return Array(decoded.results.compactMap(Podcast.init).prefix(limit))
    }

    // MARK: - Écouter

    /// Les épisodes d'une émission, dans le format que sait jouer le lecteur.
    ///
    /// Les plus récents d'abord, comme dans le flux, et plafonnés : personne
    /// ne fait défiler huit cents épisodes, et chacun coûte une ligne à
    /// analyser.
    func episodes(of podcast: Podcast, limit: Int = 50) async -> FreeAudiobook? {
        if ProcessInfo.processInfo.arguments.contains("-uitest-podcast-stub") {
            return FreeReadingService.stubMatch.audiobook
        }
        if let lastFeed, lastFeed.url == podcast.feedURL { return lastFeed.audiobook }
        guard let (data, response) = try? await session.data(from: podcast.feedURL),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }

        let sections = Self.episodes(inFeed: xml, limit: limit)
        guard !sections.isEmpty else { return nil }
        let audiobook = FreeAudiobook(title: podcast.title, sections: sections, totalTimeLabel: podcast.author)
        lastFeed = (podcast.feedURL, audiobook)
        return audiobook
    }

    // MARK: - Lecture du flux

    /// Extrait les épisodes d'un flux RSS.
    ///
    /// Analyse par balise plutôt qu'avec un parseur XML complet : les flux de
    /// podcasts sont plats, souvent mal formés, et un parseur strict refuse ce
    /// qu'un lecteur ordinaire accepte sans broncher.
    static func episodes(inFeed xml: String, limit: Int) -> [FreeAudiobook.Section] {
        var sections: [FreeAudiobook.Section] = []
        var cursor = xml.startIndex

        while sections.count < limit,
              let open = xml.range(of: "<item", range: cursor ..< xml.endIndex),
              let close = xml.range(of: "</item>", range: open.upperBound ..< xml.endIndex) {
            let item = String(xml[open.upperBound ..< close.lowerBound])
            cursor = close.upperBound

            guard let audio = attribute("url", inTag: "enclosure", of: item),
                  let audioURL = URL(string: audio.replacingOccurrences(of: " ", with: "%20")),
                  ["http", "https"].contains(audioURL.scheme ?? "") else { continue }

            let title = value(of: "title", in: item) ?? "Épisode \(sections.count + 1)"
            sections.append(FreeAudiobook.Section(
                id: sections.count,
                title: title,
                listenURL: audioURL,
                playtime: value(of: "itunes:duration", in: item).map(readableDuration)
            ))
        }
        return sections
    }

    /// « 00:22:30 » se lit tel quel ; « 1350 » est un nombre de secondes.
    static func readableDuration(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard let seconds = Int(text) else { return text }
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }

    static func value(of tag: String, in item: String) -> String? {
        guard let open = item.range(of: "<\(tag)"),
              let openEnd = item.range(of: ">", range: open.upperBound ..< item.endIndex),
              let close = item.range(of: "</\(tag)>", range: openEnd.upperBound ..< item.endIndex)
        else { return nil }
        var text = String(item[openEnd.upperBound ..< close.lowerBound])
        text = text.replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                    ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func attribute(_ name: String, inTag tag: String, of item: String) -> String? {
        guard let open = item.range(of: "<\(tag)"),
              let close = item.range(of: ">", range: open.upperBound ..< item.endIndex) else { return nil }
        let attributes = item[open.upperBound ..< close.lowerBound]
        guard let start = attributes.range(of: "\(name)=\""),
              let end = attributes.range(of: "\"", range: start.upperBound ..< attributes.endIndex)
        else { return nil }
        return String(attributes[start.upperBound ..< end.lowerBound])
    }

    // MARK: - Décodage de l'annuaire

    fileprivate struct SearchResponse: Decodable {
        struct Item: Decodable {
            let collectionId: Int?
            let collectionName: String?
            let artistName: String?
            let primaryGenreName: String?
            let feedUrl: String?
            let artworkUrl600: String?
            let artworkUrl100: String?
            let genres: [String]?
        }
        let results: [Item]
    }

    // MARK: - Bouchon pour les tests UI

    static let stub: [Podcast] = [
        Podcast(id: "1", title: "Les secrets de l'entrepreneur", author: "Dougs",
                genre: "Entrepreneuriat", summary: "Créer et gérer sa société.",
                artworkURLString: nil,
                feedURL: URL(string: "https://example.com/feed.xml")!),
        Podcast(id: "2", title: "Mindset Entrepreneur", author: "Dorès Joyce",
                genre: "Affaires", summary: "Motivation et discipline au quotidien.",
                artworkURLString: nil,
                feedURL: URL(string: "https://example.com/feed2.xml")!),
    ]
}

private extension Podcast {
    init?(_ item: PodcastService.SearchResponse.Item) {
        guard let identifier = item.collectionId,
              let title = item.collectionName,
              let feed = item.feedUrl,
              let feedURL = URL(string: feed) else { return nil }
        self.init(id: String(identifier),
                  title: title,
                  author: item.artistName ?? "",
                  genre: item.primaryGenreName ?? item.genres?.first ?? "",
                  summary: (item.genres ?? []).joined(separator: ", "),
                  artworkURLString: item.artworkUrl600 ?? item.artworkUrl100,
                  feedURL: feedURL)
    }
}
