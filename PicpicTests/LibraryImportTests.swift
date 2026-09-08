//
//  LibraryImportTests.swift
//  PicpicTests
//
//  L'import lit des fichiers écrits par d'autres logiciels, dans des formats
//  qu'on ne contrôle pas. Trois pièges valent chacun un import entièrement
//  vide, sans message d'erreur :
//
//    — Goodreads exporte `="9782070360024"` et non `9782070360024` ;
//    — les exports français sortent en point-virgule et souvent en Latin-1 ;
//    — une critique contenant une virgule décale toutes les colonnes suivantes.
//
//  Ces tests exercent les trois sur des extraits réels de structure.
//

import Foundation
import Testing
@testable import Picpic

struct LibraryImportTests {

    // MARK: - Goodreads

    /// En-têtes et échappements de l'export Goodreads, y compris la colonne
    /// « Average Rating » qui ne doit surtout pas être prise pour la sienne.
    private static let goodreads = """
    Book Id,Title,Author,ISBN,ISBN13,My Rating,Average Rating,Number of Pages,Exclusive Shelf,My Review
    123,L'Étranger,Albert Camus,="2070360024",="9782070360024",4,3.98,186,read,"Court, sec, parfait."
    456,Dune,Frank Herbert,="",="9780441013593",0,4.25,896,currently-reading,
    789,Le Horla,Guy de Maupassant,="",="",5,4.10,96,to-read,
    """

    @Test func goodreadsExportIsUnderstood() throws {
        let preview = try LibraryImportService.preview(csv: Self.goodreads)

        #expect(preview.totalRows == 3)
        try #require(preview.books.count == 2)
        // Le Horla n'a ni ISBN ni ISBN13 : compté comme rejet, pas perdu en silence.
        #expect(preview.skippedNoISBN == 1)

        let camus = try #require(preview.books.first)
        #expect(camus.title == "L'Étranger")
        #expect(camus.authors == ["Albert Camus"])
        // ISBN13 est préféré à ISBN, et la formule `="..."` est retirée.
        #expect(camus.isbn == "9782070360024")
        #expect(camus.status == .finished)
        #expect(camus.pageCount == 186)
        // 4 et non 3.98 : « My Rating » l'emporte sur « Average Rating ».
        #expect(camus.rating == 4)
        // La virgule dans la critique ne doit pas avoir décalé les colonnes.
        #expect(camus.notes == "Court, sec, parfait.")

        let dune = preview.books[1]
        #expect(dune.status == .reading)
        // 0 chez Goodreads veut dire « pas noté ».
        #expect(dune.rating == nil)
    }

    // MARK: - Exports français

    @Test func semicolonAndFrenchHeadersAreUnderstood() throws {
        let csv = """
        Titre;Auteur;ISBN;Ma note;Nombre de pages;État de lecture
        Bel-Ami;Maupassant, Guy de;978-2-07-040900-0;3;438;Lu
        La Peste;Camus, Albert;9782070360420;;279;À lire
        """
        let preview = try LibraryImportService.preview(csv: csv)

        try #require(preview.books.count == 2)
        // Les tirets de l'ISBN sont retirés.
        #expect(preview.books[0].isbn == "9782070409000")
        // « Maupassant, Guy de » est UN auteur : couper sur la virgule en
        // inventerait deux.
        #expect(preview.books[0].authors == ["Maupassant, Guy de"])
        #expect(preview.books[0].status == .finished)
        #expect(preview.books[1].status == .toRead)
        #expect(preview.books[1].rating == nil)
    }

    /// « to-read » contient « read » : testé après, toute la pile à lire
    /// basculerait dans les livres terminés.
    @Test func statusOrderingDoesNotConfuseToReadWithRead() {
        #expect(LibraryImportService.status(from: "to-read") == .toRead)
        #expect(LibraryImportService.status(from: "read") == .finished)
        #expect(LibraryImportService.status(from: "currently-reading") == .reading)
        #expect(LibraryImportService.status(from: "À lire") == .toRead)
        #expect(LibraryImportService.status(from: "Lu") == .finished)
        #expect(LibraryImportService.status(from: "Envies") == .wishlist)
        #expect(LibraryImportService.status(from: "") == .toRead)
    }

    // MARK: - Robustesse du lecteur

    @Test func quotedFieldsSurviveSeparatorsAndNewlines() throws {
        let rows = CSVReader.rows(
            from: "a,\"b,c\",\"d\"\"e\"\r\n\"multi\nligne\",f,g\n", separator: ",")
        try #require(rows.count == 2)
        #expect(rows[0] == ["a", "b,c", "d\"e"])
        #expect(rows[1] == ["multi\nligne", "f", "g"])
    }

    /// Non-régression. Swift compte en grappes de graphèmes, et CR LF en est
    /// UNE : `Character("\r\n")` n'est égal ni à "\r" ni à "\n". Le lecteur
    /// tombait donc dans son cas par défaut et recopiait la fin de ligne dans
    /// le champ — tout export Goodreads, qui sort en fins de ligne Windows, se
    /// lisait comme une seule ligne et donnait « 1 livre » sur deux cents.
    @Test func windowsLineEndingsAreNotSwallowedIntoTheField() throws {
        let csv = "Title,ISBN13,My Rating,Exclusive Shelf\r\n"
                + "Dune,=\"9780441013593\",4,read\r\n"
                + "Bel-Ami,=\"9782070409000\",0,to-read\r\n"
        let preview = try LibraryImportService.preview(csv: csv)
        try #require(preview.books.count == 2)
        #expect(preview.totalRows == 2)
        #expect(preview.books[0].title == "Dune")
        #expect(preview.books[0].status == .finished)
        #expect(preview.books[1].title == "Bel-Ami")
        #expect(preview.books[1].status == .toRead)
    }

    @Test func byteOrderMarkAndTrailingBlankLinesAreIgnored() throws {
        let preview = try LibraryImportService.preview(
            csv: "\u{FEFF}Title,ISBN\nDune,9780441013593\n\n\n")
        #expect(preview.totalRows == 1)
        #expect(preview.books.count == 1)
        #expect(preview.books[0].title == "Dune")
    }

    @Test func duplicatesWithinTheFileAreCountedOnce() throws {
        let preview = try LibraryImportService.preview(
            csv: "Title,ISBN\nDune,9780441013593\nDune (poche),978-0-441-01359-3\n")
        #expect(preview.books.count == 1)
        #expect(preview.duplicatesInFile == 1)
    }

    @Test func latin1FileIsDecoded() throws {
        let data = try #require("Titre,ISBN\nL'Étranger,9782070360024\n"
            .data(using: .isoLatin1))
        let preview = try LibraryImportService.preview(
            csv: try LibraryImportService.text(from: data))
        #expect(preview.books.first?.title == "L'Étranger")
    }

    @Test func fileWithoutRecognizableColumnsIsRefused() {
        #expect(throws: ImportError.self) {
            try LibraryImportService.preview(csv: "colonne1,colonne2\na,b\n")
        }
    }
}
