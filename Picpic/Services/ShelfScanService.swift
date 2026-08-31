//
//  ShelfScanService.swift
//  Picpic
//
//  Scan d'étagère : OCR Vision sur la photo (les tranches sont souvent
//  verticales, donc trois passes d'orientation), puis rapprochement de
//  chaque texte de tranche avec Google Books — tout en direct depuis
//  l'iPhone, zéro backend.
//

import UIKit
@preconcurrency import Vision

struct ShelfCandidate: Identifiable {
    let id = UUID()
    var spineText: String
    var isbn: String
    var title: String
    var authors: [String]
    var coverURLString: String?
    var isSelected = true

    var authorsLabel: String {
        authors.isEmpty ? "Auteur inconnu" : authors.joined(separator: ", ")
    }
}

enum ShelfScanError: LocalizedError {
    case noText
    case noMatch

    var errorDescription: String? {
        switch self {
        case .noText:
            return "Aucun titre lisible sur cette photo. Rapproche-toi des tranches et vérifie la lumière."
        case .noMatch:
            return "Impossible de reconnaître ces livres. Essaie une photo plus nette, tranche par tranche."
        }
    }
}

struct ShelfScanService {
    private let session: URLSession = .shared

    /// Nombre max de tranches interrogées (politesse envers l'API gratuite).
    private static let maxSpines = 25

    // MARK: - Pipeline

    func scan(image: UIImage) async throws -> [ShelfCandidate] {
        let spines = try await detectSpineTexts(in: image)
        guard !spines.isEmpty else { throw ShelfScanError.noText }
        let candidates = await matchBooks(from: Array(spines.prefix(Self.maxSpines)))
        guard !candidates.isEmpty else { throw ShelfScanError.noMatch }
        return candidates
    }

    // MARK: - OCR (Vision)

    /// Trois passes : texte horizontal, et tranches verticales lues dans les
    /// deux sens (haut→bas et bas→haut).
    private func detectSpineTexts(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { throw ShelfScanError.noText }

        var texts: [String] = []
        for orientation in [CGImagePropertyOrientation.up, .right, .left] {
            let lines = try await recognizeText(in: cgImage, orientation: orientation)
            texts.append(contentsOf: lines)
        }

        // Nettoyage + dédoublonnage insensible à la casse, ordre conservé.
        var seen = Set<String>()
        return texts.compactMap { raw in
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let letters = text.filter(\.isLetter)
            guard text.count >= 4, letters.count >= 4 else { return nil }
            guard seen.insert(text.lowercased()).inserted else { return nil }
            return text
        }
    }

    private func recognizeText(in cgImage: CGImage,
                               orientation: CGImagePropertyOrientation) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { observation -> String? in
                    guard let top = observation.topCandidates(1).first,
                          top.confidence > 0.4 else { return nil }
                    return top.string
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["fr-FR", "en-US"]
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Rapprochement Google Books

    /// Une requête par tranche, par lots de 4 en parallèle, dédoublonnées par
    /// ISBN (le titre et l'auteur d'une même tranche retombent sur le même livre).
    private func matchBooks(from spineTexts: [String]) async -> [ShelfCandidate] {
        var candidates: [ShelfCandidate] = []
        var seenISBNs = Set<String>()
        for chunk in spineTexts.chunked(into: 4) {
            let chunkResults = await withTaskGroup(of: ShelfCandidate?.self) { group in
                for text in chunk {
                    group.addTask { try? await self.searchGoogleBooks(spineText: text) }
                }
                var found: [ShelfCandidate] = []
                for await candidate in group {
                    if let candidate { found.append(candidate) }
                }
                return found
            }
            for candidate in chunkResults where seenISBNs.insert(candidate.isbn).inserted {
                candidates.append(candidate)
            }
        }
        return candidates
    }

    private struct GBSearchResponse: Decodable {
        struct Item: Decodable {
            struct VolumeInfo: Decodable {
                struct Identifier: Decodable { let type: String?; let identifier: String? }
                struct ImageLinks: Decodable { let thumbnail: String? }
                let title: String?
                let authors: [String]?
                let industryIdentifiers: [Identifier]?
                let imageLinks: ImageLinks?
            }
            let volumeInfo: VolumeInfo
        }
        let items: [Item]?
    }

    private func searchGoogleBooks(spineText: String) async throws -> ShelfCandidate? {
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        components.queryItems = [
            URLQueryItem(name: "q", value: spineText),
            URLQueryItem(name: "maxResults", value: "3"),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "country", value: "FR"),
        ]
        guard let url = components.url else { return nil }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let decoded = try JSONDecoder().decode(GBSearchResponse.self, from: data)

        for item in decoded.items ?? [] {
            let info = item.volumeInfo
            guard let title = info.title,
                  let isbn = info.industryIdentifiers?
                      .first(where: { $0.type == "ISBN_13" })?.identifier,
                  matches(spineText: spineText, title: title, authors: info.authors ?? [])
            else { continue }
            return ShelfCandidate(
                spineText: spineText,
                isbn: isbn,
                title: title,
                authors: info.authors ?? [],
                coverURLString: info.imageLinks?.thumbnail?
                    .replacingOccurrences(of: "http://", with: "https://")
            )
        }
        return nil
    }

    /// Garde-fou anti-faux positifs : au moins un mot significatif de la
    /// tranche doit se retrouver dans le titre ou les auteurs proposés.
    private func matches(spineText: String, title: String, authors: [String]) -> Bool {
        let haystack = ([title] + authors).joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let tokens = spineText
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.count >= 4 }
        guard !tokens.isEmpty else { return false }
        return tokens.contains { haystack.contains($0) }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
