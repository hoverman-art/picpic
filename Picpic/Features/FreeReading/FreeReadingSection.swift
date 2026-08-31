//
//  FreeReadingSection.swift
//  Picpic
//
//  Section « Lire / écouter gratuitement » de la fiche livre : si l'œuvre
//  est au domaine public, propose l'EPUB gratuit (ouvert dans Safari, qui
//  sait l'envoyer vers Apple Livres) et l'audio LibriVox dans le lecteur.
//

import SwiftUI

struct FreeReadingSection: View {
    let book: Book
    var openLink: (URL) -> Void

    @State private var match: FreeReadingMatch?
    @State private var audiobookToPlay: FreeAudiobook?

    var body: some View {
        Group {
            if let match, !match.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Lire ou écouter gratuitement")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)

                    if let ebook = match.ebook {
                        row(symbol: "book.fill",
                            title: "Lire l'EPUB gratuit",
                            detail: "Domaine public · \(ebook.source.rawValue)",
                            identifier: "freereading.ebook") {
                            openLink(ebook.epubURL)
                        }
                    }
                    if let audiobook = match.audiobook {
                        row(symbol: "headphones",
                            title: "Écouter le livre audio",
                            detail: audiobook.totalTimeLabel.map { "LibriVox · \($0)" } ?? "LibriVox · gratuit",
                            identifier: "freereading.audio") {
                            audiobookToPlay = audiobook
                        }
                    }
                }
            }
        }
        .task(id: book.isbn) {
            match = await FreeReadingService.shared.match(
                isbn: book.isbn, title: book.title, authors: book.authors)
        }
        .sheet(item: $audiobookToPlay) { audiobook in
            AudioPlayerView(audiobook: audiobook)
        }
    }

    private func row(symbol: String, title: String, detail: String,
                     identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier(identifier)
    }
}

extension FreeAudiobook: Identifiable {
    var id: String { title }
}
