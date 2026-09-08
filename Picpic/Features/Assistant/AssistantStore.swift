//
//  AssistantStore.swift
//  Picpic
//
//  Quota de l'assistant : 5 questions par jour en gratuit, illimité en Pro.
//
//  Pourquoi un quota alors que le modèle est gratuit et local. Justement parce
//  qu'il l'est : rien ne coûte, donc rien n'oblige à limiter, et la limite doit
//  se justifier autrement que par la facture. Elle se justifie par la promesse
//  du paywall — « le Pro ne restreint jamais l'existant, il ajoute » (ROADMAP).
//  L'assistant est un ajout, jamais une fonction qu'on aurait retirée du
//  gratuit. Cinq questions par jour laissent de quoi s'en servir vraiment avant
//  de décider s'il vaut un abonnement.
//
//  Le compteur est journalier et non mensuel, contrairement aux fiches de
//  révision : on pose une question quand on en a une, pas une fois par mois.
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class AssistantStore {

    static let shared = AssistantStore()

    /// Questions par jour sans Picpic Pro.
    static let freeDailyQuota = 5

    private(set) var askedToday: Int = 0 {
        didSet { UserDefaults.standard.set(askedToday, forKey: "assistant.askedToday") }
    }

    private var periodKey: String {
        didSet { UserDefaults.standard.set(periodKey, forKey: "assistant.period") }
    }

    private init() {
        let defaults = UserDefaults.standard
        periodKey = defaults.string(forKey: "assistant.period") ?? Self.currentPeriodKey()
        askedToday = defaults.integer(forKey: "assistant.askedToday")
        // Les observateurs de propriete ne se declenchent pas depuis un init :
        // sans cette ecriture, la cle de periode n'existe jamais en base et le
        // compteur ne retombe jamais a zero au changement de jour.
        defaults.set(periodKey, forKey: "assistant.period")
        defaults.set(askedToday, forKey: "assistant.askedToday")
        rolloverIfNeeded()
    }

    private static func currentPeriodKey(now: Date = .now) -> String {
        let p = Calendar.current.dateComponents([.year, .month, .day], from: now)
        return "\(p.year ?? 0)-\(p.month ?? 0)-\(p.day ?? 0)"
    }

    /// Remet le compteur à zéro au changement de jour.
    func rolloverIfNeeded(now: Date = .now) {
        let key = Self.currentPeriodKey(now: now)
        guard key != periodKey else { return }
        periodKey = key
        askedToday = 0
    }

    var remainingToday: Int {
        max(0, Self.freeDailyQuota - askedToday)
    }

    func canAsk(isPro: Bool) -> Bool {
        if isPro { return true }
        rolloverIfNeeded()
        return askedToday < Self.freeDailyQuota
    }

    /// Ne compte que les questions réellement posées au modèle : une erreur de
    /// disponibilité ou une bibliothèque vide ne doit pas consommer un crédit.
    func recordAsk(isPro: Bool) {
        guard !isPro else { return }
        rolloverIfNeeded()
        askedToday += 1
    }
}
