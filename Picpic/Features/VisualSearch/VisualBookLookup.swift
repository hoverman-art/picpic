//
//  VisualBookLookup.swift
//  Picpic
//
//  Reconnaître un livre à partir de ce que l'appareil photo voit.
//
//  C'est le moteur derrière l'intégration à la recherche visuelle d'iOS 26 :
//  le système donne une image (et parfois des étiquettes), Picpic rend des
//  livres. En brocante, on vise une couverture et Picpic répond — sans avoir
//  ouvert l'application, et sans code-barres, ce que le scan exige.
//
//  Rien de neuf sous le capot : l'OCR est celui du scan d'étagère, la
//  recherche est celle de l'accueil. Ce fichier ne fait que les brancher sur
//  une image venue du système.
//

import CoreImage
import Foundation
import SwiftData
import Vision

nonisolated struct VisualBookLookup: Sendable {

    static let shared = VisualBookLookup()

    /// Un livre reconnu, prêt à être montré par le système.
    struct Found: Sendable, Equatable {
        let isbn: String?
        let title: String
        let authors: String
        let coverURLString: String?
        /// Vrai si le livre est déjà dans la bibliothèque du lecteur : c'est
        /// la première chose qu'un chineur veut savoir devant un bac.
        let inLibrary: Bool
    }

    // MARK: - Point d'entrée

    /// Identifie jusqu'à `limit` livres à partir d'une image et des étiquettes
    /// que le système a pu poser dessus.
    func lookup(pixelBuffer: CVReadOnlyPixelBuffer?, labels: [String], limit: Int = 6) async -> [Found] {
        var queries: [String] = []

        // Les étiquettes du système arrivent déjà propres : « book », « cover »
        // n'apprennent rien, un titre lu sur la couverture, si.
        queries += labels.filter { $0.count >= 4 && !Self.uselessLabels.contains($0.lowercased()) }

        if let pixelBuffer {
            queries += await Self.textLines(in: pixelBuffer)
        }
        guard !queries.isEmpty else { return [] }

        // Les lignes les plus longues d'abord : sur une couverture, c'est le
        // titre qui occupe le plus de place, pas la mention d'éditeur.
        let ordered = Array(Set(queries)).sorted { $0.count > $1.count }.prefix(3)
        let query = ordered.joined(separator: " ")

        let local = library(matching: Array(ordered))
        let remote = await CatalogSearchService.shared.search(query, limit: limit)

        var results = local
        var seen = Set(local.compactMap(\.isbn))
        for candidate in remote {
            if let isbn = candidate.isbn, !seen.insert(isbn).inserted { continue }
            results.append(Found(isbn: candidate.isbn,
                                 title: candidate.title,
                                 authors: candidate.authorsLabel,
                                 coverURLString: candidate.coverURLString,
                                 inLibrary: false))
            if results.count == limit { break }
        }
        return results
    }

    /// Étiquettes que le système pose sur presque toutes les photos de livre :
    /// les garder noierait la vraie requête.
    private static let uselessLabels: Set<String> = [
        "book", "livre", "cover", "couverture", "text", "texte", "paper",
        "publication", "novel", "roman", "document", "print",
    ]

    // MARK: - La bibliothèque du lecteur, d'abord

    /// Cherche dans les livres déjà scannés, par recherche sémantique — la
    /// même que la barre de l'accueil, donc sur l'appareil et sans réseau.
    private func library(matching lines: [String]) -> [Found] {
        guard let context = try? ModelContext(LibraryStore.container),
              let books = try? context.fetch(FetchDescriptor<Book>()) else { return [] }
        guard !books.isEmpty else { return [] }

        let query = lines.joined(separator: " ")
        let ranked = SemanticSearchService.shared.search(query: query, in: books)
        return ranked.prefix(3).map {
            Found(isbn: $0.isbn, title: $0.title, authors: $0.authorsLabel,
                  coverURLString: $0.coverURLString, inLibrary: true)
        }
    }

    // MARK: - OCR

    /// Le texte lisible sur l'image, dans l'ordre de longueur décroissante.
    ///
    /// Une seule passe, à l'endroit : la recherche visuelle donne une photo
    /// cadrée sur un objet, pas une étagère vue de côté — les trois passes du
    /// scan d'étagère n'auraient rien de plus à trouver.
    static func textLines(in pixelBuffer: CVReadOnlyPixelBuffer) async -> [String] {
        // `CVReadOnlyPixelBuffer` protège le tampon d'une écriture concurrente :
        // on l'emprunte le temps de fabriquer l'image, on ne le garde pas.
        let cgImage = pixelBuffer.withUnsafeBuffer { buffer -> CGImage? in
            let image = CIImage(cvPixelBuffer: buffer)
            return CIContext().createCGImage(image, from: image.extent)
        }
        guard let cgImage else { return [] }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { observation -> String? in
                    guard let best = observation.topCandidates(1).first,
                          best.confidence > 0.4 else { return nil }
                    let text = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    return text.filter(\.isLetter).count >= 4 ? text : nil
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["fr-FR", "en-US"]
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                try? handler.perform([request])
            }
        }
    }
}
