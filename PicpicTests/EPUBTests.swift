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
        "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"

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

    // MARK: - Découpage pour la lecture à voix haute

    /// Chaque bloc de texte doit être numéroté dans le HTML et présent, dans le
    /// même ordre, dans la liste des paragraphes : c'est cet alignement qui
    /// permet de surligner le paragraphe que l'on entend.
    @Test func paragraphsAreMarkedAndAlignedWithTheHTML() throws {
        let document = try makeDocument()
        let readable = try #require(try document.readable(document.chapters[0]))

        #expect(readable.paragraphs == [
            "Ouverture",
            "Le premier paragraphe du livre.",
            "Un second, avec de l'italique au milieu.",
            "Le dernier.",
        ])
        for index in readable.paragraphs.indices {
            #expect(readable.html.contains("data-pp=\"\(index)\""),
                    "Le bloc \(index) doit être adressable depuis le script de surlignage")
        }
    }

    /// Le texte d'un paragraphe traverse les balises en ligne : couper à
    /// `<i>` donnerait une lecture hachée.
    @Test func inlineMarkupDoesNotSplitAParagraph() throws {
        let document = try makeDocument()
        let readable = try #require(try document.readable(document.chapters[0]))
        #expect(readable.paragraphs[2] == "Un second, avec de l'italique au milieu.")
    }

    /// La liseuse exécute son propre script ; celui de l'EPUB, jamais.
    @Test func epubScriptsAndHandlersAreRemoved() throws {
        let document = try makeDocument()
        let readable = try #require(try document.readable(document.chapters[0]))
        #expect(!readable.html.contains("<script"))
        #expect(!readable.html.contains("window.alert"))
        #expect(!readable.html.contains("onclick"))
        // Le paragraphe qui portait le gestionnaire reste lisible.
        #expect(readable.html.contains("Le dernier."))
    }
}
