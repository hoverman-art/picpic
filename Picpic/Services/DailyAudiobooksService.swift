//
//  DailyAudiobooksService.swift
//  Picpic
//
//  « À écouter aujourd'hui » : les livres audio français les plus écoutés de
//  LibriVox, renouvelés chaque jour sur l'accueil.
//
//  Pourquoi Internet Archive et pas l'API de LibriVox. Mesuré le 9 septembre
//  2026 : `librivox.org/api/feed/audiobooks` ignore son propre paramètre
//  `language=` (une requête « French » renvoie « Count of Monte Cristo » en
//  anglais), répond en 15 à 17 s, et bloque les appels répétés en 403. Elle ne
//  publie aucun classement. Internet Archive héberge les mêmes enregistrements
//  et sa recherche accepte `language:fre`, trie par nombre de téléchargements
//  et répond en moins d'une seconde : 275 livres audio français, du plus
//  écouté au moins écouté — c'est ce classement-là qui fait la sélection.
//
//  Le tri est stable dans la journée et change chaque jour : la graine du
//  mélange est le numéro du jour. Deux lancements le même jour montrent la
//  même sélection ; demain elle aura tourné, sans un seul appel réseau de plus
//  puisque le catalogue est gardé vingt-quatre heures.
//

import Foundation

/// Un livre audio du domaine public, tel qu'Internet Archive le décrit.
nonisolated struct DailyAudiobook: Identifiable, Equatable, Codable, Sendable {
    /// Identifiant Archive.org, par exemple `comte_monte_cristo_jg_librivox`.
    let id: String
    let title: String
    let author: String

    /// La vignette du fonds, servie par Archive.org.
    var coverURL: URL? {
        URL(string: "https://archive.org/services/img/\(id)")
    }
}

