//
//  DailyAudioShelf.swift
//  Picpic
//
//  « À écouter aujourd'hui » sur l'accueil : six livres audio du domaine
//  public, tirés chaque jour parmi les plus écoutés du fonds français de
//  LibriVox (voir DailyAudiobooksService pour la mesure et la source).
//
//  Pourquoi sur l'accueil. Il ne s'y passait rien : la même étagère, les mêmes
//  tuiles, à chaque ouverture. Un lecteur qui n'a rien scanné depuis une
//  semaine n'avait aucune raison de revenir. Ici, la liste change tous les
//  jours, elle ne coûte rien à personne, et elle mène à ce que Picpic sait
//  déjà faire — écouter un livre gratuitement.
//

import SwiftUI

struct DailyAudioShelf: View {
    /// Le livre à ouvrir dans le lecteur, remonté à l'accueil qui le présente.
    @Binding var playing: FreeAudiobook?

    @State private var picks: [DailyAudiobook] = []
    @State private var loaded = false
    @State private var resolving: String?
    @State private var failed: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !loaded {
                placeholderRow
            } else if picks.isEmpty {
                Text("La sélection du jour n'a pas pu être chargée. Reviens quand tu auras du réseau.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(picks) { pick in
                            card(pick)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task { await load() }
        .alert("Écoute impossible", isPresented: .init(
            get: { failed != nil },
            set: { if !$0 { failed = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failed ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("À écouter aujourd'hui")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text("gratuit")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.teal.opacity(0.14), in: Capsule())
                .foregroundStyle(Theme.teal)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.dailyAudio")
    }

    private var placeholderRow: some View {
        HStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.ink.opacity(0.05))
                    .frame(width: 130, height: 190)
            }
        }
        .accessibilityLabel("Chargement de la sélection du jour")
    }

    private func card(_ pick: DailyAudiobook) -> some View {
        Button {
            Task { await open(pick) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.teal.opacity(0.12))
                    AsyncImage(url: pick.coverURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "headphones")
                            .font(.title)
                            .foregroundStyle(Theme.teal)
                    }
                    if resolving == pick.id {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.black.opacity(0.35))
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: 130, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text(pick.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(pick.author)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 130, alignment: .leading)
        }
        .buttonStyle(PressableStyle())
        .disabled(resolving != nil)
        .accessibilityIdentifier("home.dailyAudio.item")
        .accessibilityLabel("\(pick.title), \(pick.author)")
    }

    // MARK: - Chargement

    private func load() async {
        guard !loaded else { return }
        picks = await DailyAudiobooksService.shared.selection()
        loaded = true
    }

    /// Les pistes ne sont demandées qu'au moment d'écouter : la fiche d'un
    /// livre audio pèse plus d'un mégaoctet, six d'un coup à l'ouverture de
    /// l'accueil seraient six mégaoctets pour rien.
    private func open(_ pick: DailyAudiobook) async {
        resolving = pick.id
        defer { resolving = nil }
        if let audiobook = await DailyAudiobooksService.shared.audiobook(pick) {
            playing = audiobook
        } else {
            failed = "« \(pick.title) » n'a pas pu être ouvert. Réessaie dans un instant."
        }
    }
}
