//
//  WikipediaSummaryService.swift
//  Picpic
//
//  Le résumé d'un livre scanné, quand les catalogues n'en ont pas.
//
//  Mesuré le 9 septembre 2026 : Google Books — la seule source de Picpic qui
//  portait un résumé — répondait HTTP 429 sur le quota partagé de l'accès sans
//  clé. Un scan sortait alors une fiche sans une ligne de description, ce qui
//  est précisément ce qu'on regarde quand on tient un livre inconnu en main.
//
//  Wikipédia en français comble ce trou pour les œuvres qui ont un article :
//  classiques, romans connus, essais commentés — c'est-à-dire l'essentiel de
//  ce qu'on croise en brocante. L'API REST rend un résumé d'introduction déjà
//  nettoyé, sans clé et sans quota.
//
//  Ce n'est pas Picpic qui résume l'œuvre : le texte est celui de Wikipédia,
//  et il est présenté comme tel dans la fiche (licence CC BY-SA).
//

import Foundation

nonisolated struct WikipediaSummary: Equatable, Sendable {
    let title: String
    let extract: String
    let pageURL: URL?
}

struct WikipediaSummaryService {

    static let shared = WikipediaSummaryService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    /// Cherche l'article de l'œuvre, puis en rend le résumé d'introduction.
    func summary(title: String, authors: [String]) async -> WikipediaSummary? {
        guard let page = await searchPage(title: title, authors: authors) else { return nil }
        return await extract(page: page)
    }

    /// L'article le plus proche du couple titre + auteur.
    ///
    /// La recherche inclut l'auteur : « L'Étranger » seul tombe sur une page
    /// d'homonymie, avec l'auteur elle tombe sur le roman.
    private func searchPage(title: String, authors: [String]) async -> String? {
        let terms = ([title] + authors.prefix(1)).joined(separator: " ")
        var components = URLComponents(string: "https://fr.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: terms),
            URLQueryItem(name: "srlimit", value: "5"),
            URLQueryItem(name: "format", value: "json"),
        ]
        struct Response: Decodable {
            struct Query: Decodable {
                struct Result: Decodable { let title: String }
                let search: [Result]
            }
            let query: Query?
        }
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else { return nil }

        let candidates = decoded.query?.search.map(\.title) ?? []
        // Un article dont le titre ne ressemble pas du tout au livre parle
        // d'autre chose : mieux vaut pas de résumé qu'un résumé faux.
        return candidates.first { Self.plausible(page: $0, title: title) }
    }

    /// Le titre de l'article doit contenir celui du livre, ou l'inverse.
    static func plausible(page: String, title: String) -> Bool {
        func normalize(_ text: String) -> String {
            text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                         locale: Locale(identifier: "fr_FR"))
                .filter { $0.isLetter || $0.isNumber || $0 == " " }
                .trimmingCharacters(in: .whitespaces)
        }
        let page = normalize(page), book = normalize(title)
        guard book.count >= 4 else { return false }
        return page.contains(book) || book.contains(page)
    }

    private func extract(page: String) async -> WikipediaSummary? {
        let escaped = page.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? page
        guard let url = URL(string: "https://fr.wikipedia.org/api/rest_v1/page/summary/\(escaped)"),
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }

        struct Response: Decodable {
            struct URLs: Decodable { let page: String? }
            struct Links: Decodable { let desktop: URLs? }
            let title: String?
            let extract: String?
            let type: String?
            let content_urls: Links?
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              // Une page d'homonymie n'est pas un résumé.
              decoded.type != "disambiguation",
              let extract = decoded.extract?.trimmingCharacters(in: .whitespacesAndNewlines),
              extract.count >= 80
        else { return nil }

        return WikipediaSummary(
            title: decoded.title ?? page,
            extract: extract,
            pageURL: decoded.content_urls?.desktop?.page.flatMap(URL.init(string:))
        )
    }
}
