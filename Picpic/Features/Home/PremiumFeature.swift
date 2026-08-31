//
//  PremiumFeature.swift
//  Picpic
//
//  The "liste ×10" of premium features surfaced on the home grid.
//  Order = the roadmap's recursive ranking (most selling first),
//  from the market audit + paywall benchmark (see ROADMAP).
//

import SwiftUI

struct PremiumFeature: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    var isAvailable: Bool = false
    /// Feature verrouillée derrière l'entitlement `picpic_pro` une fois livrée.
    var requiresPro: Bool = false

    static let all: [PremiumFeature] = [
        PremiumFeature(id: "shelfscan", title: "Scan d'étagère",
                       subtitle: "Toute une étagère en une photo",
                       symbol: "camera.metering.matrix", tint: Theme.accent,
                       isAvailable: true, requiresPro: true),
        PremiumFeature(id: "semantic", title: "Recherche par idée",
                       subtitle: "« un roman sur la mer »",
                       symbol: "sparkle.magnifyingglass", tint: Theme.gold, isAvailable: true),
        PremiumFeature(id: "availability", title: "Dispo autour de moi",
                       subtitle: "BU, médiathèques, librairies",
                       symbol: "location.fill", tint: Theme.teal, isAvailable: true),
        PremiumFeature(id: "summaries", title: "Fiches de révision",
                       subtitle: "L'essentiel avant l'exam",
                       symbol: "text.badge.checkmark", tint: Theme.lavender),
        PremiumFeature(id: "stats", title: "Stats & Rétrospective",
                       subtitle: "Ton année lecture façon Wrapped",
                       symbol: "chart.bar.fill", tint: .purple),
        PremiumFeature(id: "widgets", title: "Widgets & Live Activity",
                       subtitle: "Ta lecture sur l'écran d'accueil",
                       symbol: "apps.iphone", tint: .pink),
        PremiumFeature(id: "streaks", title: "Objectifs & séries",
                       subtitle: "Garde le rythme de lecture",
                       symbol: "flame.fill", tint: .orange),
        PremiumFeature(id: "quotes", title: "Citations & cartes",
                       subtitle: "Capture tes passages préférés",
                       symbol: "quote.opening", tint: .indigo),
        PremiumFeature(id: "field", title: "Mode étudiant",
                       subtitle: "Reco par filière, Sudoc, BU",
                       symbol: "graduationcap.fill", tint: .cyan),
        PremiumFeature(id: "sync", title: "Sync & alertes",
                       subtitle: "iCloud + alertes librairie",
                       symbol: "icloud.fill", tint: .mint),
    ]
}
