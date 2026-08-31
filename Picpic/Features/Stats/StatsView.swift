//
//  StatsView.swift
//  Picpic
//
//  Rétrospective lecture (Pro) : tout est calculé sur l'appareil depuis
//  la bibliothèque SwiftData — façon « Wrapped », sans aucun serveur.
//

import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if books.isEmpty {
                        emptyState
                    } else {
                        statTiles
                        statusChart
                        monthlyChart
                        topAuthors
                        topSubjects
                    }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("Ta rétrospective")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    // MARK: - Agrégats

    private var finishedBooks: [Book] { books.filter { $0.status == .finished } }

    private var pagesRead: Int {
        finishedBooks.compactMap(\.pageCount).reduce(0, +)
    }

    private var averageRating: Double? {
        let ratings = books.compactMap(\.rating)
        guard !ratings.isEmpty else { return nil }
        return Double(ratings.reduce(0, +)) / Double(ratings.count)
    }

    private var authorCounts: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for book in books {
            for author in book.authors where !author.isEmpty {
                counts[author, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(5)
            .map { (name: $0.key, count: $0.value) }
    }

    private var subjectCounts: [String] {
        var counts: [String: Int] = [:]
        for book in books {
            for subject in book.subjects where !subject.isEmpty {
                counts[subject, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(8).map(\.key)
    }

    private struct MonthCount: Identifiable {
        let month: Date
        let count: Int
        var id: Date { month }
    }

    private var monthlyAdditions: [MonthCount] {
        let calendar = Calendar.current
        let now = Date.now
        let months = (0..<12).compactMap { offset in
            calendar.date(byAdding: .month, value: -offset,
                          to: calendar.dateInterval(of: .month, for: now)!.start)
        }.reversed()
        var counts: [Date: Int] = [:]
        for book in books {
            let start = calendar.dateInterval(of: .month, for: book.dateAdded)!.start
            counts[start, default: 0] += 1
        }
        return months.map { MonthCount(month: $0, count: counts[$0] ?? 0) }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 14) {
            MascotView(pose: .idle, height: 64, animated: false)
            VStack(alignment: .leading, spacing: 3) {
                Text("Ton année lecture")
                    .font(.display(22))
                    .foregroundStyle(Theme.ink)
                Text("Calculée sur ton iPhone, rien que pour toi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            MascotView(pose: .reading, height: 110)
            Text("Scanne tes premiers livres")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("Ta rétrospective se construira toute seule au fil de tes lectures.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var statTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                  spacing: 12) {
            statTile(value: "\(books.count)", label: "livres dans ta bibliothèque",
                     symbol: "books.vertical.fill", tint: Theme.accent)
            statTile(value: "\(finishedBooks.count)", label: "terminés",
                     symbol: "checkmark.seal.fill", tint: Theme.teal)
            statTile(value: pagesRead > 0 ? "\(pagesRead)" : "—", label: "pages lues",
                     symbol: "book.pages.fill", tint: Theme.lavender)
            statTile(value: averageRating.map { String(format: "%.1f ★", $0) } ?? "—",
                     label: "note moyenne", symbol: "star.fill", tint: Theme.gold)
        }
    }

    private func statTile(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.display(26))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statusChart: some View {
        card("Où en es-tu ?") {
            Chart(ReadingStatus.allCases) { status in
                BarMark(
                    x: .value("Livres", books.filter { $0.status == status }.count),
                    y: .value("Statut", status.label)
                )
                .foregroundStyle(Theme.accent.gradient)
                .cornerRadius(6)
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: 170)
        }
    }

    private var monthlyChart: some View {
        card("Tes ajouts, mois par mois") {
            Chart(monthlyAdditions) { entry in
                BarMark(
                    x: .value("Mois", entry.month, unit: .month),
                    y: .value("Livres", entry.count)
                )
                .foregroundStyle(Theme.teal.gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 3)) {
                    AxisValueLabel(format: .dateTime.month(.narrow))
                }
            }
            .frame(height: 150)
        }
    }

    @ViewBuilder
    private var topAuthors: some View {
        if !authorCounts.isEmpty {
            card("Tes auteurs du moment") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(authorCounts, id: \.name) { author in
                        HStack {
                            Text(author.name)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer()
                            Text("\(author.count) livre\(author.count > 1 ? "s" : "")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.teal)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var topSubjects: some View {
        if !subjectCounts.isEmpty {
            card("Tes thèmes favoris") {
                WrappingHStack(spacing: 8, lineSpacing: 8) {
                    ForEach(subjectCounts, id: \.self) { subject in
                        Text(subject)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.lavender.opacity(0.12), in: Capsule())
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
        }
    }

    private func card<Content: View>(_ title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
