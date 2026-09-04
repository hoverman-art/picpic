//
//  QuoteCaptureView.swift
//  Picpic
//
//  Photographier une page, choisir les lignes qui comptent, garder la citation.
//  L'OCR sert à éviter de retaper — la sélection reste à l'utilisateur, ce qui
//  évite d'embarquer plus de texte que ce qu'il a voulu relever.
//

import SwiftUI
import SwiftData
import PhotosUI

struct QuoteCaptureView: View {
    /// Livre d'origine, si la capture part d'une fiche.
    var book: Book?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ReadingGoalStore.self) private var goals

    private enum Phase: Equatable {
        case pick
        case reading
        case select([String])
        case edit
    }

    @State private var phase: Phase = .pick
    @State private var selectedLines: Set<Int> = []
    @State private var text = ""
    @State private var pageText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var errorMessage: String?

    private let ocr = QuoteOCRService()

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pick: pickStep
                case .reading: readingStep
                case .select(let lines): selectStep(lines)
                case .edit: editStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper)
            .navigationTitle("Une citation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                if phase == .edit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Garder") { save() }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("quote.save")
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await analyze(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await analyze(item) }
            }
            .alert("Oups", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { phase = .pick }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Étapes

    private var pickStep: some View {
        VStack(spacing: 16) {
            MascotView(pose: .reading, height: 120)
            Text("Garde la phrase, pas la photo")
                .font(.display(24))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("Photographie la page : Picpic lit le texte, tu choisis les lignes à garder. La photo, elle, n'est pas conservée.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                if CameraPicker.isAvailable {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Photographier la page", systemImage: "camera.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(PressableStyle())
                }

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choisir une photo", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(PressableStyle())

                Button {
                    text = ""
                    phase = .edit
                } label: {
                    Text("Écrire la citation à la main")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
                .accessibilityIdentifier("quote.manual")
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .padding(.vertical, 30)
    }

    private var readingStep: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Lecture de la page…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func selectStep(_ lines: [String]) -> some View {
        VStack(spacing: 0) {
            Text("Touche les lignes de la citation")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(lines.indices, id: \.self) { index in
                        Button {
                            toggle(index, in: lines)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: selectedLines.contains(index)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedLines.contains(index) ? Theme.accent : Color.secondary.opacity(0.5))
                                Text(lines[index])
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(
                                selectedLines.contains(index) ? Theme.accent.opacity(0.08) : .white,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Button {
                phase = .edit
            } label: {
                Text(selectedLines.isEmpty ? "Choisis au moins une ligne" : "Continuer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(selectedLines.isEmpty ? Color.gray.opacity(0.3) : Theme.accent,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(PressableStyle())
            .disabled(selectedLines.isEmpty)
            .padding(20)
            .accessibilityIdentifier("quote.continue")
        }
    }

    private var editStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("La citation")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(minHeight: 160)
                        .padding(10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityIdentifier("quote.editor")
                }

                HStack {
                    Text("Page")
                        .font(.subheadline)
                    Spacer()
                    TextField("—", text: $pageText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .padding(8)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if let book {
                    Label(book.title, systemImage: "book.closed")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Actions

    private func toggle(_ index: Int, in lines: [String]) {
        if selectedLines.contains(index) {
            selectedLines.remove(index)
        } else {
            selectedLines.insert(index)
        }
        text = ocr.joinLines(selectedLines.sorted().map { lines[$0] })
    }

    private func analyze(_ item: PhotosPickerItem) async {
        phase = .reading
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = QuoteOCRError.unreadable.errorDescription
            return
        }
        await analyze(image)
    }

    private func analyze(_ image: UIImage) async {
        phase = .reading
        do {
            let lines = try await ocr.recognizeLines(in: image)
            selectedLines = []
            text = ""
            phase = .select(lines)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Lecture impossible."
        }
    }

    private func save() {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let quote = Quote(
            text: cleaned,
            bookISBN: book?.isbn,
            bookTitle: book?.title,
            bookAuthors: book?.authors ?? [],
            page: Int(pageText.filter(\.isNumber))
        )
        modelContext.insert(quote)
        try? modelContext.save()
        goals.recordActivity()
        dismiss()
    }
}
