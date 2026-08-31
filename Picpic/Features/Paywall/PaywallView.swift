//
//  PaywallView.swift
//  Picpic
//
//  Paywall Picpic Pro. Le lifetime est mis en avant : « pas d'abonnement
//  obligatoire parce que pas de serveurs » (positionnement ROADMAP).
//  Les prix affichés viennent du store via RevenueCat, avec un libellé
//  de secours hors connexion.
//

import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(ProStore.self) private var proStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: PackageType = .lifetime
    @State private var appeared = false

    private struct Plan: Identifiable {
        let type: PackageType
        let name: String
        let fallbackPrice: String
        let caption: String
        var badge: String?
        var id: String { name }
    }

    private let plans: [Plan] = [
        Plan(type: .monthly, name: "Mensuel", fallbackPrice: "3,99 €",
             caption: "par mois, sans engagement"),
        Plan(type: .annual, name: "Annuel", fallbackPrice: "29,99 €",
             caption: "par an, soit 2,50 €/mois"),
        Plan(type: .lifetime, name: "À vie", fallbackPrice: "49,99 €",
             caption: "une fois, à toi pour toujours", badge: "Le bon plan"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                featureList
                planPicker
                ctaButton
                restoreButton
                freeReminder
            }
            .padding(20)
            .padding(.bottom, 16)
        }
        .background(Theme.paper)
        .overlay(alignment: .topTrailing) { closeButton }
        .task { await proStore.loadOfferingsIfNeeded() }
        .onAppear { appeared = true }
        .onChange(of: proStore.isPro) { _, newValue in
            if newValue { dismiss() }
        }
        .alert("Oups", isPresented: .init(
            get: { proStore.lastError != nil },
            set: { if !$0 { proStore.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(proStore.lastError ?? "")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            MascotView(pose: .reading, height: 110)
            Text("Picpic Pro")
                .font(.display(34))
                .foregroundStyle(Theme.ink)
            Text("Pas d'abonnement obligatoire : Picpic n'a pas de serveurs. La formule à vie est à toi, point.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 28)
        .staggeredAppear(index: 0, isVisible: appeared)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            featureRow(symbol: "camera.metering.matrix", tint: Theme.accent,
                       title: "Scan d'étagère",
                       detail: "Toute une étagère cataloguée en une photo.")
            featureRow(symbol: "text.badge.checkmark", tint: Theme.lavender,
                       title: "Fiches de révision illimitées",
                       detail: "3 par mois offertes à tout le monde. (bientôt)")
            featureRow(symbol: "chart.bar.fill", tint: .purple,
                       title: "Rétrospective personnalisée",
                       detail: "Ton année lecture façon Wrapped, à ta sauce. (bientôt)")
            featureRow(symbol: "apps.iphone", tint: .pink,
                       title: "Widgets & Live Activity",
                       detail: "Ta lecture en cours sur l'écran d'accueil. (bientôt)")
            Text("Tout ce qui sortira en Pro est inclus, sans payer plus.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .staggeredAppear(index: 1, isVisible: appeared)
    }

    private func featureRow(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            ForEach(plans) { plan in
                planCard(plan)
            }
        }
        .staggeredAppear(index: 2, isVisible: appeared)
    }

    private func planCard(_ plan: Plan) -> some View {
        let isSelected = selectedPlan == plan.type
        let price = proStore.package(for: plan.type)?.storeProduct.localizedPriceString
            ?? plan.fallbackPrice
        return Button {
            selectedPlan = plan.type
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(plan.name)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        if let badge = plan.badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.gold.opacity(0.2), in: Capsule())
                                .foregroundStyle(Theme.gold)
                        }
                    }
                    Text(plan.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(price)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
            }
            .padding(16)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("paywall.plan.\(plan.type == .annual ? "annual" : plan.type == .monthly ? "monthly" : "lifetime")")
    }

    private var ctaButton: some View {
        Button {
            guard let package = proStore.package(for: selectedPlan) else {
                Task { await proStore.loadOfferingsIfNeeded() }
                return
            }
            Task { await proStore.purchase(package) }
        } label: {
            HStack {
                if proStore.isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text("Débloquer Picpic Pro")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.ink, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(PressableStyle())
        .disabled(proStore.isPurchasing)
        .accessibilityIdentifier("paywall.cta")
        .staggeredAppear(index: 3, isVisible: appeared)
    }

    private var restoreButton: some View {
        Button("Déjà Pro ? Restaurer mes achats") {
            Task { await proStore.restorePurchases() }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.teal)
        .disabled(proStore.isPurchasing)
        .accessibilityIdentifier("paywall.restore")
    }

    private var freeReminder: some View {
        Text("Toujours gratuit, pour tout le monde : scans et livres illimités, recherche par idée, disponibilité autour de toi.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .accessibilityIdentifier("paywall.close")
        .accessibilityLabel("Fermer")
    }
}

#Preview {
    PaywallView()
        .environment(ProStore.shared)
}
