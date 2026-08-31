//
//  AvailabilityService.swift
//  Picpic
//
//  "Où trouver ce livre ?" — resolves a scanned ISBN against free,
//  open catalogues, straight from the device (zero backend):
//  - Sudoc (ABES web services, Licence Ouverte): isbn2ppn + multiwhere
//    give every French university library holding the book, with GPS.
//  - BU de La Rochelle (Minimes): Primo VE deep-link.
//  - Médiathèques de l'agglo de La Rochelle (Michel-Crépeau): portal deep-link
//    (no public API on the Syracuse portal — link only, by design).
//  - Librairies indépendantes (leslibraires.fr, dont Calligrammes): deep-link.
//  - Project Gutenberg (gutendex) for public-domain ebooks.
//

import Foundation
import CoreLocation

struct AvailabilitySource: Identifiable {
    enum Kind { case universityLibrary, publicLibrary, bookstore, freeEbook }

    let id = UUID()
    let kind: Kind
    let name: String
    let detail: String
    let url: URL

    var symbol: String {
        switch kind {
        case .universityLibrary: return "building.columns"
        case .publicLibrary: return "books.vertical"
        case .bookstore: return "storefront"
        case .freeEbook: return "arrow.down.circle"
        }
    }
}

/// A university library holding the book, from Sudoc multiwhere.
struct HoldingLibrary: Identifiable {
    private static let laRochelle = CLLocation(latitude: 46.1603, longitude: -1.1511)

    let id: String // RCR
    let name: String
    let coordinate: CLLocationCoordinate2D?

    /// Distance in km from La Rochelle city centre, if locatable.
    var distanceFromLaRochelle: Double? {
        guard let coordinate else { return nil }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return here.distance(from: Self.laRochelle) / 1000
    }
}

struct AvailabilityService {

    static let shared = AvailabilityService()
    private let session: URLSession = .shared

    /// Catalogue deep links, always offered for a given ISBN/title.
    /// Opened in Safari — these portals have no public API.
    func catalogueLinks(isbn: String, title: String) -> [AvailabilitySource] {
        var sources: [AvailabilitySource] = []

        if let url = URL(string: "https://larochelle.primo.exlibrisgroup.com/discovery/search?query=any,contains,\(isbn)&vid=33ULR_INST:NDE") {
            sources.append(AvailabilitySource(
                kind: .universityLibrary,
                name: "BU des Minimes",
                detail: "La Rochelle Université · catalogue Primo",
                url: url
            ))
        }
        if let url = URL(string: "https://mediatheques.agglo-larochelle.fr/Default/search.aspx?SC=DEFAULT&QUERY=\(isbn)") {
            sources.append(AvailabilitySource(
                kind: .publicLibrary,
                name: "Médiathèque Michel-Crépeau",
                detail: "Réseau des médiathèques · Agglo de La Rochelle",
                url: url
            ))
        }
        if let url = URL(string: "https://www.leslibraires.fr/recherche/?q=\(isbn)") {
            sources.append(AvailabilitySource(
                kind: .bookstore,
                name: "Librairies indépendantes",
                detail: "Stock en librairie (Calligrammes…) · leslibraires.fr",
                url: url
            ))
        }
        // URLComponents applies value-appropriate percent-encoding
        // (titles with & or + would otherwise corrupt the query).
        var gutenberg = URLComponents(string: "https://www.gutenberg.org/ebooks/search/")
        gutenberg?.queryItems = [URLQueryItem(name: "query", value: title)]
        if let url = gutenberg?.url {
            sources.append(AvailabilitySource(
                kind: .freeEbook,
                name: "Ebook gratuit",
                detail: "Domaine public · Project Gutenberg",
                url: url
            ))
        }
        return sources
    }

    // MARK: - Sudoc (ABES) — ISBN → university libraries holding the book

    /// Resolves an ISBN to Sudoc PPN identifiers (free ABES web service, 1 req/s).
    func sudocPPNs(isbn: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "https://www.sudoc.fr/services/isbn2ppn/\(isbn)")!)
        request.setValue("text/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }

        // {"sudoc":{"query":{"resultNoHolding"?, "result": {"ppn":"x"} | [{"ppn":"x"}]}}}
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sudoc = root["sudoc"] as? [String: Any],
              let query = sudoc["query"] as? [String: Any] else { return [] }

        if let result = query["result"] as? [String: Any] {
            return [result["ppn"]].compactMap { $0 as? String }
        }
        if let results = query["result"] as? [[String: Any]] {
            return results.compactMap { $0["ppn"] as? String }
        }
        return []
    }

    /// Lists every library holding the record, with GPS coordinates.
    func holdingLibraries(ppn: String) async throws -> [HoldingLibrary] {
        var request = URLRequest(url: URL(string: "https://www.sudoc.fr/services/multiwhere/\(ppn)")!)
        request.setValue("text/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sudoc = root["sudoc"] as? [String: Any],
              let query = sudoc["query"] as? [String: Any] else { return [] }

        let resultAny = query["result"]
        let entries: [[String: Any]]
        if let single = resultAny as? [String: Any] {
            entries = [single]
        } else if let many = resultAny as? [[String: Any]] {
            entries = many
        } else {
            return []
        }

        var libraries: [HoldingLibrary] = []
        for entry in entries {
            let libAny = entry["library"]
            let libs: [[String: Any]]
            if let one = libAny as? [String: Any] { libs = [one] }
            else if let many = libAny as? [[String: Any]] { libs = many }
            else { continue }

            for lib in libs {
                guard let rcr = stringValue(lib["rcr"]), let name = stringValue(lib["shortname"]) else { continue }
                var coordinate: CLLocationCoordinate2D?
                if let lat = doubleValue(lib["latitude"]), let lon = doubleValue(lib["longitude"]) {
                    coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                }
                libraries.append(HoldingLibrary(id: rcr, name: name, coordinate: coordinate))
            }
        }
        // Deduplicate by RCR, nearest to La Rochelle first.
        // Decorate-sort-undecorate: one distance computation per library.
        var seen = Set<String>()
        return libraries
            .filter { seen.insert($0.id).inserted }
            .map { ($0, $0.distanceFromLaRochelle ?? .infinity) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Sudoc notice URL for a resolved PPN.
    func sudocNoticeURL(ppn: String) -> URL? {
        URL(string: "https://www.sudoc.fr/\(ppn)")
    }

    private func stringValue(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let s = any as? String { return Double(s) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }
}
