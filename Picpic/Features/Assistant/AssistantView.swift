//
//  AssistantView.swift
//  Picpic
//
//  « Demande à Picpic » : poser une question sur sa propre bibliothèque.
//
//  L'écran assume d'être maigre. Un assistant qui s'ouvre sur un champ vide ne
//  sert à personne : les trois suggestions du haut sont là pour montrer ce que
//  la chose sait faire, et surtout ce qu'elle ne fait pas — aucune ne demande
//  de résumé d'œuvre.
//

import SwiftData
import SwiftUI

struct AssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(ProStore.self) private var proStore
    @Environment(AssistantStore.self) private var store
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var question = ""
    @State private var answer: String?
    @State private var isThinking = false
    @State private var errorMessage: String?
    @State private var showPaywall = false
    /// Livres réellement décrits au modèle pour la dernière réponse. La fenêtre
    /// n'en accepte que quinze, et le lecteur a le droit de le savoir.
    @State private var booksUsed = 0
    @FocusState private var fieldFocused: Bool

    private static let suggestions = [
        "Qu'est-ce que je lis ensuite ?",
        "Lequel de mes livres est le plus court ?",
        "J'ai envie de quelque chose de sombre."
    ]

    /// Résolue une fois : `body` est réévalué à chaque frappe, et interroger le
    /// modèle système à chaque caractère ne sert à rien.
    @State private var availability: AssistantAvailability = .ready

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    if books.isEmpty {
                        // La tuile voisine « Dispo autour de moi » garde avant
                        // d'ouvrir ; ici on laissait taper une question entière
                        // avant de répondre par une alerte.
                        notice("Scanne d'abord quelques livres : je ne parle que de ta bibliothèque, et elle est encore vide.",
                               symbol: "barcode.viewfinder")
                    } else if case .unavailable(let why) = availability {
                        unavailableNotice(why)
                    } else {
                        field
                        if isThinking {
                            thinking
                        } else if let answer {
                            answerCard(answer)
                            scopeNote
                        }
                        suggestionRow
                    }
                    if !books.isEmpty { quotaFooter }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("Demande à Picpic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            // Si l'app est restée ouverte toute la nuit, le pied de page
            // afficherait encore « quota atteint » : seul canAsk faisait le
            // basculement, et l'utilisateur découragé n'y arrive jamais.
            .onAppear {
                store.rolloverIfNeeded()
                availability = AIAssistantService.shared.availability()
            }
            // « Active Apple Intelligence dans Réglages » n'a de sens que si on
            // regarde à nouveau au retour : onAppear ne se redéclenche pas
            // quand l'app repasse au premier plan, et l'écran restait mort.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                store.rolloverIfNeeded()
                availability = AIAssistantService.shared.availability()
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
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

    private var intro: some View {
        HStack(alignment: .top, spacing: 12) {
            MascotView(pose: .idea, height: 76)
            // Un seul littéral : concaténer produirait une String, et Text ne
            // parse le Markdown que sur un littéral.
            Text("Je ne connais que **ta** bibliothèque, et je ne quitte pas ton iPhone. Je ne résume pas les livres — je t'aide à choisir dans les tiens.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var field: some View {
        VStack(spacing: 10) {
            TextField("Ta question…", text: $question, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($fieldFocused)
                .accessibilityIdentifier("assistant.field")

            Button {
                Task { await ask() }
            } label: {
                Label("Demander", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.ink, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableStyle())
            .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
            .accessibilityIdentifier("assistant.ask")
        }
    }

    private var thinking: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Je regarde tes livres…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func answerCard(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.05), radius: 10, y: 4)
            .accessibilityIdentifier("assistant.answer")
    }

    /// Ne s'affiche que si la fenêtre a effectivement coupé : sur une petite
    /// bibliothèque il n'y a rien à préciser.
    @ViewBuilder
    private var scopeNote: some View {
        if booksUsed < books.count {
            Text("D'après \(booksUsed) de tes \(books.count) livres — ceux en cours et ceux dont tu as envie en premier.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("assistant.scope")
        }
    }

    private var suggestionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Par exemple")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            ForEach(Self.suggestions, id: \.self) { suggestion in
                Button {
                    question = suggestion
                    Task { await ask() }
                } label: {
                    Text(suggestion)
                        .font(.footnote)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.lavender.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var quotaFooter: some View {
        if proStore.isPro {
            Label("Questions illimitées avec Picpic Pro", systemImage: "infinity")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else if store.remainingToday > 0 {
            // Un simple décompte. Le rendre tapable ouvrait le paywall alors
            // qu'il restait cinq questions, sans rien qui l'annonce.
            Text("Il te reste \(store.remainingToday) question\(store.remainingToday > 1 ? "s" : "") aujourd'hui")
                .font(.caption)
                .foregroundStyle(Theme.ink.opacity(0.45))
        } else {
            Button {
                showPaywall = true
            } label: {
                Text("Quota du jour atteint — passe à Picpic Pro")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    /// Le modèle manque : on le dit, et on donne de quoi revérifier sur place.
    private func unavailableNotice(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(why, systemImage: "sparkles.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Réessayer") {
                availability = AIAssistantService.shared.availability()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)
            .accessibilityIdentifier("assistant.retry")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lavender.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func notice(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.lavender.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func ask() async {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        guard store.canAsk(isPro: proStore.isPro) else {
            showPaywall = true
            return
        }
        fieldFocused = false
        isThinking = true
        answer = nil
        defer { isThinking = false }

        do {
            let library = books.map {
                AssistantBook(title: $0.title, authors: $0.authorsLabel,
                              subjects: $0.subjects, status: $0.status,
                              pageCount: $0.pageCount, rating: $0.rating, notes: $0.notes)
            }
            booksUsed = AIAssistantService.select(library).count
            answer = try await AIAssistantService.shared.answer(question: text, library: library)
            store.recordAsk(isPro: proStore.isPro)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "L'assistant n'a pas pu répondre."
        }
    }
}
