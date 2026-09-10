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

    /// Classe les livres contre une requête en langage ordinaire.
    ///
    /// **Le littéral d'abord, le sens ensuite — et mesuré.** La recherche ne
    /// reposait que sur les embeddings d'Apple. Relevé le 10 septembre 2026
    /// sur la bibliothèque de démonstration :
    ///
    ///     « un roman sur la mer »      L'Étranger 0,718 · Vingt mille lieues
    ///                                  sous les mers 0,605 — DERNIER
    ///     « une histoire d'épidémie »  Le Petit Prince 0,697 · La Peste 0,634
    ///     « un livre pour enfants »    L'Étranger 0,725 · Le Petit Prince 0,721
    ///
    /// Les écarts sont de l'ordre du centième sur des livres qui n'ont rien à
    /// voir : `NLEmbedding.sentenceEmbedding` en français ne discrimine pas à
    /// cette échelle. Autrement dit, la « recherche par idée » classait au
    /// hasard, et l'exemple affiché dans le champ était le pire cas.
    ///
    /// Le score littéral, lui, sait où il regarde : un mot du titre pèse plus
    /// qu'un mot du résumé, et « mer » retrouve « les mers ».
    func search(query: String, in books: [Book]) -> [Book] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return books }

        let words = Self.meaningfulWords(in: trimmed)
        guard !words.isEmpty else { return books }

        let scored = books.map { ($0, Self.score(words: words, in: $0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        return scored.map(\.0)
    }

    // MARK: - Le score littéral

    /// Mots vides du français, plus ceux qui ne discriminent rien dans une
    /// bibliothèque : « livre » est vrai de tous les livres.
    private static let stopWords: Set<String> = [
        "le", "la", "les", "un", "une", "des", "du", "de", "au", "aux", "et", "ou",
        "sur", "sous", "pour", "avec", "sans", "dans", "par", "en", "a", "quelque",
        "chose", "livre", "livres", "truc", "qui", "que", "quoi", "est", "sont",
        "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "ce", "cette",
    ]

    /// Découpe la requête en mots utiles, sans accents ni casse.
    static func meaningfulWords(in query: String) -> [String] {
        query.folding(options: [.diacriticInsensitive, .caseInsensitive],
                      locale: Locale(identifier: "fr_FR"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    /// Un mot vaut selon l'endroit où il tombe : le titre dit le sujet, le
    /// résumé le raconte, l'éditeur ne dit rien.
    static func score(words: [String], in book: Book) -> Int {
        func normalize(_ text: String) -> String {
            text.folding(options: [.diacriticInsensitive, .caseInsensitive],
                         locale: Locale(identifier: "fr_FR"))
        }
        let title = normalize(book.title)
        let authors = normalize(book.authorsLabel)
        let subjects = normalize(book.subjects.joined(separator: " "))
        let summary = normalize(book.bookDescription ?? "")

        var total = 0
        for word in words {
            // Le radical suffit : « mer » doit retrouver « les mers », et
            // « épidémie » « une épidémie ». Trois lettres au minimum, sinon
            // « art » retrouverait « partie ».
            let stem = String(word.prefix(max(3, word.count - 2)))
            if title.contains(stem) { total += 5 }
            if subjects.contains(stem) { total += 3 }
            if authors.contains(stem) { total += 3 }
            if summary.contains(stem) { total += 1 }
        }
        return total
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

}
