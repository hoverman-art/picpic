//
//  FreeLibraryView.swift
//  Picpic
//
//  « Écouter gratuitement » : les livres de ta bibliothèque qui existent en
//  enregistrement libre, et les plus écoutés du fonds français.
//
//  L'écran proposait aussi des EPUB, ouverts dans une liseuse maison. Ils ont
//  été retirés le 10 septembre 2026 au profit du seul audio — voir
//  docs/AUDIO-PLUTOT-QUE-EPUB.md pour ce que la liseuse coûtait et ce que
//  l'audio rend.
//

import SwiftData
import SwiftUI

struct FreeLibraryView: View {
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]
    @Environment(\.dismiss) private var dismiss

    private struct LibraryHit: Identifiable {
        let book: Book
        let audiobook: FreeAudiobook
        var id: String { book.isbn }
    }

    @State private var hits: [LibraryHit] = []
    @State private var libraryScanned = false
    @State private var picks: [DailyAudiobook] = []
    @State private var picksLoaded = false
    @State private var resolving: String?
    @State private var audiobookToPlay: FreeAudiobook?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    intro
                    librarySection
                    discoverySection
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("Écouter gratuitement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task { await load() }
        .sheet(item: $audiobookToPlay) { audiobook in
            AudioPlayerView(audiobook: audiobook)
        }
        .alert("Écoute impossible", isPresented: .init(
            get: { failure != nil },
            set: { if !$0 { failure = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: - Sections

    private var intro: some View {
        HStack(spacing: 14) {
            MascotView(pose: .reading, height: 64, animated: false)
            Text("Les grands classiques sont au domaine public : des lecteurs bénévoles les ont enregistrés, tu peux les écouter gratuitement et légalement.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dans ta bibliothèque")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)

            if !libraryScanned {
                progressRow("Recherche dans les enregistrements libres…")
            } else if hits.isEmpty {
                Text(books.isEmpty
                     ? "Scanne d'abord quelques livres — les classiques auront leur version audio ici."
                     : "Aucun de tes livres n'a (encore) d'enregistrement libre. Découvre les plus écoutés ci-dessous.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(hits) { hit in
                    libraryRow(hit)
                }
            }
        }
    }

    private func libraryRow(_ hit: LibraryHit) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(hit.audiobook.totalTimeLabel.map { "\(hit.book.authorsLabel) · \($0)" } ?? hit.book.authorsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                audiobookToPlay = hit.audiobook
            } label: {
                Image(systemName: "headphones")
                    .font(.subheadline)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("freelibrary.listen.\(hit.book.isbn)")
            .accessibilityLabel("Écouter \(hit.book.title)")
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var discoverySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Les plus écoutés")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Le fonds français de LibriVox, du plus écouté au moins écouté.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !picksLoaded {
                progressRow("Chargement du catalogue…")
            } else if picks.isEmpty {
                Text("Impossible de charger la sélection. Vérifie ta connexion et réessaie.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(picks) { pick in
                    discoveryRow(pick)
                }
            }
        }
    }

    private func discoveryRow(_ pick: DailyAudiobook) -> some View {
        Button {
            Task { await open(pick) }
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: pick.coverURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Theme.teal.opacity(0.12)
                            Image(systemName: "headphones")
                                .foregroundStyle(Theme.teal)
                        }
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(pick.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(pick.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if resolving == pick.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.teal)
                }
            }
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(resolving != nil)
        .accessibilityIdentifier("freelibrary.pick")
    }

    private func progressRow(_ label: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Chargement

    private func load() async {
        async let library: Void = scanLibrary()
        async let discovery: Void = loadDiscovery()
        _ = await (library, discovery)
    }

    /// Les livres de la bibliothèque qui ont un enregistrement libre.
    ///
    /// En série et non en parallèle : LibriVox n'aime pas qu'on lui parle
    /// plusieurs fois à la fois, et le service impose déjà son propre rythme.
    private func scanLibrary() async {
        var found: [LibraryHit] = []
        for book in books.prefix(12) {
            let match = await FreeReadingService.shared.match(
                isbn: book.isbn, title: book.title, authors: book.authors)
            if let audiobook = match.audiobook {
                found.append(LibraryHit(book: book, audiobook: audiobook))
            }
        }
        hits = found
        libraryScanned = true
    }

    private func loadDiscovery() async {
        picks = await DailyAudiobooksService.shared.mostListened(limit: 20)
        picksLoaded = true
    }

    /// Les pistes ne sont demandées qu'au moment d'écouter : une fiche
    /// Archive.org pèse plus d'un mégaoctet.
    private func open(_ pick: DailyAudiobook) async {
        resolving = pick.id
        defer { resolving = nil }
        if let audiobook = await DailyAudiobooksService.shared.audiobook(pick) {
            audiobookToPlay = audiobook
        } else {
            failure = "« \(pick.title) » n'a pas pu être ouvert. Réessaie dans un instant."
        }
    }
}
