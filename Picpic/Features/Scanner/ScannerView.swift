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
    @State private var torchHint = false

    private var scannerAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
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
                    Text("Vise le code-barres au dos du livre")
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
            .disabled(manualISBN.filter(\.isNumber).count < 10)
        }
    }

    private func handle(_ raw: String) {
        let digits = raw.filter(\.isNumber)
        guard digits.count == 13 || digits.count == 10 else { return }
        // Books only: EAN-13 for books starts with 978/979.
        if digits.count == 13, !digits.hasPrefix("978"), !digits.hasPrefix("979") { return }
        onISBN(digits)
        dismiss()
    }
}

// MARK: - VisionKit wrapper

private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

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
        let onCode: (String) -> Void
        private var didFire = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didFire else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    didFire = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCode(payload)
                    return
                }
            }
        }
    }
}
