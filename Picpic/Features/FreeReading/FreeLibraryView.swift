//
//  FreeLibraryView.swift
//  Picpic
//
//  « Lire & écouter gratuit » depuis la home : les livres de ta
//  bibliothèque disponibles gratuitement (domaine public), et une
//  sélection de classiques populaires à découvrir (Gutendex).
//

import SwiftData
import SwiftUI

struct FreeLibraryView: View {
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]
    @Environment(\.dismiss) private var dismiss

    private struct LibraryHit: Identifiable {
        let book: Book
        let match: FreeReadingMatch
        var id: String { book.isbn }
    }

    @State private var hits: [LibraryHit] = []
    @State private var libraryScanned = false
    @State private var classics: [FreeReadingService.DiscoveryBook] = []
    @State private var classicsLoaded = false
    @State private var safariURL: IdentifiableURL?
    @State private var audiobookToPlay: FreeAudiobook?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    intro
                    librarySection
                    classicsSection
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("Lire & écouter gratuit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task { await load() }
        .sheet(item: $safariURL) { link in
            SafariView(url: link.url).ignoresSafeArea()
        }
        .sheet(item: $audiobookToPlay) { audiobook in
            AudioPlayerView(audiobook: audiobook)
        }
    }

    // MARK: - Sections

    private var intro: some View {
        HStack(spacing: 14) {
            MascotView(pose: .reading, height: 64, animated: false)
            Text("Les grands classiques sont au domaine public : lis-les en EPUB ou écoute-les gratuitement, légalement.")
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
                progressRow("Recherche dans les catalogues libres…")
            } else if hits.isEmpty {
                Text(books.isEmpty
                     ? "Scanne d'abord quelques livres — les classiques auront leur version gratuite ici."
                     : "Aucun de tes livres n'est (encore) au domaine public. Découvre les classiques ci-dessous !")
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
                Text(hit.book.authorsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let ebook = hit.match.ebook {
                iconButton("book.fill", identifier: "freelibrary.read.\(hit.book.isbn)") {
                    safariURL = IdentifiableURL(url: ebook.epubURL)
                }
            }
            if let audiobook = hit.match.audiobook {
                iconButton("headphones", identifier: "freelibrary.listen.\(hit.book.isbn)") {
                    audiobookToPlay = audiobook
                }
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var classicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Classiques à découvrir")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Les plus lus du Projet Gutenberg en français.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !classicsLoaded {
                progressRow("Chargement des classiques…")
            } else if classics.isEmpty {
                Text("Impossible de charger la sélection. Vérifie ta connexion et réessaie.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(classics.prefix(20)) { classic in
                    classicRow(classic)
                }
            }
        }
    }

    private func classicRow(_ classic: FreeReadingService.DiscoveryBook) -> some View {
        Button {
            safariURL = IdentifiableURL(url: classic.epubURL)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: classic.coverURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            LinearGradient(colors: [Theme.lavender, Theme.ink],
                                           startPoint: .top, endPoint: .bottom)
                            Image(systemName: "book.closed.fill")
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                .frame(width: 40, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(classic.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(classic.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.teal)
            }
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Helpers

    private func iconButton(_ symbol: String, identifier: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline)
                .frame(width: 38, height: 38)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .foregroundStyle(Theme.accent)
        }
        .accessibilityIdentifier(identifier)
    }

    private func progressRow(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        // Les classiques d'abord (une seule requête), puis la bibliothèque :
        // matching par lots de 4 en parallèle, plafonné aux 20 plus récents.
        classics = await FreeReadingService.shared.popularClassics()
        classicsLoaded = true
        guard hits.isEmpty else { return }
        let candidates = Array(books.prefix(20))
        let matches: [(isbn: String, match: FreeReadingMatch)] = await withTaskGroup(
            of: (String, FreeReadingMatch).self
        ) { group in
            for book in candidates {
                let (isbn, title, authors) = (book.isbn, book.title, book.authors)
                group.addTask {
                    (isbn, await FreeReadingService.shared.match(
                        isbn: isbn, title: title, authors: authors))
                }
            }
            var results: [(String, FreeReadingMatch)] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
        let byISBN = Dictionary(uniqueKeysWithValues: matches.map { ($0.isbn, $0.match) })
        hits = candidates.compactMap { book in
            guard let match = byISBN[book.isbn], !match.isEmpty else { return nil }
            return LibraryHit(book: book, match: match)
        }
        libraryScanned = true
    }
}

/// Wrapper Identifiable pour `.sheet(item:)` sur une URL.
struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
