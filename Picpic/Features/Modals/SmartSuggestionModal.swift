//
//  SmartSuggestionModal.swift
//  Picpic
//
//  Smart suggestion sheet, shown after the 3rd scan: surfaces the
//  most similar book already in the library (on-device semantic
//  similarity) and nudges towards local availability.
//

import SwiftUI

struct SmartSuggestionModal: View {
    @Environment(\.dismiss) private var dismiss
    let books: [Book]

    private var suggestion: Book? {
        // Latest scan vs. the rest: best semantic neighbour.
        guard let latest = books.first, books.count > 1 else { return books.first }
        let others = Array(books.dropFirst())
        return SemanticSearchService.shared
            .search(query: latest.semanticText, in: others)
            .first ?? others.first
    }

    var body: some View {
        VStack(spacing: 20) {
            MascotView(pose: .idea, height: 110)
                .padding(.top, 24)

            Text("Déjà 3 livres scannés !")
                .font(.display(24))
                .foregroundStyle(Theme.ink)

            if let suggestion {
                VStack(spacing: 6) {
                    Text("D'après ta bibliothèque, tu devrais adorer relire :")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        BookCard(book: suggestion)
                            .scaleEffect(0.85)
                    }
                }
            }

            Text("Astuce : ouvre la fiche d'un livre pour voir s'il t'attend à la BU des Minimes ou à la médiathèque Michel-Crépeau.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                dismiss()
            } label: {
                Text("Continuer à scanner")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.paper)
    }
}
