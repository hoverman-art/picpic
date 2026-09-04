//
//  QuoteOCRService.swift
//  Picpic
//
//  Lecture d'une page photographiée pour en extraire une citation.
//
//  Rien à voir avec le scan d'étagère : ici le texte est horizontal, dense, et
//  l'ordre de lecture compte. On rend donc les lignes triées de haut en bas,
//  puis on les recolle en respectant la césure — l'utilisateur choisit ensuite
//  la portion qui l'intéresse.
//

import UIKit
@preconcurrency import Vision

enum QuoteOCRError: LocalizedError {
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Aucun texte lisible sur cette photo. Cadre la page bien à plat, avec assez de lumière."
        }
    }
}

nonisolated struct QuoteOCRService {

    /// Lignes de la page, dans l'ordre de lecture.
    func recognizeLines(in image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { throw QuoteOCRError.unreadable }
        let observations = try await recognize(cgImage: cgImage)

        // Vision rend un repère normalisé, origine en bas à gauche : trier par
        // ordonnée décroissante remet la page dans le sens de lecture.
        let lines = observations
            .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
            .compactMap { observation -> String? in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence > 0.3 else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }

        guard !lines.isEmpty else { throw QuoteOCRError.unreadable }
        return lines
    }

    /// Recolle des lignes de page en un paragraphe lisible : les mots coupés en
    /// fin de ligne sont recousus, les autres séparés par une espace.
    func joinLines(_ lines: [String]) -> String {
        var result = ""
        for line in lines {
            let piece = line.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }
            if result.isEmpty {
                result = piece
            } else if result.hasSuffix("-") {
                result.removeLast()
                result += piece
            } else {
                result += " " + piece
            }
        }
        // Les guillemets typographiques de l'imprimé encadrent souvent déjà la
        // citation : la carte les repose elle-même, on évite le doublon.
        return result
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "«»\"“”"))
            .trimmingCharacters(in: .whitespaces)
    }

    private func recognize(cgImage: CGImage) async throws -> [VNRecognizedTextObservation] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (request.results as? [VNRecognizedTextObservation]) ?? [])
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["fr-FR", "en-US"]
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
