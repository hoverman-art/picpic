//
//  ProStore.swift
//  Picpic
//
//  Monétisation zéro backend : RevenueCat gère les reçus côté store,
//  l'app ne lit que l'entitlement `picpic_pro`.
//  Règle absolue (ROADMAP) : jamais de cap de livres ni de scans —
//  le paywall ne porte que sur la valeur ajoutée.
//

import Foundation
import RevenueCat

@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()

    static let entitlementID = "picpic_pro"

    /// Clés publiques RevenueCat (projet Picpic) : Test Store en debug pour
    /// acheter en simulateur sans App Store Connect, App Store en release.
    #if DEBUG
    private static let apiKey = "test_QmLDuFKeKAVojAwfOVGEbgHeXQo"
    #else
    private static let apiKey = "appl_VBDYOVSzBAejmzGxzZfxYVathCs"
    #endif

    private(set) var isPro: Bool
    private(set) var packages: [Package] = []
    private(set) var isPurchasing = false
    var lastError: String?

    /// Les tests UI forcent l'un ou l'autre côté de la barrière sans réseau.
    private let forcedPro: Bool

    private init() {
        forcedPro = ProcessInfo.processInfo.arguments.contains("-uitest-pro")
        isPro = forcedPro
    }

    static func configure() {
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
    }

    /// Observation continue de l'entitlement, lancée une fois depuis la racine.
    func observeCustomerInfo() async {
        guard !forcedPro else { return }
        for await info in Purchases.shared.customerInfoStream {
            isPro = info.entitlements[Self.entitlementID]?.isActive == true
        }
    }

    func loadOfferingsIfNeeded() async {
        guard packages.isEmpty else { return }
        do {
            let offerings = try await Purchases.shared.offerings()
            packages = offerings.current?.availablePackages ?? []
        } catch {
            lastError = "Impossible de charger les formules. Vérifie ta connexion et réessaie."
        }
    }

    func package(for type: PackageType) -> Package? {
        packages.first { $0.packageType == type }
    }

    func purchase(_ package: Package) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled {
                isPro = result.customerInfo.entitlements[Self.entitlementID]?.isActive == true
            }
        } catch let error as ErrorCode where error == .purchaseCancelledError {
            // Annulation volontaire : pas d'alerte.
        } catch {
            lastError = "L'achat n'a pas abouti. Rien n'a été débité, tu peux réessayer."
        }
    }

    func restorePurchases() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            isPro = info.entitlements[Self.entitlementID]?.isActive == true
            if !isPro {
                lastError = "Aucun achat Picpic Pro trouvé sur ce compte."
            }
        } catch {
            lastError = "La restauration n'a pas abouti. Vérifie ta connexion et réessaie."
        }
    }
}
