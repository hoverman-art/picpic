//
//  RevisionSheetView.swift
//  Picpic
//
//  La fiche de révision d'un livre.
//
//  Elle n'est jamais un résumé de l'œuvre : elle rassemble ce que
//  l'utilisateur a lui-même produit — ses notes, ses citations — et les faits
//  bibliographiques publics (auteur, éditeur, année, vedettes-matière). C'est
//  un choix de conception autant que de prudence : résumer une œuvre protégée
//  à la place de son lecteur n'est ni utile ni défendable.
//

import SwiftUI
import SwiftData

struct RevisionSheetView: View {
    let book: Book

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Quote.dateAdded) private var allQuotes: [Quote]

    @State private var isTesting = false
    @State private var revealed: Set<String> = []

    private var quotes: [Quote] {
        allQuotes.filter { $0.bookISBN == book.isbn }
    }

    /// Les notes libres découpées en points : une ligne ou une phrase = un point.
    private var notePoints: [String] {
        book.notes
            .components(separatedBy: CharacterSet(charactersIn: "\n•"))
            .flatMap { $0.components(separatedBy: ". ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 }
    }

    private var isEmpty: Bool { notePoints.isEmpty && quotes.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    identityCard
                    if isEmpty {
                        emptyState
                    } else {
                        if !notePoints.isEmpty { notesSection }
                        if !quotes.isEmpty { quotesSection }
                    }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("Fiche de révision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                if !isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button(isTesting ? "Tout voir" : "Me tester") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isTesting.toggle()
                                revealed = []
                            }
                        }
                        .accessibilityIdentifier("revision.toggleTest")
                    }
                }
            }
        }
    }

    // MARK: - L'essentiel (faits bibliographiques)

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(book.title)
                .font(.display(24))
                .foregroundStyle(Theme.ink)
            Text(book.authorsLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)

            let imprint = [book.publisher, book.publishedDate].compactMap { $0 }.joined(separator: ", ")
            if !imprint.isEmpty {
                Text(imprint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let pages = book.pageCount {
                Text("\(pages) pages")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !book.subjects.isEmpty {
                FlowChips(items: Array(book.subjects.prefix(6)))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.largeTitle)
                .foregroundStyle(Theme.lavender)
            Text("Ta fiche est encore vide")
                .font(.headline)
            Text("Elle se remplit avec ce que tu écris : tes notes sur la fiche du livre, et les citations que tu photographies. Picpic ne résume pas les livres à ta place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Tes notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Tes notes", symbol: "pencil.line")
            ForEach(Array(notePoints.enumerated()), id: \.offset) { index, point in
                maskableRow(id: "note-\(index)", text: point, accent: Theme.lavender)
            }
        }
    }

    private var quotesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Tes citations", symbol: "text.quote")
            ForEach(quotes) { quote in
                VStack(alignment: .leading, spacing: 6) {
                    maskableRow(id: quote.text,
                                text: quote.text, accent: Theme.gold, italic: true)
                    if let page = quote.page {
                        Text("page \(page)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 4)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.title3.weight(.semibold))
            .foregroundStyle(Theme.ink)
    }

    /// En mode « me tester », le texte est masqué jusqu'à ce qu'on le touche :
    /// c'est le rappel actif, pas la relecture, qui fait tenir une révision.
    private func maskableRow(id: String, text: String, accent: Color, italic: Bool = false) -> some View {
        let isHidden = isTesting && !revealed.contains(id)
        return Button {
            guard isTesting else { return }
            withAnimation(.easeInOut(duration: 0.18)) { _ = revealed.insert(id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .padding(.top, 7)
                Text(isHidden ? String(repeating: "▒", count: min(48, max(12, text.count / 2))) : text)
                    .font(.callout)
                    .italic(italic && !isHidden)
                    .foregroundStyle(isHidden ? accent.opacity(0.35) : Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(isHidden ? 2 : nil)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isTesting)
        .accessibilityHint(isHidden ? "Touche pour révéler" : "")
    }
}
