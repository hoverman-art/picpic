//
//  QuotesView.swift
//  Picpic
//
//  Le carnet de citations, et la carte que l'on partage. Gratuit : c'est ce
//  qui sort de l'app et la fait connaître.
//

import SwiftUI
import SwiftData

struct QuotesView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Quote.dateAdded, order: .reverse) private var quotes: [Quote]
    @Environment(\.modelContext) private var modelContext

    @State private var showCapture = false
    @State private var sharedQuote: Quote?

    var body: some View {
        NavigationStack {
            Group {
                if quotes.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper)
            .navigationTitle("Mes citations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCapture = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("quotes.add")
                }
            }
            .sheet(isPresented: $showCapture) {
                QuoteCaptureView()
            }
            .sheet(item: $sharedQuote) { quote in
                QuoteCardView(quote: quote)
                    .presentationDetents([.large])
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            MascotView(pose: .reading, height: 120)
            Text("Aucune citation")
                .font(.headline)
            Text("Photographie une page qui t'a marqué : Picpic en extrait le texte, tu gardes la phrase.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showCapture = true
            } label: {
                Label("Capturer une citation", systemImage: "text.viewfinder")
                    .font(.headline)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 4)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(quotes) { quote in
                    Button {
                        sharedQuote = quote
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("« \(quote.text) »")
                                .font(.callout)
                                .italic()
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                                .lineLimit(6)
                            HStack {
                                Text(quote.attribution.isEmpty ? "Sans livre" : quote.attribution)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if let page = quote.page {
                                    Text("p. \(page)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "square.and.arrow.up")
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button(role: .destructive) {
                            modelContext.delete(quote)
                            try? modelContext.save()
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - La carte partageable

struct QuoteCardView: View {
    let quote: Quote

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var palette: CardPalette = .paper

    enum CardPalette: String, CaseIterable, Identifiable {
        case paper, ink, coral

        var id: String { rawValue }

        var label: String {
            switch self {
            case .paper: return "Papier"
            case .ink: return "Encre"
            case .coral: return "Corail"
            }
        }

        var background: Color {
            switch self {
            case .paper: return Theme.paper
            case .ink: return Theme.ink
            case .coral: return Theme.accent
            }
        }

        var foreground: Color {
            switch self {
            case .paper: return Theme.ink
            case .ink, .coral: return .white
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                card
                    .frame(maxWidth: 320)
                    .shadow(color: Theme.ink.opacity(0.15), radius: 20, y: 10)

                Picker("Couleur", selection: $palette) {
                    ForEach(CardPalette.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)

                if let image = renderedImage {
                    ShareLink(
                        item: image,
                        preview: SharePreview("Citation", image: image)
                    ) {
                        Label("Partager", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.horizontal, 30)
                    .accessibilityIdentifier("quote.share")
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    /// La carte, aussi bien affichée à l'écran que rendue en image.
    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("”")
                .font(.system(size: 64, weight: .bold, design: .serif))
                .foregroundStyle(palette.foreground.opacity(0.35))
                .frame(height: 30, alignment: .top)

            Text(quote.text)
                .font(.system(size: 19, weight: .medium, design: .serif))
                .foregroundStyle(palette.foreground)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 2) {
                if !quote.attribution.isEmpty {
                    Text(quote.attribution)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(palette.foreground.opacity(0.85))
                }
                if let page = quote.page {
                    Text("page \(page)")
                        .font(.caption)
                        .foregroundStyle(palette.foreground.opacity(0.6))
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "barcode.viewfinder")
                    .font(.caption2)
                Text("Picpic")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(palette.foreground.opacity(0.5))
        }
        .padding(26)
        .frame(width: 320, alignment: .leading)
        .background(palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @MainActor
    private var renderedImage: Image? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = displayScale
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}
