//
//  ShelfScanView.swift
//  Picpic
//
//  Scan d'étagère (Picpic Pro) : une photo de l'étagère, OCR des tranches,
//  rapprochement Google Books, puis ajout en lot à la bibliothèque.
//

import SwiftUI
import SwiftData
import PhotosUI

struct ShelfScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(UserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case pick
        case analyzing
        case results
        case adding
        case done(added: Int, skipped: Int)
    }

    @State private var phase: Phase = .pick
    @State private var candidates: [ShelfCandidate] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var errorMessage: String?

    private let scanService = ShelfScanService()
    private let metadataService = BookMetadataService()

    var body: some View {
        NavigationStack {
            content
                .background(Theme.paper)
                .navigationTitle("Scan d'étagère")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") { dismiss() }
                    }
                }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await analyze(item: item) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                Task { await analyze(image: image) }
            }
            .ignoresSafeArea()
        }
        .alert("Oups", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .pick:
            pickView
        case .analyzing:
            waitingView(title: "Lecture des tranches…",
                        subtitle: "OCR sur ta photo, puis reconnaissance des livres. Tout se passe entre ton iPhone et les catalogues ouverts.")
        case .results:
            resultsView
        case .adding:
            waitingView(title: "Ajout à ta bibliothèque…",
                        subtitle: "Fiches complètes, résumés et couvertures en cours de récupération.")
        case .done(let added, let skipped):
            doneView(added: added, skipped: skipped)
        }
    }

    // MARK: - Phases

    private var pickView: some View {
        VStack(spacing: 20) {
            Spacer()
            MascotView(pose: .reading, height: 130)
            Text("Photographie ton étagère")
                .font(.display(26))
                .foregroundStyle(Theme.ink)
            Text("Cadre les tranches bien de face, avec de la lumière. Picpic lit les titres et retrouve chaque livre.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label("Prendre une photo", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.ink, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("shelfscan.camera")
            }

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choisir dans mes photos", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.white, in: Capsule())
                    .foregroundStyle(Theme.ink)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("shelfscan.pickPhoto")
        }
        .padding(20)
    }

    private func waitingView(title: String, subtitle: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            MascotView(pose: .idle, height: 110)
            ProgressView()
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedCount: Int {
        candidates.filter(\.isSelected).count
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    ForEach($candidates) { $candidate in
                        candidateRow($candidate)
                    }
                } header: {
                    Text("\(candidates.count) livre\(candidates.count > 1 ? "s" : "") reconnu\(candidates.count > 1 ? "s" : "") — décoche les erreurs")
                }
            }
            .scrollContentBackground(.hidden)

            Button {
                Task { await addSelection() }
            } label: {
                Text(selectedCount == 0
                     ? "Sélectionne au moins un livre"
                     : "Ajouter \(selectedCount) livre\(selectedCount > 1 ? "s" : "")")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedCount == 0 ? Color.gray : Theme.ink, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableStyle())
            .disabled(selectedCount == 0)
            .padding(20)
            .accessibilityIdentifier("shelfscan.addSelected")
        }
    }

    private func candidateRow(_ candidate: Binding<ShelfCandidate>) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: candidate.wrappedValue.coverURLString.flatMap(URL.init)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZStack {
                        Theme.lavender.opacity(0.4)
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 42, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.wrappedValue.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(candidate.wrappedValue.authorsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Lu sur la tranche : « \(candidate.wrappedValue.spineText) »")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: candidate.isSelected)
                .labelsHidden()
                .tint(Theme.teal)
        }
    }

    private func doneView(added: Int, skipped: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            MascotView(pose: .reading, height: 130)
            Text(added > 0 ? "\(added) livre\(added > 1 ? "s" : "") ajouté\(added > 1 ? "s" : "") 🎉" : "Rien de nouveau")
                .font(.display(26))
                .foregroundStyle(Theme.ink)
            if skipped > 0 {
                Text("\(skipped) déjà dans ta bibliothèque ou introuvable\(skipped > 1 ? "s" : "") — passé\(skipped > 1 ? "s" : "").")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Voir ma bibliothèque")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.ink, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("shelfscan.finish")
        }
        .padding(20)
    }

    // MARK: - Actions

    private func analyze(item: PhotosPickerItem) async {
        photoItem = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "Impossible de lire cette photo."
            return
        }
        await analyze(image: image)
    }

    private func analyze(image: UIImage) async {
        phase = .analyzing
        do {
            candidates = try await scanService.scan(image: image)
            phase = .results
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "L'analyse a échoué. Réessaie avec une autre photo."
            phase = .pick
        }
    }

    /// Ajout en lot : fiche complète via la cascade ISBN habituelle, repli sur
    /// les données de la recherche si la fiche est introuvable.
    private func addSelection() async {
        phase = .adding
        var added = 0
        var skipped = 0

        for candidate in candidates where candidate.isSelected {
            let isbn = candidate.isbn
            let existing = try? modelContext.fetch(FetchDescriptor<Book>(
                predicate: #Predicate { $0.isbn == isbn }
            ))
            if existing?.isEmpty == false {
                skipped += 1
                continue
            }

            let book: Book
            if let metadata = try? await metadataService.fetch(isbn: isbn) {
                book = Book(
                    isbn: metadata.isbn,
                    title: metadata.title,
                    authors: metadata.authors.isEmpty ? candidate.authors : metadata.authors,
                    bookDescription: metadata.description,
                    subjects: metadata.subjects,
                    coverURLString: metadata.coverURLString ?? candidate.coverURLString,
                    publisher: metadata.publisher,
                    publishedDate: metadata.publishedDate,
                    pageCount: metadata.pageCount,
                    language: metadata.language
                )
            } else {
                book = Book(
                    isbn: isbn,
                    title: candidate.title,
                    authors: candidate.authors,
                    bookDescription: nil,
                    subjects: [],
                    coverURLString: candidate.coverURLString,
                    publisher: nil,
                    publishedDate: nil,
                    pageCount: nil,
                    language: nil
                )
            }
            book.embedding = SemanticSearchService.shared.vector(for: book.semanticText)
            modelContext.insert(book)
            added += 1
        }

        do {
            try modelContext.save()
            settings.scanCount += added
        } catch {
            errorMessage = "Impossible d'enregistrer les livres. Réessaie."
            phase = .results
            return
        }
        phase = .done(added: added, skipped: skipped)
    }
}

// MARK: - Camera picker (UIImagePickerController, pas d'API SwiftUI native)

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.dismiss()
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
