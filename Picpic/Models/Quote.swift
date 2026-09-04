//
//  Quote.swift
//  Picpic
//
//  Une citation relevée par l'utilisateur dans un livre qu'il lit.
//  Le texte est saisi ou reconnu depuis SA photo, sur SON appareil, et ne
//  quitte jamais l'iPhone.
//

import Foundation
import SwiftData

@Model
final class Quote {
    var text: String
    /// ISBN du livre d'origine, quand la citation part d'une fiche.
    var bookISBN: String?
    var bookTitle: String?
    var bookAuthors: [String]
    var page: Int?
    var dateAdded: Date

    var attribution: String {
        let author = bookAuthors.first
        switch (bookTitle, author) {
        case let (title?, author?): return "\(title) — \(author)"
        case let (title?, nil): return title
        case let (nil, author?): return author
        default: return ""
        }
    }

    init(
        text: String,
        bookISBN: String? = nil,
        bookTitle: String? = nil,
        bookAuthors: [String] = [],
        page: Int? = nil,
        dateAdded: Date = .now
    ) {
        self.text = text
        self.bookISBN = bookISBN
        self.bookTitle = bookTitle
        self.bookAuthors = bookAuthors
        self.page = page
        self.dateAdded = dateAdded
    }
}
