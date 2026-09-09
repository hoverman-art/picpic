//
//  BookDetailView.swift
//  Picpic
//
//  Book sheet: cover, metadata, summary, reading status, and
//  "Où le trouver ?" — open catalogues + Sudoc university holdings.
//

import SwiftUI
import SwiftData
import SafariServices

/// Identifiable wrapper for `.sheet(item:)` — avoids a retroactive
/// `URL: Identifiable` conformance that would collide if Foundation
/// or a dependency ever declares one.
private struct SafariLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct BookDetailView: View {
    @Environment(ReadingGoalStore.self) private var goals
    @Bindable var book: Book

    @State private var holdings: [HoldingLibrary] = []
    @State private var holdingsLoaded = false
    @State private var safariLink: SafariLink?
    @State private var showQuoteCapture = false
    @State private var showRevision = false
    @Environment(\.modelContext) private var modelContext
    @State private var showPaywall = false
    /// Ce que vaut cet exemplaire, pour qui chine. Résolu à l'ouverture.
    @State private var valuation: BookValuation?
    @State private var valuationRunning = false
    @State private var showValuationMethod = false
    @Environment(ProStore.self) private var proStore
    @Environment(RevisionSheetStore.self) private var revisionStore
    @Query(sort: \Quote.dateAdded, order: .reverse) private var allQuotes: [Quote]

