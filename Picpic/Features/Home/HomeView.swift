//
//  HomeView.swift
//  Picpic
//
//  Home: semantic search, scanned books shelf, premium feature grid,
//  scan button, and the smart suggestion / rating modals.
//

import SwiftUI
import SwiftData

private enum HomeSheet: String, Identifiable {
    case paywall, shelfScan, freeLibrary, stats, sudoc, goals, quotes, assistant
    /// `import` est un mot réservé : la valeur brute garde le nom court, qui
    /// sert d'argument de lancement aux tests UI et aux captures.
    case importLibrary = "import"

    var id: String { rawValue }
}

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
    /// Couvertures ou tranches. Conservé : c'est une préférence d'affichage,
    /// pas un état de navigation, et la redemander à chaque lancement agace.
    @AppStorage("home.shelfAsSpines") private var shelfAsSpines = false
    /// Les écrans de fonctionnalité passent par une seule feuille : empiler
    /// dix `.sheet` sur la même vue devient vite impossible à raisonner.
    @State private var sheet: HomeSheet?
    /// Livre audio du jour en cours d'écoute.
    @State private var playingAudiobook: FreeAudiobook?
    /// Ce que les catalogues ouverts proposent pour la recherche en cours.
    @State private var catalogResults: [CatalogResult] = []
    @State private var catalogSearching = false
    /// Émissions gratuites qui parlent du sujet cherché.
    @State private var podcasts: [Podcast] = []
    @State private var resolvingPodcast: String?
    /// Ce que la recherche visuelle a demandé d'ouvrir.
    @State private var pending = PendingBook.shared
    @FocusState private var searchFocused: Bool
    /// Réserve sous le contenu pour le bouton Scanner flottant : elle grandit
    /// avec la taille de texte, sinon le bouton recouvre la dernière carte.
    @ScaledMetric(relativeTo: .headline) private var scanButtonInset: CGFloat = 100

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

                    // Ce qu'on ouvre l'application pour voir arrive en premier :
                    // l'étagère est passée juste sous la recherche, et la carte
                    // BU, la série et la bannière Pro sont descendues sous elle.
                    if !searchText.isEmpty {
                        catalogSection
                        podcastSection
                    }

                    if books.isEmpty {
                        emptyState
                            .staggeredAppear(index: 2, isVisible: appeared)
                    } else {
                        bookShelf
                            .staggeredAppear(index: 2, isVisible: appeared)
                    }

                    DailyAudioShelf(playing: $playingAudiobook)
                        .staggeredAppear(index: 3, isVisible: appeared)

                    campusCard
                        .staggeredAppear(index: 3, isVisible: appeared)
                    GoalStrip(books: books) { sheet = .goals }
                        .staggeredAppear(index: 4, isVisible: appeared)

                    if !proStore.isPro {
                        proBanner
                            .staggeredAppear(index: 5, isVisible: appeared)
                    }

                    featureGrid
                        .staggeredAppear(index: 6, isVisible: appeared)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, scanButtonInset)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.paper)
            .overlay(alignment: .bottom) { scanButton }
            // La recherche dans les catalogues suit la frappe, avec un temps
            // mort : sans lui, « Bovary » lancerait six requêtes.
            // La recherche visuelle d'iOS 26 ouvre l'application sur un livre :
            // s'il est déjà dans la bibliothèque, on va sur sa fiche ; sinon on
            // remplit la recherche avec son titre, et « Ailleurs qu'ici »
            // propose de l'ajouter. Un intent ne peut pas naviguer lui-même.
            .onChange(of: pending.isbn) { _, _ in openPendingBook() }
            .onChange(of: pending.title) { _, _ in openPendingBook() }
            .task { openPendingBook() }
            .task(id: searchText) {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard query.count >= 3 else {
                    catalogResults = []
                    podcasts = []
                    catalogSearching = false
                    return
                }
                catalogSearching = true
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                async let books = CatalogSearchService.shared.search(query)
                async let shows = PodcastService.shared.search(query)
                catalogResults = await books
                podcasts = await shows
                catalogSearching = false
            }
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
            .sheet(item: $playingAudiobook) { audiobook in
                AudioPlayerView(audiobook: audiobook)
            }
            .sheet(isPresented: $viewModel.showSuggestionModal) {
                SmartSuggestionModal(books: books)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $showTutorial) {
                TutorialView()
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .paywall: PaywallView()
                case .shelfScan: ShelfScanView()
                case .freeLibrary: FreeLibraryView()
                case .stats: StatsView()
                case .sudoc: SudocSearchView()
                case .goals: GoalsView()
                case .quotes: QuotesView()
                case .assistant: AssistantView()
                case .importLibrary: ImportView()
                }
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
                case "paywall": sheet = .paywall
                case "shelfscan": sheet = .shelfScan
                case "freereading": sheet = .freeLibrary
                case "stats": sheet = .stats
                case "sudoc": sheet = .sudoc
                case "goals": sheet = .goals
                case "quotes": sheet = .quotes
                case "assistant": sheet = .assistant
                case "import": sheet = .importLibrary
                case "tutorial": showTutorial = true
                case "bookdetail":
                    if let first = books.first { navPath.append(first) }
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

    /// La recherche filtre à la frappe, mais rien ne le disait : sans touche
    /// de validation ni bouton, le champ avait l'air cassé et le clavier ne
    /// se fermait jamais. Trois ajouts : la touche « Rechercher » ferme le
    /// clavier, une croix efface, et le défilement referme le clavier.
    private func openPendingBook() {
        guard pending.isbn != nil || pending.title != nil else { return }
        if let isbn = pending.isbn, let book = books.first(where: { $0.isbn == isbn }) {
            navPath = NavigationPath()
            navPath.append(book)
        } else if let title = pending.title {
            searchText = title
        }
        pending.clear()
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(Theme.accent)
            TextField("Cherche par idée : « roman sur la mer »…", text: $searchText)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("home.search")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.ink.opacity(0.3))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.searchClear")
                .accessibilityLabel("Effacer la recherche")
            } else if searchFocused {
                Button("OK") { searchFocused = false }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.searchDone")
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.06), radius: 10, y: 4)
        .animation(.easeInOut(duration: 0.15), value: searchText.isEmpty)
        .animation(.easeInOut(duration: 0.15), value: searchFocused)
    }

    /// Sudoc en tête d'accueil : la recherche par sujet dans le fonds d'une BU
    /// est ce que Picpic fait de plus singulier, et le premier geste utile
    /// quand la bibliothèque est encore vide.
    private var campusCard: some View {
        Button {
            sheet = .sudoc
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "building.columns.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.teal, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(campusTitle)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text("Cherche par sujet dans le catalogue des BU françaises et vois ce que la bibliothèque a en rayon.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.teal.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("home.campusCard")
    }

    private var campusTitle: String {
        settings.studyField.map { "\($0.label) à la BU" } ?? "Ta filière à la BU"
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
            // Le lecteur qui vient de Goodreads ou de Babelio a deux cents
            // livres à reprendre : lui proposer de scanner le premier, c'est
            // lui demander de recommencer sa bibliothèque à la main.
            Button {
                sheet = .importLibrary
            } label: {
                Label("J'ai déjà une bibliothèque ailleurs", systemImage: "square.and.arrow.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityIdentifier("home.importFromEmpty")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Ce que les catalogues ouverts proposent, sous les livres qu'on possède.
    ///
    /// La recherche par idée ne classait que la bibliothèque scannée : taper
    /// le titre d'un roman qu'on n'a pas encore donnait « aucun résultat »,
    /// comme si le livre n'existait pas. Ces lignes-là viennent de Google
    /// Books et d'Open Library, et s'ajoutent en un geste.
    @ViewBuilder
    private var catalogSection: some View {
        if catalogSearching || !catalogResults.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Ailleurs qu'ici")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        // L'identifiant va sur le titre, pas sur la section :
                        // posé sur le conteneur, il écrasait celui de chaque
                        // bouton « Ajouter » et les rendait introuvables.
                        .accessibilityIdentifier("home.catalogResults")
                    if catalogSearching { ProgressView().controlSize(.small) }
                }
                Text("Trouvé dans les catalogues ouverts — ajoute-le pour le suivre.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(catalogResults) { result in
                    catalogRow(result)
                }
            }
        }
    }

    private func catalogRow(_ result: CatalogResult) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: result.coverURLString.flatMap(URL.init(string:))) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "book.closed")
                    .foregroundStyle(Theme.ink.opacity(0.25))
            }
            .frame(width: 38, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text([result.authorsLabel, result.year].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if let isbn = result.isbn {
                Button {
                    Task {
                        await viewModel.addBook(isbn: isbn, context: modelContext, settings: settings)
                        searchText = ""
                        searchFocused = false
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("home.catalogAdd")
                .accessibilityLabel("Ajouter \(result.title)")
            } else {
                // Sans ISBN, l'application ne sait ni retrouver la couverture,
                // ni chercher la disponibilité : mieux vaut le dire que
                // d'ajouter une fiche vide.
                Text("sans ISBN")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.05), radius: 8, y: 3)
    }

    /// Ce qui se dit là-dessus, gratuitement, à l'oreille.
    ///
    /// L'ordre est celui de l'annuaire d'Apple — voir PodcastService pour
    /// pourquoi on ne le reclasse pas.
    @ViewBuilder
    private var podcastSection: some View {
        if !podcasts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("À écouter là-dessus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("home.podcastResults")
                Text("Des émissions gratuites, jouées depuis le flux de leur auteur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(podcasts) { podcast in
                    podcastRow(podcast)
                }
            }
        }
    }

    private func podcastRow(_ podcast: Podcast) -> some View {
        Button {
            Task { await openPodcast(podcast) }
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: podcast.artworkURLString.flatMap(URL.init(string:))) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Theme.teal.opacity(0.12)
                            Image(systemName: "waveform")
                                .foregroundStyle(Theme.teal)
                        }
                    }
                }
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(podcast.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text([podcast.author, podcast.genre].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if resolvingPodcast == podcast.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "play.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.teal)
                }
            }
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.05), radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle())
        .disabled(resolvingPodcast != nil)
        .accessibilityIdentifier("home.podcastRow")
    }

    /// Le flux n'est lu qu'au moment d'écouter : six cents kilooctets pour cent
    /// épisodes, ce n'est pas ce qu'on télécharge en tapant une recherche.
    private func openPodcast(_ podcast: Podcast) async {
        resolvingPodcast = podcast.id
        defer { resolvingPodcast = nil }
        playingAudiobook = await PodcastService.shared.episodes(of: podcast)
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
                shelfStyleToggle
            }
            if displayedBooks.isEmpty {
                Text("Aucun résultat — essaie une autre idée.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            if shelfAsSpines {
                SpineShelf(books: displayedBooks)
            } else {
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
    }

    /// Un seul bouton plutôt qu'un sélecteur segmenté : il n'y a que deux
    /// modes, et l'icône montre celui vers lequel on bascule.
    private var shelfStyleToggle: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                shelfAsSpines.toggle()
            }
        } label: {
            Image(systemName: shelfAsSpines ? "square.grid.2x2" : "books.vertical")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink.opacity(0.55))
                .padding(6)
                .background(Theme.ink.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.shelfStyle")
        .accessibilityLabel(shelfAsSpines ? "Afficher les couvertures" : "Afficher les tranches")
    }

    private var proBanner: some View {
        Button {
            sheet = .paywall
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
                    sheet = .shelfScan
                } else {
                    sheet = .paywall
                }
            }
        case "sudoc":
            return { sheet = .sudoc }
        case "goals":
            return { sheet = .goals }
        case "quotes":
            return { sheet = .quotes }
        case "assistant":
            // Gratuite avec un quota, comme les fiches de révision : le Pro
            // lève la limite, il ne déverrouille pas l'accès.
            return { sheet = .assistant }
        case "import":
            return { sheet = .importLibrary }
        case "semantic":
            return { searchFocused = true }
        case "freereading":
            return { sheet = .freeLibrary }
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
                    sheet = .stats
                } else {
                    sheet = .paywall
                }
            }
        default:
            return {}
        }
    }

    /// Le bouton flotte au-dessus du contenu qui défile : il passait en encre
    /// sur la bannière Pro, elle aussi en encre, et les deux se confondaient.
    /// Le corail est la couleur de l'action dans le système (voir Theme) —
    /// c'était sa place depuis le début, et il se détache du papier comme de
    /// l'encre. Le liseré papier l'isole de ce qui passe dessous.
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
            .background(Theme.accent, in: Capsule())
            .overlay(Capsule().stroke(Theme.paper, lineWidth: 3))
            .foregroundStyle(.white)
            .shadow(color: Theme.ink.opacity(0.30), radius: 14, y: 6)
        }
        .buttonStyle(PressableStyle())
        .padding(.bottom, 12)
        .accessibilityIdentifier("home.scan")
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
            // La pastille n'apparaît qu'une fois la fiche ouverte : c'est là
            // que l'estimation est calculée, et elle reste ensuite. De retour
            // de brocante, la valeur du lot se lit d'un coup d'œil.
            .overlay(alignment: .topTrailing) {
                if let low = book.estimatedLow, let high = book.estimatedHigh {
                    Text(low == high ? "≈ \(low) €" : "\(low)–\(high) €")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .foregroundStyle(Theme.ink)
                        .padding(6)
                        .accessibilityLabel("Estimé entre \(low) et \(high) euros")
                }
            }

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
