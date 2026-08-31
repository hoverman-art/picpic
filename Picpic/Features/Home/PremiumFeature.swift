//
//  PremiumFeature.swift
//  Picpic
//
//  The home grid's features. Everything listed here ships in the app —
//  no teasers: a feature only appears once it is fully implemented.
//

import SwiftUI

struct PremiumFeature: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    /// Feature verrouillée derrière l'entitlement `picpic_pro`.
    var requiresPro: Bool = false

    static let all: [PremiumFeature] = [
        PremiumFeature(id: "shelfscan", title: "Scan d'étagère",
                       subtitle: "Toute une étagère en une photo",
                       symbol: "camera.metering.matrix", tint: Theme.accent,
                       requiresPro: true),
        PremiumFeature(id: "semantic", title: "Recherche par idée",
                       subtitle: "« un roman sur la mer »",
                       symbol: "sparkle.magnifyingglass", tint: Theme.gold),
        PremiumFeature(id: "freereading", title: "Lire & écouter gratuit",
                       subtitle: "Classiques en EPUB et audio",
                       symbol: "headphones", tint: Theme.lavender),
        PremiumFeature(id: "availability", title: "Dispo autour de moi",
                       subtitle: "BU, médiathèques, librairies",
                       symbol: "location.fill", tint: Theme.teal),
        PremiumFeature(id: "stats", title: "Ta rétrospective",
                       subtitle: "Ton année lecture, en chiffres",
                       symbol: "chart.bar.fill", tint: .purple,
                       requiresPro: true),
    ]
}
