//
//  Book.swift
//  Picpic
//

import Foundation
import SwiftData

enum ReadingStatus: String, Codable, CaseIterable, Identifiable {
    case wishlist
    case toRead
    case reading
    case finished

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wishlist: return "Envie"
        case .toRead: return "À lire"
        case .reading: return "En cours"
        case .finished: return "Terminé"
        }
    }

    var symbol: String {
        switch self {
        case .wishlist: return "heart"
        case .toRead: return "books.vertical"
        case .reading: return "book"
        case .finished: return "checkmark.seal"
        }
    }
}

@Model
final class Book {
    @Attribute(.unique) var isbn: String
    var title: String
    var authors: [String]
    var bookDescription: String?
    /// Fourchette d'occasion estimée, en euros (voir BookValueService).
    /// Conservée pour que l'étagère puisse l'afficher sans réinterroger trois
    /// catalogues à chaque affichage — un chineur qui rentre de brocante avec
    /// trente livres ne va pas attendre quatre-vingt-dix appels réseau.
    var estimatedLow: Int?
    var estimatedHigh: Int?
    var valuedAt: Date?
    var subjects: [String]
    var coverURLString: String?
    var publisher: String?
    var publishedDate: String?
    var pageCount: Int?
    var language: String?
    var dateAdded: Date
    var statusRaw: String
    /// Date de passage au statut « terminé ». Nécessaire à l'objectif annuel :
    /// `dateAdded` dit quand le livre est entré dans la bibliothèque, pas quand
    /// il a été lu. Optionnelle, donc migration légère pour les bibliothèques
    /// existantes (les livres déjà terminés restent sans date).
    var dateFinished: Date?
    var rating: Int?
    var notes: String
    /// Embedding vector (Float32 array encoded as Data) for on-device semantic search.
    var embedding: Data?

    var status: ReadingStatus {
        get { ReadingStatus(rawValue: statusRaw) ?? .toRead }
        set {
            statusRaw = newValue.rawValue
            // Repasser un livre en cours annule sa date de fin : sinon il
            // compterait deux fois dans l'objectif annuel une fois reterminé.
            dateFinished = newValue == .finished ? (dateFinished ?? .now) : nil
        }
    }

    var coverURL: URL? {
        coverURLString.flatMap(URL.init(string:))
    }

    var authorsLabel: String {
        authors.isEmpty ? "Auteur inconnu" : authors.joined(separator: ", ")
    }

    /// Text used to compute the semantic embedding.
    var semanticText: String {
        var parts = [title, authors.joined(separator: " ")]
        if let bookDescription { parts.append(bookDescription) }
        if !subjects.isEmpty { parts.append(subjects.joined(separator: " ")) }
        return parts.joined(separator: ". ")
    }

    init(
        isbn: String,
        title: String,
        authors: [String] = [],
        bookDescription: String? = nil,
        subjects: [String] = [],
        coverURLString: String? = nil,
        publisher: String? = nil,
        publishedDate: String? = nil,
        pageCount: Int? = nil,
        language: String? = nil,
        dateAdded: Date = .now,
        status: ReadingStatus = .toRead
    ) {
        self.isbn = isbn
        self.title = title
        self.authors = authors
        self.bookDescription = bookDescription
        self.subjects = subjects
        self.coverURLString = coverURLString
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.pageCount = pageCount
        self.language = language
        self.dateAdded = dateAdded
        self.statusRaw = status.rawValue
        self.dateFinished = status == .finished ? dateAdded : nil
        self.rating = nil
        self.notes = ""
        self.embedding = nil
    }
}
