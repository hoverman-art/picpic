//
//  SudocSearchView.swift
//  Picpic
//
//  « Ta filière à la BU » — l'écran qui retourne le geste de Picpic : au lieu
//  de partir d'un livre qu'on tient pour dire où l'emprunter, il part du rayon
//  d'à côté pour dire quoi lire. Rendu possible par l'index `rbc` du SRU
//  Sudoc, qui restreint une recherche au fonds d'une bibliothèque précise.
//

import SwiftUI
import SwiftData

struct SudocSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(UserSettings.self) private var settings
    @Query private var libraryBooks: [Book]

    @State private var viewModel = SudocSearchViewModel()
    @State private var selectedRecord: SudocRecord?
    @FocusState private var searchFocused: Bool

    /// Sujets proposés d'entrée : ceux de la filière, ou une sélection
    /// généraliste pour qui n'est pas étudiant.
    private var suggestedSubjects: [String] {
        settings.studyField?.sudocSubjects ?? [
            "roman", "histoire de France", "philosophie", "psychologie",
            "écologie", "cinéma",
        ]
    }

    private var heading: String {
        settings.studyField.map { "\($0.label) à la BU" } ?? "Le catalogue des BU"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    searchField
                    subjectChips
                    filters
                    results
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Theme.paper)
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(item: $selectedRecord) { record in
                SudocRecordDetailView(record: record)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - En-tête

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ce que la BU a en rayon, sur ton sujet.")
                .font(.display(24))
                .foregroundStyle(Theme.ink)
            Text("Recherche dans le Sudoc, le catalogue commun des bibliothèques universitaires françaises — 15 millions de notices, en accès libre.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.teal)
            TextField("Un sujet : « droit du travail »…", text: $viewModel.terms)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { Task { await viewModel.search() } }
                .accessibilityIdentifier("sudoc.searchField")

            Menu {
                Picker("Chercher dans", selection: $viewModel.index) {
                    ForEach(SudocIndex.browsable) { index in
                        Text(index.label).tag(index)
                    }
                }
            } label: {
                Text(viewModel.index.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.teal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.teal.opacity(0.12), in: Capsule())
            }
            .accessibilityIdentifier("sudoc.indexMenu")
            .onChange(of: viewModel.index) { Task { await viewModel.refilter() } }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.06), radius: 10, y: 4)
    }

    private var subjectChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestedSubjects, id: \.self) { subject in
                    Button {
                        searchFocused = false
                        Task { await viewModel.search(subject: subject) }
                    } label: {
                        Text(subject)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                viewModel.terms == subject ? Theme.teal : .white,
                                in: Capsule()
                            )
                            .foregroundStyle(viewModel.terms == subject ? .white : Theme.ink)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("sudoc.chip.\(subject)")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var filters: some View {
        HStack(spacing: 10) {
            Picker("Où", selection: $viewModel.scope) {
                ForEach(SudocScope.allCases) { scope in
                    Text(scope.shortLabel).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 190)
            .accessibilityIdentifier("sudoc.scope")
            .onChange(of: viewModel.scope) { Task { await viewModel.refilter() } }

            Menu {
                Picker("Période", selection: $viewModel.period) {
                    ForEach(SudocSearchViewModel.Period.allCases) { period in
                        Text(period.label).tag(period)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(viewModel.period == .any ? "Période" : viewModel.period.label)
                        .lineLimit(1)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white, in: Capsule())
            }
            .accessibilityIdentifier("sudoc.periodMenu")
            .onChange(of: viewModel.period) { Task { await viewModel.refilter() } }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Résultats

    @ViewBuilder
    private var results: some View {
        if viewModel.isLoading {
            loadingState
        } else if let error = viewModel.errorMessage, viewModel.records.isEmpty {
            message(symbol: "wifi.exclamationmark", title: "Sudoc injoignable", detail: error)
        } else if viewModel.hasSearched && viewModel.records.isEmpty {
            message(symbol: "text.magnifyingglass",
                    title: "Rien sur ce sujet",
                    detail: viewModel.scope == .laRochelle
                        ? "La BU de La Rochelle n'a rien là-dessus. Essaie « Toute la France »."
                        : "Essaie un sujet plus large, ou cherche par titre.")
        } else if !viewModel.hasSearched {
            welcomeState
        } else {
            resultList
        }
    }

    private var resultList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.resultSummary)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("sudoc.summary")

            LazyVStack(spacing: 10) {
                ForEach(viewModel.records) { record in
                    SudocResultRow(
                        record: record,
                        isInLibrary: viewModel.isInLibrary(record, existing: libraryBooks),
                        isAdding: viewModel.addingPPN == record.ppn,
                        onOpen: { selectedRecord = record },
                        onAdd: { Task { await viewModel.add(record, context: modelContext) } }
                    )
                }
            }

            if viewModel.canLoadMore {
                Button {
                    Task { await viewModel.loadMore() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMore {
                            ProgressView()
                        } else {
                            Text("Charger la suite")
                                .font(.subheadline.weight(.semibold))
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("sudoc.loadMore")
            }
        }
    }

    private var welcomeState: some View {
        VStack(spacing: 12) {
            MascotView(pose: .reading, height: 120)
            Text("Choisis un sujet là-haut")
                .font(.headline)
            Text(settings.studyField == nil
                 ? "Ou tape ce que tu cherches : le Sudoc couvre tout ce que les universités françaises possèdent."
                 : "Les propositions viennent de ta filière. Tu peux aussi taper ton propre sujet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Interrogation du Sudoc…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 16)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Ligne de résultat

private struct SudocResultRow: View {
    let record: SudocRecord
    let isInLibrary: Bool
    let isAdding: Bool
    let onOpen: () -> Void
    let onAdd: () -> Void

    var body: some View {
        // Le bouton d'ajout est le frère de la ligne, pas son enfant :
        // SwiftUI ne gère pas un bouton imbriqué dans le label d'un autre.
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    Text(record.authorsLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !record.imprintLabel.isEmpty {
                        Text(record.imprintLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("sudoc.row")

            addButton
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var addButton: some View {
        if isInLibrary {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.teal)
                .accessibilityLabel("Déjà dans ta bibliothèque")
        } else if record.isbn != nil {
            Button(action: onAdd) {
                if isAdding {
                    ProgressView()
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajouter à ma bibliothèque")
            .accessibilityIdentifier("sudoc.add")
        }
    }
}

// MARK: - Détail d'une notice

struct SudocRecordDetailView: View {
    let record: SudocRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var holdings: [HoldingLibrary] = []
    @State private var isLoadingHoldings = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.title)
                            .font(.display(24))
                            .foregroundStyle(Theme.ink)
                        if let subtitle = record.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(record.authorsLabel)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.accent)
                        if !record.imprintLabel.isEmpty {
                            Text(record.imprintLabel)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !record.subjects.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sujets")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            FlowChips(items: record.subjects)
                        }
                    }

                    holdingsSection

                    if let url = record.noticeURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Voir la notice Sudoc", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .task {
            defer { isLoadingHoldings = false }
            holdings = (try? await AvailabilityService.shared.holdingLibraries(ppn: record.ppn)) ?? []
        }
    }

    @ViewBuilder
    private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Où l'emprunter")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            if isLoadingHoldings {
                ProgressView()
            } else if holdings.isEmpty {
                Text("Aucun exemplaire localisé pour cette notice.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(holdings.prefix(6)) { library in
                    HStack {
                        Image(systemName: "building.columns")
                            .foregroundStyle(Theme.teal)
                        Text(library.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        if let distance = library.distanceFromLaRochelle {
                            Text("\(Int(distance)) km")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if holdings.count > 6 {
                    Text("et \(holdings.count - 6) autres bibliothèques")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Puces de sujets qui passent à la ligne.
struct FlowChips: View {
    let items: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows.indices, id: \.self) { index in
                    HStack(spacing: 6) {
                        ForEach(rows[index], id: \.self) { chip($0) }
                    }
                }
            }
        }
    }

    private var chips: some View {
        ForEach(items, id: \.self) { chip($0) }
    }

    /// Deux sujets par ligne : les vedettes Rameau sont longues.
    private var rows: [[String]] {
        stride(from: 0, to: items.count, by: 2).map {
            Array(items[$0..<min($0 + 2, items.count)])
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.lavender.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.ink)
    }
}
