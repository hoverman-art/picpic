//
//  BookDetailView.swift
//  Picpic
//
//  Book sheet: cover, metadata, summary, reading status, and
//  "Où le trouver ?" — open catalogues + Sudoc university holdings.
//

import SwiftUI
import SafariServices

/// Identifiable wrapper for `.sheet(item:)` — avoids a retroactive
/// `URL: Identifiable` conformance that would collide if Foundation
/// or a dependency ever declares one.
private struct SafariLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct BookDetailView: View {
    @Bindable var book: Book

    @State private var holdings: [HoldingLibrary] = []
    @State private var holdingsLoaded = false
    @State private var safariLink: SafariLink?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                statusPicker
                if let description = book.bookDescription, !description.isEmpty {
                    summarySection(description)
                }
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
        .sheet(item: $safariLink) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
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
            set: { book.status = $0 }
        )) {
            ForEach(ReadingStatus.allCases) { status in
                Label(status.label, systemImage: status.symbol).tag(status)
            }
        }
        .pickerStyle(.segmented)
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
            VStack(alignment: .leading, spacing: 10) {
                Label("Dispo dans \(holdings.count) BU en France (Sudoc)", systemImage: "building.columns.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                ForEach(holdings.prefix(5)) { library in
                    HStack {
                        Text(library.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if let km = library.distanceFromLaRochelle {
                            Text(km < 1 ? "ici" : "\(Int(km)) km")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(km < 20 ? Theme.teal : .secondary)
                        }
                    }
                }
            }
            .padding(14)
            .background(Theme.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
