//
//  LibraryViewModel.swift
//  Picpic
//

import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class LibraryViewModel {
    var isFetching = false
    var fetchError: String?
    var lastScannedBook: Book?
    var showSuggestionModal = false
    var showRateModal = false

    private let metadataService = BookMetadataService()

    /// Full scan pipeline: metadata fetch → embedding → insert → smart modals.
    func addBook(isbn: String, context: ModelContext, settings: UserSettings) async {
        isFetching = true
        fetchError = nil
        defer { isFetching = false }

        // Already scanned? Just surface it.
        let existing = try? context.fetch(FetchDescriptor<Book>(
            predicate: #Predicate { $0.isbn == isbn }
        ))
        if let book = existing?.first {
            lastScannedBook = book
            return
        }

        do {
            let metadata = try await metadataService.fetch(isbn: isbn)
            let book = Book(
                isbn: metadata.isbn,
                title: metadata.title,
                authors: metadata.authors,
                bookDescription: metadata.description,
                subjects: metadata.subjects,
                coverURLString: metadata.coverURLString,
                publisher: metadata.publisher,
                publishedDate: metadata.publishedDate,
                pageCount: metadata.pageCount,
                language: metadata.language
            )
            book.embedding = SemanticSearchService.shared.vector(for: book.semanticText)
            context.insert(book)
            try? context.save()

            lastScannedBook = book
            settings.scanCount += 1
            triggerSmartModals(settings: settings)
        } catch {
            fetchError = (error as? LocalizedError)?.errorDescription ?? "Une erreur est survenue."
        }
    }

    /// Smart modal logic: suggestion modal on milestones, rate prompt once
    /// the user has demonstrated real engagement (5+ scans), max 1×/90 days.
    private func triggerSmartModals(settings: UserSettings) {
        if settings.scanCount == 3 {
            showSuggestionModal = true
            return
        }
        guard !settings.didRateApp, settings.scanCount >= 5 else { return }
        let ninetyDays: TimeInterval = 90 * 24 * 3600
        let lastAsk = settings.lastReviewRequestDate ?? .distantPast
        if Date.now.timeIntervalSince(lastAsk) > ninetyDays {
            settings.lastReviewRequestDate = .now
            showRateModal = true
        }
    }
}
