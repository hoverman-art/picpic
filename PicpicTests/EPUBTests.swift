//
//  EPUBTests.swift
//  PicpicTests
//
//  La liseuse repose sur deux morceaux de code binaire écrits à la main : la
//  lecture du ZIP et l'analyse de l'EPUB. Ces tests les exercent sur une vraie
//  archive miniature (générée avec `zipfile`, entrées stockées ET compressées),
//  parce qu'une régression s'y traduirait par une page blanche silencieuse.
//

import Foundation
import Testing
@testable import Picpic

struct EPUBTests {

    /// EPUB complet de 1,5 Kio : mimetype stocké, XML compressé en DEFLATE,
    /// une image PNG stockée, deux chapitres et un manifeste avec des fichiers
    /// hors spine (CSS, couverture).
    private static let fixtureBase64 =
        "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" +
        "dQQAAAAA"

    private func makeDocument() throws -> EPUBDocument {
        let data = try #require(Data(base64Encoded: Self.fixtureBase64))
        return try EPUBDocument(data: data)
    }

    // MARK: - ZIP

    @Test func readsBothStoredAndDeflatedEntries() throws {
        let data = try #require(Data(base64Encoded: Self.fixtureBase64))
        let archive = try ZIPArchive(data: data)

        // « mimetype » est stocké tel quel, le XML est compressé.
        #expect(try archive.string(for: "mimetype") == "application/epub+zip")
        let container = try #require(try archive.string(for: "META-INF/container.xml"))
        #expect(container.contains("OEBPS/book.opf"))
    }

    @Test func missingEntryIsNilNotAFailure() throws {
        let data = try #require(Data(base64Encoded: Self.fixtureBase64))
        let archive = try ZIPArchive(data: data)
        #expect(try archive.data(for: "OEBPS/absent.xhtml") == nil)
    }

    @Test func rejectsSomethingThatIsNotAZip() {
        #expect(throws: ZIPArchive.Failure.self) {
            _ = try ZIPArchive(data: Data("pas une archive".utf8))
        }
    }

    // MARK: - EPUB

    @Test func readsTitleAndAuthorFromThePackage() throws {
        let document = try makeDocument()
        #expect(document.title == "Le Petit Livre")
        #expect(document.author == "Anonyme")
    }

    /// Le manifeste contient aussi le CSS et la couverture : seuls les
    /// documents du spine sont des chapitres, et dans son ordre.
    @Test func chaptersComeFromTheSpineOnly() throws {
        let document = try makeDocument()
        #expect(document.chapters.count == 2)
        #expect(document.chapters.map(\.path) == ["OEBPS/text/un.xhtml", "OEBPS/text/deux.xhtml"])
    }

    @Test func chapterTitlesComeFromTheDocumentNotTheIndex() throws {
        let document = try makeDocument()
        #expect(document.chapters[0].title == "Ouverture")     // <h1>
        #expect(document.chapters[1].title == "Chapitre deux") // <title>, faute de <h1>
    }

    /// Le <head> du chapitre porte des styles qui écraseraient ceux de la
    /// liseuse : seul l'intérieur de <body> doit ressortir.
    @Test func onlyTheBodyIsKept() throws {
        let document = try makeDocument()
        let html = try #require(try document.html(for: document.chapters[0]))
        #expect(html.contains("Le premier paragraphe du livre."))
        #expect(!html.contains("color:red"))
        #expect(!html.contains("<head"))
    }

    /// Sans URL de base, une image relative ne se charge pas : elle doit être
    /// remplacée par son contenu, sinon la couverture est une page blanche.
    @Test func relativeImagesAreInlined() throws {
        let document = try makeDocument()
        let html = try #require(try document.html(for: document.chapters[0]))
        #expect(html.contains("src=\"data:image/png;base64,"))
        #expect(!html.contains("../images/cover.png"))
    }

    @Test func excerptStripsMarkupAndEntities() throws {
        let document = try makeDocument()
        let excerpt = try #require(document.excerpt(for: document.chapters[1]))
        #expect(excerpt == "Suite & fin.")
    }
}
