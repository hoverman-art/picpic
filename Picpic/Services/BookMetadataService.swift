//
//  BookMetadataService.swift
//  Picpic
//
//  Fetches book metadata by ISBN from free open-data sources,
//  directly from the device — no backend involved.
//  Order: Open Library (open data, CC0) → Google Books (fallback).
//

import Foundation

struct BookMetadata {
    var isbn: String
    var title: String
    var authors: [String]
    var description: String?
    var subjects: [String]
    var coverURLString: String?
    var publisher: String?
    var publishedDate: String?
    var pageCount: Int?
    var language: String?
}

enum BookMetadataError: LocalizedError {
    case notFound
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notFound: return "Livre introuvable dans les catalogues ouverts."
        case .network: return "Connexion impossible. Vérifie ton réseau."
        }
    }
}

struct BookMetadataService {
    private let session: URLSession = .shared

    // Cascade: Google Books first (best French coverage + descriptions),
    // then Open Library. Both are keyless and HTTPS.
    func fetch(isbn rawISBN: String) async throws -> BookMetadata {
        let isbn = rawISBN.filter(\.isNumber)
        if let google = try? await fetchFromGoogleBooks(isbn: isbn) {
            return google
        }
        if let openLibrary = try? await fetchFromOpenLibrary(isbn: isbn) {
            return openLibrary
        }
        throw BookMetadataError.notFound
    }

    // MARK: - Open Library

    private struct OLResponse: Decodable {
        struct Author: Decodable { let key: String? }
        struct Work: Decodable { let key: String }
        let title: String?
        let by_statement: String?
        let number_of_pages: Int?
        let publish_date: String?
        let publishers: [String]?
        let subjects: [String]?
        let covers: [Int]?
        let works: [Work]?
        let authors: [Author]?
        let description: OLText?
    }

    /// Open Library "description" is either a string or {type, value}.
    private enum OLText: Decodable {
        case text(String)

        var value: String {
            switch self { case .text(let s): return s }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                self = .text(s)
                return
            }
            struct Typed: Decodable { let value: String }
            let typed = try container.decode(Typed.self)
            self = .text(typed.value)
        }
    }

    private struct OLWork: Decodable {
        let description: OLText?
        let subjects: [String]?
    }

    private struct OLAuthor: Decodable { let name: String? }

    private func fetchFromOpenLibrary(isbn: String) async throws -> BookMetadata {
        let url = URL(string: "https://openlibrary.org/isbn/\(isbn).json")!
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BookMetadataError.notFound
        }
        let edition = try JSONDecoder().decode(OLResponse.self, from: data)
        guard let title = edition.title else { throw BookMetadataError.notFound }

        var description = edition.description?.value
        var subjects = edition.subjects ?? []

        // The work record usually carries the description and subjects.
        if description == nil || subjects.isEmpty, let workKey = edition.works?.first?.key {
            if let workURL = URL(string: "https://openlibrary.org\(workKey).json"),
               let (workData, _) = try? await session.data(from: workURL),
               let work = try? JSONDecoder().decode(OLWork.self, from: workData) {
                description = description ?? work.description?.value
                if subjects.isEmpty { subjects = work.subjects ?? [] }
            }
        }

        var authorNames: [String] = []
        for author in edition.authors ?? [] {
            guard let key = author.key,
                  let authorURL = URL(string: "https://openlibrary.org\(key).json"),
                  let (authorData, _) = try? await session.data(from: authorURL),
                  let decoded = try? JSONDecoder().decode(OLAuthor.self, from: authorData),
                  let name = decoded.name else { continue }
            authorNames.append(name)
        }
        if authorNames.isEmpty, let by = edition.by_statement {
            authorNames = [by]
        }

        return BookMetadata(
            isbn: isbn,
            title: title,
            authors: authorNames,
            description: description,
            subjects: Array(subjects.prefix(8)),
            coverURLString: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg",
            publisher: edition.publishers?.first,
            publishedDate: edition.publish_date,
            pageCount: edition.number_of_pages,
            language: nil
        )
    }

    // MARK: - Google Books (no API key needed for volume search by ISBN)

    private struct GBResponse: Decodable {
        struct Item: Decodable {
            struct VolumeInfo: Decodable {
                struct ImageLinks: Decodable { let thumbnail: String? }
                let title: String?
                let authors: [String]?
                let description: String?
                let categories: [String]?
                let publisher: String?
                let publishedDate: String?
                let pageCount: Int?
                let language: String?
                let imageLinks: ImageLinks?
            }
            let volumeInfo: VolumeInfo
        }
        let items: [Item]?
    }

    private func fetchFromGoogleBooks(isbn: String) async throws -> BookMetadata {
        let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=isbn:\(isbn)&country=FR")!
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw BookMetadataError.notFound
        }
        let decoded = try JSONDecoder().decode(GBResponse.self, from: data)
        guard let info = decoded.items?.first?.volumeInfo, let title = info.title else {
            throw BookMetadataError.notFound
        }
        return BookMetadata(
            isbn: isbn,
            title: title,
            authors: info.authors ?? [],
            description: info.description,
            subjects: info.categories ?? [],
            coverURLString: info.imageLinks?.thumbnail?
                .replacingOccurrences(of: "http://", with: "https://"),
            publisher: info.publisher,
            publishedDate: info.publishedDate,
            pageCount: info.pageCount,
            language: info.language
        )
    }
}
