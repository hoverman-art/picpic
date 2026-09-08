//
//  RevisionSheetStore.swift
//  Picpic
//
//  Quota des fiches de révision : 3 livres par mois en gratuit, illimité en Pro.
//  Le compteur porte sur les livres, pas sur les ouvertures — revenir réviser
//  la même fiche dix fois ne coûte rien, c'est bien le but.
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class RevisionSheetStore {

    static let shared = RevisionSheetStore()

    /// Nombre de livres révisables par mois sans Picpic Pro.
    static let freeMonthlyQuota = 3

    private(set) var openedISBNs: [String] = [] {
        didSet { UserDefaults.standard.set(openedISBNs, forKey: "revision.openedISBNs") }
    }

    private var periodKey: String {
        didSet { UserDefaults.standard.set(periodKey, forKey: "revision.period") }
    }

    private init() {
        let defaults = UserDefaults.standard
        periodKey = defaults.string(forKey: "revision.period") ?? Self.currentPeriodKey()
        openedISBNs = defaults.stringArray(forKey: "revision.openedISBNs") ?? []
        // Les observateurs de propriete ne se declenchent pas depuis un init :
        // sans cette ecriture, la cle de periode n'existe jamais en base et le
        // compteur ne retombe jamais a zero au changement de mois.
        defaults.set(periodKey, forKey: "revision.period")
        defaults.set(openedISBNs, forKey: "revision.openedISBNs")
        rolloverIfNeeded()
    }

    private static func currentPeriodKey(now: Date = .now) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: now)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)"
    }

    /// Remet le compteur à zéro au changement de mois.
    func rolloverIfNeeded(now: Date = .now) {
        let key = Self.currentPeriodKey(now: now)
        guard key != periodKey else { return }
        periodKey = key
        openedISBNs = []
    }

    var remainingThisMonth: Int {
        max(0, Self.freeMonthlyQuota - openedISBNs.count)
    }

    /// Un livre déjà ouvert ce mois-ci reste ouvert : le quota compte les
    /// livres découverts, pas les allers-retours.
    func canOpen(isbn: String, isPro: Bool) -> Bool {
        if isPro { return true }
        rolloverIfNeeded()
        return openedISBNs.contains(isbn) || openedISBNs.count < Self.freeMonthlyQuota
    }

    func recordOpen(isbn: String, isPro: Bool) {
        guard !isPro else { return }
        rolloverIfNeeded()
        guard !openedISBNs.contains(isbn) else { return }
        openedISBNs.append(isbn)
    }
}