    /// Les citations relevées dans ce livre.
    private var quotes: [Quote] {
        allQuotes.filter { $0.bookISBN == book.isbn }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                statusPicker
                if let description = book.bookDescription, !description.isEmpty {
                    summarySection(description)
                }
                valueSection
                FreeReadingSection(book: book) { url in
                    safariLink = SafariLink(url: url)
                }
                personalSection
                quotesSection
                revisionButton
                availabilitySection
                if !book.subjects.isEmpty {
                    subjectsSection
                }
            }
            .padding(20)
        }
        .background(Theme.paper)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHoldings() }
        .task { await loadValuation() }
        .sheet(item: $safariLink) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showQuoteCapture) {
            QuoteCaptureView(book: book)
        }
        .sheet(isPresented: $showRevision) {
            RevisionSheetView(book: book)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 18) {
            AsyncImage(url: book.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZStack {
                        LinearGradient(colors: [Theme.lavender, Theme.ink], startPoint: .top, endPoint: .bottom)
                        Image(systemName: "book.closed.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(width: 110, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.2), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.display(22))
                    .foregroundStyle(Theme.ink)
                Text(book.authorsLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let publisher = book.publisher {
                    Text([publisher, book.publishedDate].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let pages = book.pageCount {
                    Label("\(pages) pages", systemImage: "book.pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("ISBN \(book.isbn)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusPicker: some View {
        Picker("Statut", selection: Binding(
            get: { book.status },
            set: { newStatus in
                book.status = newStatus
                // Faire avancer un livre compte comme avoir lu aujourd'hui.
                if newStatus == .reading || newStatus == .finished {
                    goals.recordActivity()
                }
            }
        )) {
            ForEach(ReadingStatus.allCases) { status in
                Label(status.label, systemImage: status.symbol).tag(status)
            }
        }
        .pickerStyle(.segmented)
    }

    /// Ce que le lecteur ajoute lui-même : sa note et ses remarques. C'est
    /// aussi la matière première de la fiche de révision.
    private var personalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mon avis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        // Retoucher l'étoile courante retire la note.
                        book.rating = (book.rating == star) ? nil : star
                        goals.recordActivity()
                    } label: {
                        Image(systemName: (book.rating ?? 0) >= star ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle((book.rating ?? 0) >= star ? Theme.gold : Color.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) étoile\(star > 1 ? "s" : "")")
                    .accessibilityIdentifier("book.star.\(star)")
                }
                Spacer(minLength: 0)
                if book.rating != nil {
                    Button("Effacer") { book.rating = nil }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Mes notes")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextEditor(text: $book.notes)
                    .font(.callout)
                    .frame(minHeight: 90)
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if book.notes.isEmpty {
                            Text("Ce que tu veux retenir…")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityIdentifier("book.notes")
            }
        }
        .padding(16)
        .background(.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Fiche de révision : 3 livres par mois en gratuit, illimité en Pro.
    private var revisionButton: some View {
        Button {
            if revisionStore.canOpen(isbn: book.isbn, isPro: proStore.isPro) {
                revisionStore.recordOpen(isbn: book.isbn, isPro: proStore.isPro)
                showRevision = true
            } else {
                showPaywall = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.and.pencil.and.ellipsis")
                    .font(.title3)
                    .foregroundStyle(Theme.lavender)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fiche de révision")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(revisionSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("book.revision")
    }

    private var revisionSubtitle: String {
        if proStore.isPro { return "Tes notes et tes citations, en mode révision" }
        if revisionStore.canOpen(isbn: book.isbn, isPro: false) {
            let left = revisionStore.remainingThisMonth
            return "Tes notes et tes citations · \(left) livre\(left > 1 ? "s" : "") ce mois-ci"
        }
        return "Quota du mois atteint — passe à Picpic Pro"
    }

    private var quotesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Citations")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    showQuoteCapture = true
                } label: {
                    Label("Capturer", systemImage: "text.viewfinder")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.gold.opacity(0.18), in: Capsule())
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("book.captureQuote")
            }

            if quotes.isEmpty {
                Text("Une phrase t'a marqué ? Photographie la page, Picpic en extrait le texte.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(quotes) { quote in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("« \(quote.text) »")
                            .font(.callout)
                            .italic()
                            .foregroundStyle(Theme.ink)
                            .lineLimit(4)
                        if let page = quote.page {
                            Text("page \(page)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private func summarySection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Résumé")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Ce que ça vaut

    /// Pour le chineur : ce qu'on peut dire honnêtement du prix, et où aller
    /// vérifier. Voir BookValueService — Picpic n'invente pas de cote, il
    /// réunit les signaux mesurables et montre sa règle.
    @ViewBuilder
    private var valueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ça vaut quoi ?")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if valuationRunning { ProgressView().controlSize(.small) }
            }

            if let valuation {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(valuation.range)
                        .font(.display(30))
                        .foregroundStyle(Theme.ink)
                    Text("d'occasion, estimé")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                signalRow(valuation)

                Button {
                    showValuationMethod.toggle()
                } label: {
                    Label(showValuationMethod ? "Masquer le calcul" : "Comment c'est estimé",
                          systemImage: showValuationMethod ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("value.method")

                if showValuationMethod {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(valuation.reasons, id: \.self) { reason in
                            Text("• \(reason)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Une estimation, pas une cote : c'est le marché qui décide. Vérifie les offres réelles ci-dessous.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .transition(.opacity)
                }

                marketRow
            } else if valuationRunning {
                Text("Estimation en cours…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Pas assez d'informations sur cette édition pour l'estimer. Les offres réelles restent consultables.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                marketRow
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: showValuationMethod)
        .accessibilityIdentifier("book.value")
    }

    /// Les trois signaux, en clair : format, âge, rareté.
    private func signalRow(_ valuation: BookValuation) -> some View {
        WrappingHStack(spacing: 8, lineSpacing: 8) {
            chip(valuation.collection ?? valuation.format.label, symbol: "book.closed")
            if let year = valuation.year {
                chip("édition \(year)", symbol: "calendar")
            }
            if let libraries = valuation.libraries {
                chip("\(libraries) bibliothèque\(libraries > 1 ? "s" : "")", symbol: "building.columns")
            }
            if let editions = valuation.editions {
                chip("\(editions) édition\(editions > 1 ? "s" : "")", symbol: "square.stack")
            }
        }
    }

    private func chip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.ink.opacity(0.05), in: Capsule())
            .foregroundStyle(Theme.ink.opacity(0.7))
    }

    /// Les offres réelles, ouvertes dans le navigateur.
    private var marketRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voir les offres réelles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink.opacity(0.55))
            WrappingHStack(spacing: 8, lineSpacing: 8) {
                ForEach(BookValueService.marketLinks(isbn: book.isbn), id: \.name) { link in
                    Button {
                        safariLink = SafariLink(url: link.url)
                    } label: {
                        Text(link.name)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Theme.teal.opacity(0.12), in: Capsule())
                            .foregroundStyle(Theme.teal)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("value.market.\(link.name)")
                }
            }
        }
    }

    private func loadValuation() async {
        guard valuation == nil, !valuationRunning else { return }
        valuationRunning = true
        defer { valuationRunning = false }
        let edition = await BnFService.shared.edition(isbn: book.isbn)
        let computed = await BookValueService.shared.valuation(isbn: book.isbn, edition: edition)
        valuation = computed
        // Gardée sur le livre : l'étagère l'affiche ensuite sans rappeler les
        // trois catalogues.
        if let computed {
            book.estimatedLow = computed.low
            book.estimatedHigh = computed.high
            book.valuedAt = .now
            try? modelContext.save()
        }
    }

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Où le trouver ?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)

            ForEach(AvailabilityService.shared.catalogueLinks(isbn: book.isbn, title: book.title)) { source in
                Button {
                    safariLink = SafariLink(url: source.url)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: source.symbol)
                            .font(.title3)
                            .foregroundStyle(Theme.teal)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text(source.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }

            sudocSection
        }
    }

    @ViewBuilder
    private var sudocSection: some View {
        if !holdings.isEmpty {
            // Une carte plutôt qu'une liste : « LA ROCHELLE-BU » ne dit rien,
            // un point sur une carte répond tout de suite à « est-ce près de
            // moi ? ». Toucher une ligne recentre la carte sur l'établissement.
            HoldingsMapView(holdings: holdings)
        } else if !holdingsLoaded {
            HStack(spacing: 8) {
                ProgressView()
                Text("Interrogation du Sudoc…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subjectsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Thèmes")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            WrappingHStack(spacing: 8, lineSpacing: 8) {
                ForEach(book.subjects, id: \.self) { subject in
                    Text(subject)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Theme.lavender.opacity(0.12), in: Capsule())
                        .foregroundStyle(Theme.ink)
                }
            }
        }
    }

    private func loadHoldings() async {
        defer { holdingsLoaded = true }
        guard holdings.isEmpty,
              let ppn = try? await AvailabilityService.shared.sudocPPNs(isbn: book.isbn).first,
              let libraries = try? await AvailabilityService.shared.holdingLibraries(ppn: ppn) else { return }
        holdings = libraries
    }
}

// MARK: - Safari helpers

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
