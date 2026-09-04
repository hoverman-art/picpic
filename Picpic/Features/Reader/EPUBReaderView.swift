//
//  EPUBReaderView.swift
//  Picpic
//
//  La liseuse. Les classiques du domaine public se lisent dans Picpic, pas
//  dans Safari : confort de lecture (thème, police, interligne), reprise au
//  bon chapitre, disponibilité hors connexion une fois le livre téléchargé,
//  et lecture à voix haute avec la meilleure voix installée sur l'appareil.
//

import AVFoundation
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
    @State private var content: (html: String, paragraphs: [String])?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showChapters = false
    @State private var showSettings = false
    @State private var showChrome = true
    @State private var readAloud = ReadAloudController()

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
                } else if let content {
                    page(content.html)
                } else {
                    errorState("Ce chapitre est illisible.")
                }
            }
            .navigationTitle(document?.title ?? fallbackTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showChrome ? .visible : .hidden, for: .navigationBar)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                if document != nil, showChrome {
                    if readAloud.isSpeaking { listeningBar } else { pager }
                }
            }
            .sheet(isPresented: $showChapters) { chapterList }
            .sheet(isPresented: $showSettings) {
                ReaderSettingsSheet(onVoiceChanged: { readAloud.restartCurrentUtterance() })
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .task { await load() }
        .onDisappear { readAloud.stop() }
        .onChange(of: chapterIndex) { _, _ in loadChapterContent() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

    private func page(_ html: String) -> some View {
        ChapterWebView(
            html: html,
            css: settings.css(),
            backgroundColor: settings.theme.background,
            highlightedParagraph: readAloud.currentParagraph,
            onTapCenter: { withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() } }
        )
        .id("\(chapterIndex)-\(settings.theme.rawValue)-\(Int(settings.fontSize))-\(settings.typeface.rawValue)-\(settings.spacing.rawValue)")
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Barres du bas

    private var pager: some View {
        HStack {
            Button {
                go(to: chapterIndex - 1)
            } label: {
                Image(systemName: "chevron.left").font(.headline).padding(12)
            }
            .disabled(chapterIndex == 0)
            .accessibilityLabel("Chapitre précédent")

            Spacer()
            VStack(spacing: 2) {
                Button { toggleReadAloud() } label: {
                    Label("Écouter", systemImage: "speaker.wave.2.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("reader.listen")

                if let document {
                    Text("\(chapterIndex + 1) / \(document.chapters.count)")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(settings.theme.foreground.opacity(0.6))
                }
            }
            Spacer()

            Button {
                go(to: chapterIndex + 1)
            } label: {
                Image(systemName: "chevron.right").font(.headline).padding(12)
            }
            .disabled(chapterIndex + 1 >= (document?.chapters.count ?? 0))
            .accessibilityLabel("Chapitre suivant")
            .accessibilityIdentifier("reader.next")
        }
        .foregroundStyle(settings.theme.foreground)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(settings.theme.background.opacity(0.96))
    }

    private var listeningBar: some View {
        HStack(spacing: 8) {
            Button { readAloud.skipBackward() } label: {
                Image(systemName: "gobackward.15").font(.title3).padding(10)
            }
            .accessibilityLabel("Paragraphe précédent")

            Button {
                readAloud.isPaused ? readAloud.resume() : readAloud.pause()
            } label: {
                Image(systemName: readAloud.isPaused ? "play.fill" : "pause.fill")
                    .font(.title2)
                    .frame(width: 46, height: 46)
                    .background(Theme.accent, in: Circle())
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("reader.playPause")

            Button { readAloud.skipForward() } label: {
                Image(systemName: "goforward.15").font(.title3).padding(10)
            }
            .accessibilityLabel("Paragraphe suivant")

            Spacer(minLength: 4)

            if let current = readAloud.currentParagraph, let content {
                Text("\(current + 1) / \(content.paragraphs.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(settings.theme.foreground.opacity(0.6))
            }

            Button { readAloud.stop() } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).padding(10)
            }
            .accessibilityLabel("Arrêter la lecture")
        }
        .foregroundStyle(settings.theme.foreground)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
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

    // MARK: - Lecture à voix haute

    private func toggleReadAloud() {
        if readAloud.isSpeaking {
            readAloud.stop()
            return
        }
        guard let content, !content.paragraphs.isEmpty else { return }
        readAloud.onParagraphChange = { _ in }
        readAloud.onFinishedChapter = {
            // Enchaîner sur le chapitre suivant : on écoute un livre, pas un
            // chapitre. Au dernier, on s'arrête simplement.
            guard let document, chapterIndex + 1 < document.chapters.count else {
                readAloud.stop()
                return
            }
            go(to: chapterIndex + 1)
            if let next = self.content, !next.paragraphs.isEmpty {
                readAloud.start(paragraphs: next.paragraphs,
                                bookTitle: document.title,
                                chapterTitle: document.chapters[chapterIndex].title)
            }
        }
        readAloud.start(paragraphs: content.paragraphs,
                        bookTitle: document?.title ?? fallbackTitle,
                        chapterTitle: chapter?.title ?? "")
    }

    // MARK: - Chargement

    private func go(to index: Int) {
        guard let document, document.chapters.indices.contains(index) else { return }
        chapterIndex = index
        settings.setLastChapter(index, for: progressKey)
    }

    private func loadChapterContent() {
        guard let document, let chapter else { content = nil; return }
        content = (try? document.readable(chapter)) ?? nil
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
            loadChapterContent()
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
    var onVoiceChanged: () -> Void

    @Environment(ReaderSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var voices: [NarratorVoice] = []
    @State private var previewer = VoicePreviewer()

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
                voiceSection
            }
            .navigationTitle("Confort de lecture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .onAppear { voices = ReadAloudController.availableVoices() }
        .onDisappear { previewer.stop() }
    }

    @ViewBuilder
    private var voiceSection: some View {
        @Bindable var settings = settings

        Section {
            ForEach(voices) { voice in
                Button {
                    settings.voiceIdentifier = voice.id
                    previewer.play(voiceIdentifier: voice.id, rate: settings.speechRate)
                    onVoiceChanged()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: settings.voiceIdentifier == voice.id
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(settings.voiceIdentifier == voice.id
                                             ? Theme.accent : Color.secondary.opacity(0.5))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(voice.name)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                            Text(voice.language)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text(voice.qualityLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(voice.isHighQuality
                                        ? Theme.teal.opacity(0.18) : Color.secondary.opacity(0.12),
                                        in: Capsule())
                            .foregroundStyle(voice.isHighQuality ? Theme.teal : .secondary)
                    }
                }
                .accessibilityIdentifier("reader.voice.\(voice.id)")
            }

            HStack {
                Image(systemName: "tortoise")
                Slider(value: $settings.speechRate,
                       in: Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate) * 0.6)
                    .accessibilityIdentifier("reader.speechRate")
                    .onChange(of: settings.speechRate) { _, _ in onVoiceChanged() }
                Image(systemName: "hare")
            }
            .foregroundStyle(.secondary)
        } header: {
            Text("Voix de lecture")
        } footer: {
            if ReadAloudController.onlyStandardVoicesInstalled {
                // Apple ne permet pas à une app d'installer ses voix : le dire
                // franchement vaut mieux que de laisser croire à un défaut.
                Text("Seules les voix standard d'iOS sont installées. Les voix « Améliorée » et « Premium », bien plus naturelles, s'ajoutent dans Réglages › Accessibilité › Contenu énoncé › Voix — elles apparaîtront ici automatiquement.")
            } else {
                Text("Touche une voix pour l'entendre. Les voix Premium et Améliorées sont les plus naturelles.")
            }
        }
    }
}

/// Petit lecteur d'extrait, indépendant de la lecture en cours.
@Observable
@MainActor
private final class VoicePreviewer {
    private let synthesizer = AVSpeechSynthesizer()

    func play(voiceIdentifier: String, rate: Double) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: "Les grands classiques, lus à voix haute.")
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        utterance.rate = Float(rate)
        synthesizer.speak(utterance)
    }

    func stop() { synthesizer.stopSpeaking(at: .immediate) }
}

// MARK: - Rendu d'un chapitre

private struct ChapterWebView: UIViewRepresentable {
    let html: String
    let css: String
    let backgroundColor: Color
    let highlightedParagraph: Int?
    let onTapCenter: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Le script de surlignage est le nôtre ; ceux de l'EPUB ont été
        // retirés en amont (`strippingScripts`).
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
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
        <meta http-equiv="Content-Security-Policy"
              content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
        <style>\(css)</style>
        </head><body>\(html)
        <script>
        function ppHighlight(n) {
            document.querySelectorAll('.pp-now').forEach(function (e) { e.classList.remove('pp-now'); });
            var el = document.querySelector('[data-pp="' + n + '"]');
            if (el) {
                el.classList.add('pp-now');
                el.scrollIntoView({ block: 'center', behavior: 'smooth' });
            }
        }
        </script>
        </body></html>
        """
        if context.coordinator.lastDocument != document {
            context.coordinator.lastDocument = document
            context.coordinator.pendingHighlight = highlightedParagraph
            context.coordinator.isLoaded = false
            webView.loadHTMLString(document, baseURL: nil)
            return
        }
        context.coordinator.highlight(highlightedParagraph, in: webView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTapCenter: onTapCenter) }

    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        var onTapCenter: () -> Void
        var lastDocument: String?
        var pendingHighlight: Int?
        var appliedHighlight: Int?
        var isLoaded = false

        init(onTapCenter: @escaping () -> Void) {
            self.onTapCenter = onTapCenter
        }

        /// Le surlignage n'a de sens qu'une fois la page chargée : avant, on le
        /// met de côté et on l'applique à la fin de la navigation.
        func highlight(_ paragraph: Int?, in webView: WKWebView) {
            guard let paragraph else { return }
            guard isLoaded else { pendingHighlight = paragraph; return }
            guard appliedHighlight != paragraph else { return }
            appliedHighlight = paragraph
            webView.evaluateJavaScript("ppHighlight(\(paragraph))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            appliedHighlight = nil
            if let pending = pendingHighlight { highlight(pending, in: webView) }
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
