//
//  EPUBReaderView.swift
//  Picpic
//
//  La liseuse. Les classiques du domaine public se lisent dans Picpic, pas
//  dans Safari : on garde le confort de lecture (thème, police, interligne),
//  la reprise au bon chapitre, et le livre reste disponible hors connexion
//  une fois téléchargé.
//

import SwiftUI
import WebKit

struct EPUBReaderView: View {
    let epubURL: URL
    let fallbackTitle: String
    /// Clé de reprise : l'ISBN quand il existe, sinon l'URL.
    let progressKey: String

    @Environment(\.dismiss) private var dismiss
    @Environment(ReaderSettings.self) private var settings
    @Environment(ReadingGoalStore.self) private var goals

    @State private var document: EPUBDocument?
    @State private var chapterIndex = 0
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showChapters = false
    @State private var showSettings = false
    @State private var showChrome = true

    private var chapter: EPUBChapter? {
        guard let document, document.chapters.indices.contains(chapterIndex) else { return nil }
        return document.chapters[chapterIndex]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                settings.theme.background.ignoresSafeArea()

                if isLoading {
                    loadingState
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if let document, let chapter, let html = try? document.html(for: chapter) {
                    page(html: html)
                } else {
                    errorState("Ce chapitre est illisible.")
                }
            }
            .navigationTitle(document?.title ?? fallbackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showChrome ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if document != nil {
                        Button { showChapters = true } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Chapitres")
                        Button { showSettings = true } label: {
                            Image(systemName: "textformat.size")
                        }
                        .accessibilityLabel("Confort de lecture")
                        .accessibilityIdentifier("reader.settings")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if document != nil, showChrome { pager }
            }
            .sheet(isPresented: $showChapters) { chapterList }
            .sheet(isPresented: $showSettings) {
                ReaderSettingsSheet()
                    .presentationDetents([.height(380)])
                    .presentationDragIndicator(.visible)
            }
        }
        .task { await load() }
    }

