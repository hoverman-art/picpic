//
//  SudocSearchViewModel.swift
//  Picpic
//

import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class SudocSearchViewModel {

    // Requête courante
    var terms = ""
    var index: SudocIndex = .subject
    var scope: SudocScope = .laRochelle
    var period: Period = .any

    // Résultats
    private(set) var records: [SudocRecord] = []
    private(set) var totalRecords = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    /// Vrai tant que l'écran n'a pas encore lancé sa première recherche.
    private(set) var hasSearched = false

    /// PPN déjà ajoutés pendant la session, pour l'état du bouton.
    private(set) var addedPPNs: Set<String> = []
    var addingPPN: String?

    private let pageSize = 20
    /// Identifie la recherche en cours : une réponse plus lente qu'un
    /// changement de filtre ne doit pas écraser des résultats plus récents.
    private var currentSearchID = UUID()

    enum Period: String, CaseIterable, Identifiable {
        case any, fiveYears, tenYears

        var id: String { rawValue }

        var label: String {
            switch self {
            case .any: return "Toutes années"
            case .fiveYears: return "5 dernières années"
            case .tenYears: return "10 dernières années"
            }
        }

        var sinceYear: Int? {
            let year = Calendar.current.component(.year, from: .now)
            switch self {
            case .any: return nil
            case .fiveYears: return year - 5
            case .tenYears: return year - 10
            }
        }
    }

    var query: SudocQuery {
        SudocQuery(terms: terms, index: index, scope: scope, sinceYear: period.sinceYear)
    }

    var canLoadMore: Bool {
        !records.isEmpty && records.count < totalRecords
    }

    /// « 1 240 livres à la BU » — la promesse que l'écran tient.
    var resultSummary: String {
        let formatted = totalRecords.formatted(.number.grouping(.automatic))
        let noun = totalRecords > 1 ? "notices" : "notice"
        return "\(formatted) \(noun) · \(scope.label)"
    }

    // MARK: - Recherche

    func search(subject: String? = nil) async {
        if let subject { terms = subject }
        guard !terms.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let searchID = UUID()
        currentSearchID = searchID
        hasSearched = true
        isLoading = true
        errorMessage = nil
        records = []
        totalRecords = 0
        defer { if currentSearchID == searchID { isLoading = false } }

        do {
            let result = try await SudocSearchService.shared.search(query, pageSize: pageSize)
            guard currentSearchID == searchID else { return }
            records = result.records
            totalRecords = result.totalRecords
        } catch {
            guard currentSearchID == searchID else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Recherche impossible."
        }
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore, !isLoading else { return }
        let searchID = currentSearchID
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await SudocSearchService.shared.search(
                query, startRecord: records.count + 1, pageSize: pageSize
            )
            guard currentSearchID == searchID else { return }
            // Le Sudoc peut renvoyer deux fois la même notice entre deux pages.
            let known = Set(records.map(\.ppn))
            records += result.records.filter { !known.contains($0.ppn) }
        } catch {
            guard currentSearchID == searchID else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Chargement impossible."
        }
    }

    /// Relance la recherche courante après un changement de filtre.
    func refilter() async {
        guard hasSearched else { return }
        await search()
    }

    // MARK: - Ajout à la bibliothèque

    func isInLibrary(_ record: SudocRecord, existing: [Book]) -> Bool {
        if addedPPNs.contains(record.ppn) { return true }
        guard let isbn = record.isbn else { return false }
        return existing.contains { $0.isbn == isbn }
    }

    /// Ajoute la notice à la bibliothèque. Les métadonnées enrichies (résumé,
    /// couverture) sont tentées d'abord ; à défaut, la notice Sudoc suffit —
    /// mieux vaut un livre sans couverture qu'un ajout qui échoue.
    func add(_ record: SudocRecord, context: ModelContext) async {
        guard let isbn = record.isbn, addingPPN == nil else { return }
        addingPPN = record.ppn
        defer { addingPPN = nil }

        let existing = try? context.fetch(FetchDescriptor<Book>(
            predicate: #Predicate { $0.isbn == isbn }
        ))
        if existing?.isEmpty == false {
            addedPPNs.insert(record.ppn)
            return
        }

        let book: Book
        if let metadata = try? await BookMetadataService().fetch(isbn: isbn) {
            book = Book(
                isbn: metadata.isbn,
                title: metadata.title,
                authors: metadata.authors,
                bookDescription: metadata.description,
                subjects: metadata.subjects.isEmpty ? record.subjects : metadata.subjects,
                coverURLString: metadata.coverURLString,
                publisher: metadata.publisher,
                publishedDate: metadata.publishedDate,
                pageCount: metadata.pageCount,
                language: metadata.language
            )
        } else {
            book = Book(
                isbn: isbn,
                title: record.title,
                authors: record.authors,
                bookDescription: nil,
                subjects: record.subjects,
                coverURLString: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg",
                publisher: record.publisher,
                publishedDate: record.year,
                pageCount: nil,
                language: "fr"
            )
        }
        book.embedding = SemanticSearchService.shared.vector(for: book.semanticText)
        context.insert(book)
        try? context.save()
        addedPPNs.insert(record.ppn)
    }
}
