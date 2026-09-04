//
//  ReadingGoalStore.swift
//  Picpic
//
//  Objectif annuel et série de jours de lecture. Tout tient dans UserDefaults :
//  trois entiers et une date, calculés sur l'appareil, comme le reste de l'app.
//

import Foundation
import SwiftUI

@Observable
@MainActor
final class ReadingGoalStore {

    static let shared = ReadingGoalStore()

    /// Nombre de livres à terminer dans l'année. 0 = pas d'objectif.
    var annualGoal: Int {
        didSet { UserDefaults.standard.set(annualGoal, forKey: "goal.annual") }
    }

    private(set) var currentStreak: Int {
        didSet { UserDefaults.standard.set(currentStreak, forKey: "goal.streak.current") }
    }

    private(set) var bestStreak: Int {
        didSet { UserDefaults.standard.set(bestStreak, forKey: "goal.streak.best") }
    }

    /// Dernier jour où l'utilisateur a lu (jour civil, heure ignorée).
    private(set) var lastActiveDay: Date? {
        didSet { UserDefaults.standard.set(lastActiveDay, forKey: "goal.streak.lastDay") }
    }

    private let calendar = Calendar.current

    private init() {
        let defaults = UserDefaults.standard
        // 12 livres — un par mois : un objectif que l'on tient, pas une punition.
        annualGoal = defaults.object(forKey: "goal.annual") as? Int ?? 12
        currentStreak = defaults.integer(forKey: "goal.streak.current")
        bestStreak = defaults.integer(forKey: "goal.streak.best")
        lastActiveDay = defaults.object(forKey: "goal.streak.lastDay") as? Date
    }

    // MARK: - Série

    /// À appeler dès que l'utilisateur lit : passage d'un livre « en cours » ou
    /// « terminé », pages mises à jour, citation capturée.
    func recordActivity(on date: Date = .now) {
        let today = calendar.startOfDay(for: date)
        guard let last = lastActiveDay.map({ calendar.startOfDay(for: $0) }) else {
            currentStreak = 1
            bestStreak = max(bestStreak, 1)
            lastActiveDay = today
            return
        }
        if calendar.isDate(last, inSameDayAs: today) { return }

        let days = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        // Une seule journée sautée suffit à casser la série : c'est la règle
        // partout ailleurs, et une série « rattrapable » ne motive plus personne.
        currentStreak = days == 1 ? currentStreak + 1 : 1
        bestStreak = max(bestStreak, currentStreak)
        lastActiveDay = today
    }

    /// Remet la série à zéro si le dernier jour lu est trop ancien. À appeler à
    /// l'ouverture de l'app : sans ça, une série de 30 jours abandonnée en mars
    /// s'afficherait encore en septembre.
    func refreshStreak(now: Date = .now) {
        guard let last = lastActiveDay.map({ calendar.startOfDay(for: $0) }) else {
            currentStreak = 0
            return
        }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        if days > 1 { currentStreak = 0 }
    }

    /// Vrai si la série est encore « chaude » aujourd'hui.
    func hasReadToday(now: Date = .now) -> Bool {
        guard let last = lastActiveDay else { return false }
        return calendar.isDate(last, inSameDayAs: now)
    }

    // MARK: - Objectif annuel

    func booksFinishedThisYear(_ books: [Book], now: Date = .now) -> Int {
        let year = calendar.component(.year, from: now)
        return books.filter {
            guard let finished = $0.dateFinished else { return false }
            return calendar.component(.year, from: finished) == year
        }.count
    }

    func progress(_ books: [Book], now: Date = .now) -> Double {
        guard annualGoal > 0 else { return 0 }
        return min(1, Double(booksFinishedThisYear(books, now: now)) / Double(annualGoal))
    }

    /// Où l'on devrait en être à cette date de l'année, pour situer l'avance
    /// ou le retard sans culpabiliser.
    func expectedByNow(now: Date = .now) -> Int {
        guard annualGoal > 0 else { return 0 }
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        let daysInYear = calendar.range(of: .day, in: .year, for: now)?.count ?? 365
        return Int((Double(annualGoal) * Double(dayOfYear) / Double(daysInYear)).rounded())
    }

    func paceLabel(_ books: [Book], now: Date = .now) -> String {
        guard annualGoal > 0 else { return "Aucun objectif fixé" }
        let done = booksFinishedThisYear(books, now: now)
        let expected = expectedByNow(now: now)
        if done >= annualGoal { return "Objectif atteint 🎉" }
        let delta = done - expected
        switch delta {
        case 1...: return "\(delta) livre\(delta > 1 ? "s" : "") d'avance"
        case 0: return "Pile dans les temps"
        default: return "\(-delta) livre\(-delta > 1 ? "s" : "") de retard"
        }
    }
}