actor DailyAudiobooksService {

    static let shared = DailyAudiobooksService()

    /// Combien de livres on garde en réserve pour tirer la sélection du jour.
    /// Assez pour que deux jours de suite ne se ressemblent pas, assez peu
    /// pour tenir dans les réglages sans peser.
    private static let poolSize = 60

    private let session: URLSession
    private let defaults: UserDefaults
    private var pool: [DailyAudiobook] = []

    private static let poolKey = "audio.dailyPool"
    private static let poolDayKey = "audio.dailyPoolDay"

    init(defaults: UserDefaults = .standard) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        session = URLSession(configuration: config)
        self.defaults = defaults
    }

    // MARK: - Sélection du jour

    /// Les livres audio du jour, prêts à afficher.
    func selection(count: Int = 6, on date: Date = .now) async -> [DailyAudiobook] {
        if ProcessInfo.processInfo.arguments.contains("-uitest-audio-stub") {
            return Array(Self.stub.prefix(count))
        }
        let catalogue = await catalogue(on: date)
        guard !catalogue.isEmpty else { return [] }
        return Self.pick(count, from: catalogue, day: Self.dayNumber(of: date))
    }

    /// Le catalogue entier, du plus écouté au moins écouté : ce que montre
    /// l'écran « Écouter gratuitement », là où l'accueil n'en tire que six.
    func mostListened(limit: Int = 20) async -> [DailyAudiobook] {
        if ProcessInfo.processInfo.arguments.contains("-uitest-audio-stub") {
            return Array(Self.stub.prefix(limit))
        }
        return Array(await catalogue(on: .now).prefix(limit))
    }

    /// Le catalogue, rechargé une fois par jour au plus.
    private func catalogue(on date: Date) async -> [DailyAudiobook] {
        let today = Self.dayNumber(of: date)
        if !pool.isEmpty, defaults.integer(forKey: Self.poolDayKey) == today { return pool }

        if let data = defaults.data(forKey: Self.poolKey),
           defaults.integer(forKey: Self.poolDayKey) == today,
           let saved = try? JSONDecoder().decode([DailyAudiobook].self, from: data),
           !saved.isEmpty {
            pool = saved
            return saved
        }

        let fetched = await fetchTopFrench()
        if !fetched.isEmpty {
            pool = fetched
            defaults.set(try? JSONEncoder().encode(fetched), forKey: Self.poolKey)
            defaults.set(today, forKey: Self.poolDayKey)
            return fetched
        }
        // Réseau absent : plutôt le catalogue d'hier qu'une étagère vide.
        if let data = defaults.data(forKey: Self.poolKey),
           let saved = try? JSONDecoder().decode([DailyAudiobook].self, from: data) {
            pool = saved
            return saved
        }
        return []
    }

    /// Numéro du jour depuis 1970 : c'est lui qui fait tourner la sélection.
    static func dayNumber(of date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 86_400)
    }

    /// Tire `count` livres dans le catalogue, de façon reproductible pour un
    /// jour donné. Le tirage est déterministe : deux appels le même jour
    /// donnent la même liste, sur cet iPhone comme sur un autre.
    static func pick(_ count: Int, from catalogue: [DailyAudiobook], day: Int) -> [DailyAudiobook] {
        guard !catalogue.isEmpty else { return [] }
        var generator = SeededGenerator(seed: UInt64(bitPattern: Int64(day)) &* 6_364_136_223_846_793_005 &+ 1)
        var indices = Array(catalogue.indices)
        // Mélange de Fisher-Yates, avec notre propre source de hasard : celle
        // du système changerait d'un lancement à l'autre.
        for position in indices.indices.reversed() where position > 0 {
            let other = Int(generator.next() % UInt64(position + 1))
            indices.swapAt(position, other)
        }
        return indices.prefix(count).map { catalogue[$0] }
    }

    // MARK: - Le catalogue chez Internet Archive

    private struct SearchResponse: Decodable {
        struct Response: Decodable {
            struct Doc: Decodable {
                let identifier: String
                let title: String?
                /// Archive.org renvoie tantôt une chaîne, tantôt un tableau.
                let creator: OneOrMany?
            }
            let docs: [Doc]
        }
        let response: Response
    }

    /// Un champ qui peut arriver seul ou en liste : `creator` chez Archive.org.
    private enum OneOrMany: Decodable {
        case one(String)
        case many([String])

        var first: String? {
            switch self {
            case .one(let value): return value
            case .many(let values): return values.first
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) { self = .one(value) }
            else { self = .many(try container.decode([String].self)) }
        }
    }

    private func fetchTopFrench() async -> [DailyAudiobook] {
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        components.queryItems = [
            // `language:fre` et pas `language:French` : la seconde forme ne
            // renvoie qu'un seul livre, la première les 275 du fonds.
            URLQueryItem(name: "q", value: "collection:librivoxaudio AND language:fre"),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "creator"),
            URLQueryItem(name: "sort[]", value: "downloads desc"),
            URLQueryItem(name: "rows", value: String(Self.poolSize)),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "output", value: "json"),
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data)
        else { return [] }

        return decoded.response.docs.compactMap { doc in
            guard let title = doc.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { return nil }
            return DailyAudiobook(id: doc.identifier,
                                  title: title,
                                  author: doc.creator?.first ?? "Anonyme")
        }
    }

    // MARK: - Les pistes, au moment d'écouter

    private struct MetadataResponse: Decodable {
        struct File: Decodable {
            let name: String
            let title: String?
            let format: String?
            let length: String?
        }
        struct Metadata: Decodable {
            let title: String?
            let runtime: String?
        }
        let files: [File]
        let metadata: Metadata?
    }

    /// Les chapitres d'un livre audio, dans le format que sait jouer la
    /// liseuse audio. Résolu à l'ouverture seulement : la sélection du jour
    /// n'a besoin que des titres, et une fiche pèse plus d'un mégaoctet.
    func audiobook(_ pick: DailyAudiobook) async -> FreeAudiobook? {
        if ProcessInfo.processInfo.arguments.contains("-uitest-audio-stub") {
            return FreeReadingService.stubMatch.audiobook
        }
        guard let url = URL(string: "https://archive.org/metadata/\(pick.id)"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(MetadataResponse.self, from: data)
        else { return nil }

        // Le même chapitre est publié en plusieurs qualités : on garde le VBR,
        // le plus répandu, et on retombe sur le 64 kbps quand il manque.
        let preferred = decoded.files.filter { $0.format == "VBR MP3" }
        let files = preferred.isEmpty
            ? decoded.files.filter { ($0.format ?? "").hasSuffix("MP3") }
            : preferred

        let sections = files.enumerated().compactMap { index, file -> FreeAudiobook.Section? in
            let escaped = file.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.name
            guard let listenURL = URL(string: "https://archive.org/download/\(pick.id)/\(escaped)") else { return nil }
            return FreeAudiobook.Section(
                id: index,
                title: file.title ?? "Chapitre \(index + 1)",
                listenURL: listenURL,
                playtime: file.length.map(Self.readableLength)
            )
        }
        guard !sections.isEmpty else { return nil }
        return FreeAudiobook(title: decoded.metadata?.title ?? pick.title,
                             sections: sections,
                             totalTimeLabel: decoded.metadata?.runtime)
    }

    /// Archive.org donne tantôt « 1109.01 » (secondes), tantôt « 18:28 ».
    static func readableLength(_ raw: String) -> String {
        guard let seconds = Double(raw) else { return raw }
        let total = Int(seconds.rounded())
        let minutes = total / 60, remainder = total % 60
        return String(format: "%d:%02d", minutes, remainder)
    }

    // MARK: - Hasard reproductible

    /// Générateur à graine : le tirage du jour doit être le même à chaque
    /// ouverture de l'application, donc pas question d'utiliser `SystemRandom`.
    struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

        mutating func next() -> UInt64 {
            // xorshift64* : court, sans dépendance, et suffisant pour tirer
            // six livres dans soixante.
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 2_685_821_657_736_338_717
        }
    }

    // MARK: - Bouchon pour les tests UI

    static let stub: [DailyAudiobook] = [
        DailyAudiobook(id: "fables_de_la_fontaine_librivox", title: "Fables de La Fontaine, livre 01", author: "Jean de La Fontaine"),
        DailyAudiobook(id: "comte_monte_cristo_jg_librivox", title: "Le Comte de Monte Cristo", author: "Alexandre Dumas"),
        DailyAudiobook(id: "tour_du_monde_80_jours_librivox", title: "Le tour du monde en quatre-vingts jours", author: "Jules Verne"),
    ]
}
