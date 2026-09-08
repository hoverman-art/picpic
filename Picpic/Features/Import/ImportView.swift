//
//  ImportView.swift
//  Picpic
//
//  « J'ai déjà une bibliothèque ailleurs » — reprendre un export CSV.
//
//  L'écran montre ce qu'il a compris AVANT d'écrire quoi que ce soit. Un import
//  qui avale un fichier et annonce « terminé » ne laisse aucun moyen de savoir
//  s'il a pris deux cents livres ou vingt : ici on annonce le compte, les
//  rejets et leur raison, et c'est le lecteur qui appuie.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(UserSettings.self) private var settings
    @Query private var existing: [Book]

    private enum Phase: Equatable {
        case pick
        case reading
        case ready(ImportPreview)
        case importing(done: Int, total: Int)
        case finished(added: Int, alreadyThere: Int, skipped: Int)

        static func == (a: Phase, b: Phase) -> Bool {
            switch (a, b) {
            case (.pick, .pick), (.reading, .reading): return true
            case let (.ready(x), .ready(y)): return x.books.count == y.books.count
            case let (.importing(a1, a2), .importing(b1, b2)): return a1 == b1 && a2 == b2
            case let (.finished(a1, a2, a3), .finished(b1, b2, b3)):
                return a1 == b1 && a2 == b2 && a3 == b3
            default: return false
            }
        }
    }

    @State private var phase: Phase = .pick
    @State private var showPicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    switch phase {
                    case .pick: pickCard
                    case .reading: ProgressView("Lecture du fichier…")
                    case .ready(let preview): readyCard(preview)
                    case .importing(let done, let total): importingCard(done: done, total: total)
                    case .finished(let a, let b, let c):
                        finishedCard(added: a, alreadyThere: b, skipped: c)
                    }
                    helpCard
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("Importer ma bibliothèque")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                          allowsMultipleSelection: false) { result in
                Task { await load(result) }
            }
            .alert("Oups", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Blocs

    private var intro: some View {
        HStack(alignment: .top, spacing: 12) {
            MascotView(pose: .idea, height: 76)
            Text("Tu as déjà une bibliothèque sur **Goodreads**, **Babelio** ou dans un tableur ? Donne-moi son export CSV, je reprends tout — sans rien envoyer nulle part.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var pickCard: some View {
        Button {
            showPicker = true
        } label: {
            Label("Choisir un fichier CSV", systemImage: "doc.badge.plus")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.ink, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("import.pick")
    }

    private func readyCard(_ preview: ImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(preview.books.count) livre\(preview.books.count > 1 ? "s" : "") à importer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("import.count")

            if preview.skippedTotal > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    // Chaque rejet est nommé : sans ça, l'écart entre les lignes
                    // du fichier et les livres importés passe pour une perte.
                    if preview.skippedNoISBN > 0 {
                        detail("\(preview.skippedNoISBN) sans ISBN — Picpic identifie les livres par leur ISBN, je ne peux pas les reprendre.")
                    }
                    if preview.skippedNoTitle > 0 {
                        detail("\(preview.skippedNoTitle) sans titre.")
                    }
                    if preview.duplicatesInFile > 0 {
                        detail("\(preview.duplicatesInFile) en double dans le fichier.")
                    }
                }
            }

            ForEach(preview.books.prefix(3), id: \.isbn) { book in
                HStack(spacing: 8) {
                    Image(systemName: "book.closed")
                        .font(.caption)
                        .foregroundStyle(Theme.lavender)
                    Text(book.title).font(.footnote.weight(.medium)).lineLimit(1)
                    Text("· \(book.status.label)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if preview.books.count > 3 {
                detail("et \(preview.books.count - 3) autres.")
            }

            Button {
                Task { await runImport(preview) }
            } label: {
                Label("Tout importer", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableStyle())
            .disabled(preview.books.isEmpty)
            .accessibilityIdentifier("import.run")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func importingCard(done: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(Theme.accent)
            Text("\(done) / \(total)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func finishedCard(added: Int, alreadyThere: Int, skipped: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(added) livre\(added > 1 ? "s" : "") ajouté\(added > 1 ? "s" : "")",
                  systemImage: "checkmark.seal.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.teal)
                .accessibilityIdentifier("import.done")
            if alreadyThere > 0 { detail("\(alreadyThere) étaient déjà dans ta bibliothèque.") }
            if skipped > 0 { detail("\(skipped) lignes non reprises.") }
            Button("Voir ma bibliothèque") { dismiss() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Où trouver son export")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink.opacity(0.55))
            detail("**Goodreads** : My Books → Import and export → Export Library.")
            detail("**Babelio** : Ma bibliothèque → Exporter.")
            detail("Un tableur convient aussi : il lui faut une colonne titre et une colonne ISBN.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lavender.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func detail(_ text: String) -> some View {
        Text(.init(text))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func load(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, let url = urls.first else { return }
        phase = .reading
        // Le fichier vient de l'app Fichiers : sans cette parenthèse, la lecture
        // échoue avec une erreur de permission difficile à interpréter.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let preview = try LibraryImportService.preview(
                csv: LibraryImportService.text(from: try Data(contentsOf: url)))
            phase = .ready(preview)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Impossible de lire ce fichier."
            phase = .pick
        }
    }

    private func runImport(_ preview: ImportPreview) async {
        let known = Set(existing.map(\.isbn))
        var added = 0
        var alreadyThere = 0
        phase = .importing(done: 0, total: preview.books.count)

        for (index, imported) in preview.books.enumerated() {
            guard !known.contains(imported.isbn) else { alreadyThere += 1; continue }

            let book = Book(
                isbn: imported.isbn,
                title: imported.title,
                authors: imported.authors,
                coverURLString: LibraryImportService.coverURLString(isbn: imported.isbn),
                pageCount: imported.pageCount,
                status: imported.status
            )
            book.rating = imported.rating
            book.notes = imported.notes
            book.embedding = SemanticSearchService.shared.vector(for: book.semanticText)
            modelContext.insert(book)
            added += 1

            // Une seule sauvegarde à la fin, mais un rendu régulier : sans ces
            // respirations la barre reste figée sur un gros fichier.
            if index % 20 == 0 {
                phase = .importing(done: index + 1, total: preview.books.count)
                await Task.yield()
            }
        }

        do {
            try modelContext.save()
        } catch {
            errorMessage = "Impossible d'enregistrer les livres importés."
            phase = .ready(preview)
            return
        }
        settings.scanCount += added
        phase = .finished(added: added, alreadyThere: alreadyThere,
                          skipped: preview.skippedTotal)
    }
}