    // MARK: - États

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Téléchargement du livre…")
                .font(.subheadline)
                .foregroundStyle(settings.theme.foreground.opacity(0.7))
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent)
            Text("Lecture impossible")
                .font(.headline)
                .foregroundStyle(settings.theme.foreground)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(settings.theme.foreground.opacity(0.7))
                .multilineTextAlignment(.center)
            Button {
                Task { await load() }
            } label: {
                Text("Réessayer")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(30)
    }

    private func page(html: String) -> some View {
        ChapterWebView(
            html: html,
            css: settings.css(),
            backgroundColor: settings.theme.background,
            onTapCenter: { withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() } }
        )
        .id("\(chapterIndex)-\(settings.theme.rawValue)-\(Int(settings.fontSize))-\(settings.typeface.rawValue)-\(settings.spacing.rawValue)")
        .ignoresSafeArea(edges: .bottom)
    }

    private var pager: some View {
        HStack {
            Button {
                go(to: chapterIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .padding(12)
            }
            .disabled(chapterIndex == 0)
            .accessibilityLabel("Chapitre précédent")

            Spacer()
            if let document {
                Text("\(chapterIndex + 1) / \(document.chapters.count)")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
            }
            Spacer()

            Button {
                go(to: chapterIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .padding(12)
            }
            .disabled(chapterIndex + 1 >= (document?.chapters.count ?? 0))
            .accessibilityLabel("Chapitre suivant")
            .accessibilityIdentifier("reader.next")
        }
        .foregroundStyle(settings.theme.foreground)
        .padding(.horizontal, 16)
        .background(settings.theme.background.opacity(0.96))
    }

    private var chapterList: some View {
        NavigationStack {
            List {
                ForEach(Array((document?.chapters ?? []).enumerated()), id: \.element.id) { index, item in
                    Button {
                        go(to: index)
                        showChapters = false
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 26, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(index == chapterIndex ? .bold : .regular))
                                    .foregroundStyle(Theme.ink)
                                if let excerpt = document?.excerpt(for: item) {
                                    Text(excerpt)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                            if index == chapterIndex {
                                Image(systemName: "book.fill")
                                    .font(.caption)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Chapitres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { showChapters = false }
                }
            }
        }
    }

    // MARK: - Chargement

    private func go(to index: Int) {
        guard let document, document.chapters.indices.contains(index) else { return }
        chapterIndex = index
        settings.setLastChapter(index, for: progressKey)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let data = try await EPUBLoader.shared.data(for: epubURL)
            // Décompression et analyse hors du fil principal : un gros EPUB
            // figerait l'écran le temps de l'ouvrir.
            let parsed = try await Task.detached(priority: .userInitiated) {
                try EPUBDocument(data: data)
            }.value
            document = parsed
            let saved = settings.lastChapter(for: progressKey)
            chapterIndex = parsed.chapters.indices.contains(saved) ? saved : 0
            // Ouvrir un livre, c'est lire : la série du jour est acquise.
            goals.recordActivity()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Le livre n'a pas pu être téléchargé."
        }
    }
}

// MARK: - Réglages

private struct ReaderSettingsSheet: View {
    @Environment(ReaderSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings

        return NavigationStack {
            Form {
                Section("Thème") {
                    Picker("Thème", selection: $settings.theme) {
                        ForEach(ReaderSettings.Theme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("reader.theme")
                }
                Section("Police") {
                    Picker("Police", selection: $settings.typeface) {
                        ForEach(ReaderSettings.Typeface.allCases) { face in
                            Text(face.label).tag(face)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("A").font(.footnote)
                        Slider(value: $settings.fontSize, in: 14...30, step: 1)
                            .accessibilityIdentifier("reader.fontSize")
                        Text("A").font(.title3)
                    }
                }
                Section("Interligne") {
                    Picker("Interligne", selection: $settings.spacing) {
                        ForEach(ReaderSettings.Spacing.allCases) { spacing in
                            Text(spacing.label).tag(spacing)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Confort de lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Rendu d'un chapitre

private struct ChapterWebView: UIViewRepresentable {
    let html: String
    let css: String
    let backgroundColor: Color
    let onTapCenter: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Un chapitre est du texte : rien à charger, rien à exécuter.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(backgroundColor)
        webView.scrollView.backgroundColor = UIColor(backgroundColor)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTapCenter = onTapCenter
        webView.backgroundColor = UIColor(backgroundColor)
        webView.scrollView.backgroundColor = UIColor(backgroundColor)
        let document = """
        <!doctype html><html lang="fr"><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <style>\(css)</style>
        </head><body>\(html)</body></html>
        """
        guard context.coordinator.lastDocument != document else { return }
        context.coordinator.lastDocument = document
        webView.loadHTMLString(document, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTapCenter: onTapCenter) }

    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        var onTapCenter: () -> Void
        var lastDocument: String?

        init(onTapCenter: @escaping () -> Void) {
            self.onTapCenter = onTapCenter
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            // Seule la bande centrale masque/affiche les commandes : les bords
            // restent au défilement et à la sélection de texte.
            let x = recognizer.location(in: view).x
            if x > view.bounds.width * 0.3, x < view.bounds.width * 0.7 {
                onTapCenter()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// Un lien interne à l'EPUB ne doit pas sortir de la liseuse.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
        }
    }
}

// MARK: - Téléchargement et cache

actor EPUBLoader {
    static let shared = EPUBLoader()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 90
        session = URLSession(configuration: config)
    }

    /// Le fichier est gardé en cache disque : un livre ouvert une fois se
    /// relit sans réseau.
    func data(for url: URL) async throws -> Data {
        let cached = cacheURL(for: url)
        if let data = try? Data(contentsOf: cached), !data.isEmpty { return data }

        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        try? data.write(to: cached, options: .atomic)
        return data
    }

    private func cacheURL(for url: URL) -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("epubs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Nom de fichier stable et sans caractère interdit.
        let name = String(url.absoluteString.hashValue.magnitude, radix: 36)
        return directory.appendingPathComponent("\(name).epub")
    }
}
