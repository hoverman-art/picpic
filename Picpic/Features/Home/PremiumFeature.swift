//
//  PremiumFeature.swift
//  Picpic
//
//  The home grid's features. Everything listed here ships in the app —
//  no teasers: a feature only appears once it is fully implemented.
//
//  La teinte d'une tuile dit quelque chose, ou la tuile reste neutre. Les dix
//  tuiles portaient auparavant cinq couleurs distribuées sans règle — deux
//  tuiles teal sans rapport entre elles, `gold` sur « Recherche par idée » et
//  sur « Citations », et un `.purple` système hors palette. De la décoration,
//  pas un système (voir docs/DESIGN-SYSTEME.md).
//
//    teal      dehors et gratuit — BU, médiathèques, domaine public
//    lavender  sur ton iPhone — assistant, recherche par idée, OCR
//    gold      Picpic Pro
//    ink       ta bibliothèque, sans plus — neutre, et c'est voulu
//
//  Le corail (`Theme.accent`) n'apparaît pas ici : il est réservé à l'action,
//  c'est-à-dire au bouton Scanner. Un accent qu'on voit partout ne signale
//  plus rien.
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
        // En tête : c'est la fonction qui n'existe nulle part ailleurs.
        PremiumFeature(id: "sudoc", title: "Ma filière à la BU",
                       subtitle: "Le rayon d'à côté, par sujet",
                       symbol: "building.columns.fill", tint: Theme.teal),
        PremiumFeature(id: "shelfscan", title: "Scan d'étagère",
                       subtitle: "Toute une étagère en une photo",
                       symbol: "camera.metering.matrix", tint: Theme.gold,
                       requiresPro: true),
        PremiumFeature(id: "semantic", title: "Recherche par idée",
                       subtitle: "« un roman sur la mer »",
                       symbol: "sparkle.magnifyingglass", tint: Theme.lavender),
        PremiumFeature(id: "freereading", title: "Lire & écouter gratuit",
                       subtitle: "Classiques en EPUB et audio",
                       symbol: "headphones", tint: Theme.teal),
        PremiumFeature(id: "availability", title: "Dispo autour de moi",
                       subtitle: "BU, médiathèques, librairies",
                       symbol: "location.fill", tint: Theme.teal),
        PremiumFeature(id: "assistant", title: "Demande à Picpic",
                       subtitle: "Ton assistant de lecture, sur l'iPhone",
                       symbol: "sparkles", tint: Theme.lavender),
        PremiumFeature(id: "import", title: "Importer ma biblio",
                       subtitle: "Goodreads, Babelio, CSV",
                       symbol: "square.and.arrow.down", tint: Theme.ink),
        PremiumFeature(id: "quotes", title: "Citations",
                       subtitle: "Photographie, garde, partage",
                       symbol: "text.quote", tint: Theme.lavender),
        PremiumFeature(id: "goals", title: "Objectifs & séries",
                       subtitle: "Ton année, jour après jour",
                       symbol: "flame.fill", tint: Theme.ink),
        PremiumFeature(id: "stats", title: "Ta rétrospective",
                       subtitle: "Ton année lecture, en chiffres",
                       symbol: "chart.bar.fill", tint: Theme.gold,
                       requiresPro: true),
    ]
}
