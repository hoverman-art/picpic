//
//  HomeView.swift
//  Picpic
//
//  Home: semantic search, scanned books shelf, premium feature grid,
//  scan button, and the smart suggestion / rating modals.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(UserSettings.self) private var settings
    @Environment(ProStore.self) private var proStore
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var viewModel = LibraryViewModel()
    @State private var searchText = ""
    @State private var showScanner = false
    @State private var showTutorial = false
    @State private var appeared = false
    @State private var navPath = NavigationPath()
    @State private var showScanFirstHint = false
    @State private var showPaywall = false
    @State private var showShelfScan = false
    @State private var showFreeLibrary = false
    @State private var showStats = false
    @FocusState private var searchFocused: Bool

    private var displayedBooks: [Book] {
        searchText.isEmpty
            ? books
            : SemanticSearchService.shared.search(query: searchText, in: books)
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                        .staggeredAppear(index: 0, isVisible: appeared)
                    searchBar
                        .staggeredAppear(index: 1, isVisible: appeared)

                    if books.isEmpty {
                        emptyState
                            .staggeredAppear(index: 2, isVisible: appeared)
                    } else {
                        bookShelf
                            .staggeredAppear(index: 2, isVisible: appeared)
                    }

                    if !proStore.isPro {
                        proBanner
                            .staggeredAppear(index: 3, isVisible: appeared)
                    }

                    featureGrid
                        .staggeredAppear(index: 4, isVisible: appeared)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .background(Theme.paper)
            .overlay(alignment: .bottom) { scanButton }
            .navigationDestination(for: Book.self) { book in
                BookDetailView(book: book)
            }
            .sheet(isPresented: $showScanner) {
                ScannerView { isbn in
                    Task {
                        await viewModel.addBook(isbn: isbn, context: modelContext, settings: settings)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSuggestionModal) {
                SmartSuggestionModal(books: books)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showTutorial) {
                TutorialView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showShelfScan) {
                ShelfScanView()
            }
            .sheet(isPresented: $showFreeLibrary) {
                FreeLibraryView()
            }
            .sheet(isPresented: $showStats) {
                StatsView()
            }
            .sheet(isPresented: $viewModel.showRateModal) {
                RateAppModal()
                    .presentationDetents([.height(440)])
                    .presentationDragIndicator(.visible)
            }
            .overlay {
                if viewModel.isFetching {
                    fetchingOverlay
                }
            }
            .alert("Oups", isPresented: .init(
                get: { viewModel.fetchError != nil },
                set: { if !$0 { viewModel.fetchError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.fetchError ?? "")
            }
        }
        .onAppear {
            appeared = true
            // Ouverture directe d'un écran pour tests UI et captures d'écran.
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-uitest-open"),
               index + 1 < ProcessInfo.processInfo.arguments.count {
                switch ProcessInfo.processInfo.arguments[index + 1] {
                case "paywall": showPaywall = true
                case "shelfscan": showShelfScan = true
                case "freereading": showFreeLibrary = true
                case "stats": showStats = true
                default: break
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Ta bibliothèque")
                    .font(.display(32))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Button {
                showTutorial = true
            } label: {
                MascotView(pose: .idle, height: 54, animated: false)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.accent)
                            .background(.white, in: Circle())
                    }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Didacticiel")
        }
        .padding(.top, 12)
    }

    private var greeting: String {
        let name = settings.profile == .student ? "l'étudiant·e" : "le lecteur"
        let field = settings.studyField.map { " · \($0.label)" } ?? ""
        return "Salut \(name)\(field) 👋"
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(Theme.accent)
            TextField("Cherche par idée : « roman sur la mer »…", text: $searchText)
                .autocorrectionDisabled()
                .focused($searchFocused)
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.06), radius: 10, y: 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            MascotView(pose: .reading, height: 130)
            Text("Scanne ton premier livre")
                .font(.headline)
            Text("Le code-barres au dos suffit : fiche complète, résumé et disponibilité en 2 secondes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var bookShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(searchText.isEmpty ? "Mes scans" : "Résultats")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(displayedBooks.count) livre\(displayedBooks.count > 1 ? "s" : "")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if displayedBooks.isEmpty {
                Text("Aucun résultat — essaie une autre idée.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(displayedBooks) { book in
                        NavigationLink(value: book) {
                            BookCard(book: book)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var proBanner: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Picpic Pro")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Scan d'étagère et plus — dès 29,99 €/an, ou 49,99 € à vie.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(16)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("home.proBanner")
    }

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Aller plus loin")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(PremiumFeature.all) { feature in
                    FeatureTile(feature: feature,
                                isLocked: feature.requiresPro && !proStore.isPro,
                                action: action(for: feature))
                }
            }
        }
        .alert("Scanne d'abord un livre 📚", isPresented: $showScanFirstHint) {
            Button("Scanner", role: .none) { showScanner = true }
            Button("Plus tard", role: .cancel) {}
        } message: {
            Text("La disponibilité s'affiche sur la fiche de chaque livre scanné.")
        }
    }

    /// Every tile leads to a real, shipped feature (no teasers).
    private func action(for feature: PremiumFeature) -> () -> Void {
        switch feature.id {
        case "shelfscan":
            return {
                if proStore.isPro {
                    showShelfScan = true
                } else {
                    showPaywall = true
                }
            }
        case "semantic":
            return { searchFocused = true }
        case "freereading":
            return { showFreeLibrary = true }
        case "availability":
            return {
                if let latest = books.first {
                    navPath.append(latest)
                } else {
                    showScanFirstHint = true
                }
            }
        case "stats":
            return {
                if proStore.isPro {
                    showStats = true
                } else {
                    showPaywall = true
                }
            }
        default:
            return {}
        }
    }

    private var scanButton: some View {
        Button {
            showScanner = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "barcode.viewfinder")
                    .font(.title3)
                Text("Scanner")
                    .font(.headline)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(Theme.ink, in: Capsule())
            .foregroundStyle(.white)
            .shadow(color: Theme.ink.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(PressableStyle())
        .padding(.bottom, 12)
    }

    private var fetchingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text("Recherche du livre…")
                    .font(.subheadline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

// MARK: - Book card

struct BookCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: book.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZStack {
                        LinearGradient(colors: [Theme.lavender, Theme.ink],
                                       startPoint: .top, endPoint: .bottom)
                        Image(systemName: "book.closed.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(width: 120, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.15), radius: 8, y: 4)

            Text(book.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(book.authorsLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 120, alignment: .leading)
    }
}

// MARK: - Feature tile

struct FeatureTile: View {
    let feature: PremiumFeature
    var isLocked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: feature.symbol)
                        .font(.title3)
                        .foregroundStyle(feature.tint)
                    Spacer()
                    if isLocked {
                        Label("Pro", systemImage: "lock.fill")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.gold.opacity(0.18), in: Capsule())
                            .foregroundStyle(Theme.gold)
                    }
                }
                Spacer(minLength: 0)
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Text(feature.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.05), radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle())
    }
}
