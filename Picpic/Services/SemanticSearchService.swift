//
//  SemanticSearchService.swift
//  Picpic
//
//  On-device semantic search using Apple's NaturalLanguage embeddings.
//  Zero network, zero backend: vectors are computed locally and stored
//  on each Book (SwiftData). Falls back to fuzzy text match when no
//  embedding model is available for the language.
//

import Foundation
import NaturalLanguage

struct SemanticSearchService {

    static let shared = SemanticSearchService()

    // NLEmbedding models are expensive to create and safe to reuse:
    // load once for the process lifetime.
    private static let cachedEmbedding: NLEmbedding? =
        NLEmbedding.sentenceEmbedding(for: .french) ?? NLEmbedding.sentenceEmbedding(for: .english)

    private var embedding: NLEmbedding? { Self.cachedEmbedding }

    /// Computes the embedding vector for a text, encoded as Float32 Data.
    func vector(for text: String) -> Data? {
        guard let embedding,
              let vector = embedding.vector(for: text.lowercased()) else { return nil }
        let floats = vector.map { Float($0) }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Ranks books against a natural-language query. Returns books sorted by
    /// relevance, best first. Books without embeddings are matched by text.
    func search(query: String, in books: [Book]) -> [Book] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return books }

        guard let embedding,
              let queryVector = embedding.vector(for: trimmed.lowercased()) else {
            return textFallback(query: trimmed, in: books)
        }

        let scored: [(Book, Double)] = books.map { book in
            if let data = book.embedding {
                let bookVector = decode(data)
                return (book, cosineSimilarity(queryVector, bookVector))
            }
            // No stored vector: cheap lexical score so the book still surfaces.
            let haystack = book.semanticText.lowercased()
            return (book, haystack.contains(trimmed.lowercased()) ? 0.6 : 0)
        }

        return scored
            .filter { $0.1 > 0.15 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    private func decode(_ data: Data) -> [Double] {
        data.withUnsafeBytes { raw in
            raw.bindMemory(to: Float.self).map(Double.init)
        }
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, magA = 0.0, magB = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA.squareRoot() * magB.squareRoot())
    }

    private func textFallback(query: String, in books: [Book]) -> [Book] {
        let q = query.lowercased()
        return books.filter { $0.semanticText.lowercased().contains(q) }
    }
}
