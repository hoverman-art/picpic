//
//  GoalsView.swift
//  Picpic
//
//  « Mon année de lecture » : un objectif que l'on se fixe, une série que l'on
//  entretient. Gratuit — c'est ce qui fait revenir tous les jours.
//

import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ReadingGoalStore.self) private var goals
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    private var finishedThisYear: [Book] {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: .now)
        return books
            .filter { book in
                guard let finished = book.dateFinished else { return false }
                return calendar.component(.year, from: finished) == year
            }
            .sorted { ($0.dateFinished ?? .distantPast) > ($1.dateFinished ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    goalCard
                    streakCard
                    finishedSection
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("Mon année")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    // MARK: - Objectif

    private var goalCard: some View {
        @Bindable var goals = goals
        let done = goals.booksFinishedThisYear(books)

        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Theme.ink.opacity(0.08), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: goals.progress(books))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: goals.progress(books))
                VStack(spacing: 2) {
                    Text("\(done)")
                        .font(.display(40))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Text(goals.annualGoal > 0 ? "sur \(goals.annualGoal)" : "livres")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 160)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(done) livres terminés sur \(goals.annualGoal)")

            Text(goals.paceLabel(books))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .accessibilityIdentifier("goals.pace")

            Stepper(value: $goals.annualGoal, in: 0...200) {
                HStack {
                    Text("Objectif de l'année")
                        .font(.subheadline)
                    Spacer()
                    Text(goals.annualGoal > 0 ? "\(goals.annualGoal) livres" : "aucun")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityIdentifier("goals.stepper")
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Série

    private var streakCard: some View {
        HStack(spacing: 18) {
            VStack(spacing: 2) {
                Image(systemName: goals.hasReadToday() ? "flame.fill" : "flame")
                    .font(.title)
                    .foregroundStyle(goals.currentStreak > 0 ? Theme.accent : .secondary)
                Text("\(goals.currentStreak)")
                    .font(.display(28))
                    .foregroundStyle(Theme.ink)
                Text(goals.currentStreak > 1 ? "jours" : "jour")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 78)

            VStack(alignment: .leading, spacing: 4) {
                Text(streakTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(streakDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if goals.bestStreak > 0 {
                    Text("Record : \(goals.bestStreak) jours")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("goals.streak")
    }

    private var streakTitle: String {
        switch (goals.currentStreak, goals.hasReadToday()) {
        case (0, _): return "Pas encore de série"
        case (_, true): return "Série en cours"
        default: return "Série à sauver"
        }
    }

    private var streakDetail: String {
        switch (goals.currentStreak, goals.hasReadToday()) {
        case (0, _):
            return "Avance dans un livre aujourd'hui pour la lancer."
        case (_, true):
            return "C'est fait pour aujourd'hui. À demain."
        default:
            return "Avance dans un livre aujourd'hui pour ne pas la perdre."
        }
    }

    // MARK: - Terminés

    @ViewBuilder
    private var finishedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Terminés cette année")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)

            if finishedThisYear.isEmpty {
                Text("Aucun livre terminé pour l'instant. Passe un livre en « Terminé » depuis sa fiche.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(finishedThisYear) { book in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Theme.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text(book.authorsLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if let finished = book.dateFinished {
                            Text(finished.formatted(.dateTime.day().month(.abbreviated)))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}

/// Bandeau compact d'accueil : la série et l'objectif, en une ligne.
struct GoalStrip: View {
    let books: [Book]
    let action: () -> Void

    @Environment(ReadingGoalStore.self) private var goals

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: goals.hasReadToday() ? "flame.fill" : "flame")
                    .foregroundStyle(goals.currentStreak > 0 ? Theme.accent : .secondary)
                Text(goals.currentStreak > 0
                     ? "\(goals.currentStreak) jour\(goals.currentStreak > 1 ? "s" : "") de suite"
                     : "Lance ta série")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)

                Divider().frame(height: 18)

                Text(goals.annualGoal > 0
                     ? "\(goals.booksFinishedThisYear(books))/\(goals.annualGoal) cette année"
                     : "Fixe un objectif")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("home.goalStrip")
    }
}
