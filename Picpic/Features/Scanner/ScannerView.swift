//
//  ScannerView.swift
//  Picpic
//
//  ISBN barcode scanning via VisionKit's DataScanner (EAN-13),
//  with a manual-entry fallback (also used on Simulator, which
//  has no camera).
//

import SwiftUI
import Vision
import VisionKit

struct ScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onISBN: (String) -> Void

    @State private var manualISBN = ""
    @State private var rejectedCode = false

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    private var manualISBNIsValid: Bool {
        Self.validISBN(manualISBN) != nil
    }

    /// Returns the cleaned digits when the input is a plausible book ISBN
    /// (10 digits, or 13 digits prefixed 978/979), nil otherwise.
    static func validISBN(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        guard digits.count == 13 || digits.count == 10 else { return nil }
        if digits.count == 13, !digits.hasPrefix("978"), !digits.hasPrefix("979") { return nil }
        return digits
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if scannerAvailable {
                    BarcodeScannerRepresentable { code in
                        handle(code)
                    }
                    .ignoresSafeArea()

                    scanOverlay
                } else {
                    unavailableView
                }
            }
            .navigationTitle("Scanner un livre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                manualEntry
                    .padding()
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var scanOverlay: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                .frame(width: 260, height: 150)
                .overlay(alignment: .top) {
                    Text(rejectedCode
                         ? "Ce n'est pas un livre — vise le code ISBN (978…)"
                         : "Vise le code-barres au dos du livre")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.5), in: Capsule())
                        .offset(y: -44)
                }
            Spacer()
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var unavailableView: some View {
        ContentUnavailableView(
            "Caméra indisponible",
            systemImage: "camera.on.rectangle",
            description: Text("Sur simulateur ou sans caméra, saisis l'ISBN ci-dessous (13 chiffres au dos du livre).")
        )
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                TextField("ISBN (ex. 9782070368228)", text: $manualISBN)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("isbnField")
                Button {
                    handle(manualISBN)
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                }
                .accessibilityLabel("Valider l'ISBN")
                .disabled(!manualISBNIsValid)
            }
            if !manualISBN.isEmpty && !manualISBNIsValid {
                Text("Un ISBN fait 10 chiffres, ou 13 en commençant par 978/979.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Returns true when the code was accepted (book ISBN), so the
    /// scanner coordinator only latches after a real success.
    @discardableResult
    private func handle(_ raw: String) -> Bool {
        guard let digits = Self.validISBN(raw) else {
            rejectedCode = true
            return false
        }
        onISBN(digits)
        dismiss()
        return true
    }
}

// MARK: - VisionKit wrapper

private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    /// Returns true when the payload was accepted; the coordinator keeps
    /// scanning until then.
    let onCode: (String) -> Bool

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8])],
            qualityLevel: .accurate,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Bool
        private var didFire = false

        init(onCode: @escaping (String) -> Bool) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didFire else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    if onCode(payload) {
                        didFire = true
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } else {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    }
                    return
                }
            }
        }
    }
}
