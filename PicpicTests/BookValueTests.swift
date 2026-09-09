//
//  BookValueTests.swift
//  PicpicTests
//
//  L'estimation montrée aux chineurs repose sur trois briques dont chacune
//  peut se tromper en silence :
//
//    — la conversion ISBN-13 → ISBN-10, sans laquelle la BnF ne trouve rien ;
//    — la lecture d'une notice Dublin Core (collection, pagination, format) ;
//    — la règle de calcul elle-même, affichée à l'écran.
//
//  Ces tests fixent les trois sur des données réelles, relevées le
//  9 septembre 2026.
//

import Foundation
import Testing
@testable import Picpic

struct BookValueTests {

    // MARK: - ISBN

    /// La BnF n'indexe que l'ISBN-10 : sans conversion, zéro notice.
    @Test func isbn13BecomesIsbn10() {
        // « L'Étranger », Folio : 9782070360024 → 2070360024, vérifié sur le
        // catalogue général de la BnF.
        #expect(BnFService.isbn10(from: "9782070360024") == "2070360024")
        #expect(BnFService.isbn10(from: "978-2-07-036002-4") == "2070360024")
    }

    /// Un ISBN-10 est rendu tel quel, un ISBN-13 en 979 n'a pas d'équivalent.
    @Test func isbn10PassesThroughAndNine79HasNoEquivalent() {
        #expect(BnFService.isbn10(from: "2070360024") == "2070360024")
        #expect(BnFService.isbn10(from: "9791234567896") == nil)
        #expect(BnFService.isbn10(from: "123") == nil)
    }

    /// La clé de contrôle vaut parfois X.
    @Test func checkDigitCanBeX() {
        // 9780306406157 → 0306406152 (exemple canonique de la norme).
        #expect(BnFService.isbn10(from: "9780306406157") == "0306406152")
    }

    // MARK: - Notice BnF

    private static let record = """
    <?xml version="1.0" encoding="UTF-8"?>
    <srw:searchRetrieveResponse xmlns:srw="http://www.loc.gov/zing/srw/">
    <srw:records><srw:record><srw:recordData>
    <dc:title>L'Étranger / Albert Camus</dc:title>
    <dc:creator>Camus, Albert (1913-1960). Auteur du texte / Autrice du texte</dc:creator>
    <dc:publisher>Gallimard (Paris)</dc:publisher>
    <dc:date>1971</dc:date>
    <dc:description>Collection : Folio ; 2</dc:description>
    <dc:format>1 volume 191 p ; 18 cm</dc:format>
    <dc:language>fre</dc:language>
    </srw:recordData></srw:record></srw:records>
    </srw:searchRetrieveResponse>
    """

    @Test func bnfRecordIsRead() throws {
        let edition = try #require(BnFService.parse(Self.record))
        #expect(edition.title == "L'Étranger")
        // « Camus, Albert (1913-1960). Auteur du texte » se lit « Albert Camus ».
        #expect(edition.authors == ["Albert Camus"])
        #expect(edition.publisher == "Gallimard")
        #expect(edition.year == "1971")
        #expect(edition.collection == "Folio")
        #expect(edition.pageCount == 191)
        #expect(edition.heightCm == 18)
    }

    @Test func formatIsReadFromThePhysicalDescription() {
        #expect(BnFService.pages(in: "1 volume 191 p ; 18 cm") == 191)
        #expect(BnFService.height(in: "1 volume 191 p ; 18 cm") == 18)
        #expect(BnFService.height(in: "1 volume non paginé") == nil)
    }

    // MARK: - Le format décide de la base

    @Test func heightDecidesTheFormat() {
        func edition(height: Int?, collection: String? = nil) -> BnFEdition {
            BnFEdition(title: "T", authors: [], publisher: nil, year: nil,
                       collection: collection, pageCount: nil, heightCm: height)
        }
        #expect(BookValueService.format(of: edition(height: 18)) == .pocket)
        #expect(BookValueService.format(of: edition(height: 22)) == .paperback)
        #expect(BookValueService.format(of: edition(height: 30)) == .large)
        // Sans hauteur, la collection tranche.
        #expect(BookValueService.format(of: edition(height: nil, collection: "Le Livre de poche")) == .pocket)
        #expect(BookValueService.format(of: edition(height: nil, collection: "Blanche")) == .unknown)
    }

    // MARK: - La règle

    private func folio(year: String?) -> BnFEdition {
        BnFEdition(title: "L'Étranger", authors: ["Albert Camus"], publisher: "Gallimard",
                   year: year, collection: "Folio", pageCount: 191, heightCm: 18)
    }

    /// Le cas mesuré : Folio de 1971, 67 bibliothèques, 468 éditions.
    /// Un livre qu'on trouve partout ne vaut pas cher, et l'estimation doit le
    /// dire — c'est le premier service qu'on rend à un chineur.
    @Test func aCommonPocketStaysCheap() {
        let value = BookValueService.estimate(edition: folio(year: "1971"),
                                              libraries: 67, editions: 468)
        #expect(value.format == .pocket)
        #expect(value.low <= 3)
        #expect(value.high <= 8)
        #expect(value.reasons.count >= 3)
    }

    /// Vieux, rare, peu réédité : la fourchette doit monter franchement.
    @Test func anOldAndRareBookIsWorthMore() {
        let old = BnFEdition(title: "Traité", authors: [], publisher: "Didot", year: "1878",
                             collection: nil, pageCount: 320, heightCm: 24)
        let value = BookValueService.estimate(edition: old, libraries: 2, editions: 3)
        #expect(value.low >= 40)
        #expect(value.high > value.low)
        #expect(value.reasons.contains { $0.contains("1878") })
        #expect(value.reasons.contains { $0.contains("rare") })
    }

    /// Sans notice ni signal, on ne prétend pas savoir : fourchette large et
    /// format inconnu, mais jamais de valeur nulle.
    @Test func unknownEditionStillGivesARange() {
        let value = BookValueService.estimate(edition: nil, libraries: nil, editions: nil)
        #expect(value.format == .unknown)
        #expect(value.low >= 1)
        #expect(value.high > value.low)
    }

    /// La fourchette est toujours croissante et jamais gratuite.
    @Test func rangeIsAlwaysOrdered() {
        for year in ["1850", "1935", "1975", "2020"] {
            for libraries in [1, 8, 40, 120] {
                let value = BookValueService.estimate(edition: folio(year: year),
                                                      libraries: libraries, editions: 12)
                #expect(value.low >= 1)
                #expect(value.high > value.low)
            }
        }
    }

    // MARK: - Liens marchands

    /// Trois liens de recherche ordinaires, avec l'ISBN dedans.
    @Test func marketLinksCarryTheISBN() {
        let links = BookValueService.marketLinks(isbn: "9782070360024")
        #expect(links.count == 3)
        #expect(links.allSatisfy { $0.url.absoluteString.contains("9782070360024") })
    }

    // MARK: - Rareté, lue dans les réponses du Sudoc

    @Test func sudocAnswersAreRead() {
        let isbn2ppn = """
        <sudoc service="isbn2ppn"><query><isbn>9782070360024</isbn>
        <result><ppn>001896431</ppn><ppn>172254191</ppn></result></query></sudoc>
        """
        #expect(SudocSearchService.firstTag("ppn", in: isbn2ppn) == "001896431")

        let multiwhere = """
        <sudoc><query><result><library><shortname>NICE-BU</shortname></library>
        <library><shortname>AIX-IUT</shortname></library>
        <library><shortname>LA ROCHELLE-BU</shortname></library></result></query></sudoc>
        """
        #expect(SudocSearchService.countTag("shortname", in: multiwhere) == 3)
        #expect(SudocSearchService.countTag("shortname", in: "<vide/>") == 0)
    }

    // MARK: - Résumé de secours

    /// L'article doit parler du livre, sinon pas de résumé du tout.
    @Test func wikipediaPageMustMatchTheBook() {
        #expect(WikipediaSummaryService.plausible(page: "L'Étranger", title: "L'Étranger"))
        #expect(WikipediaSummaryService.plausible(page: "Madame Bovary (film, 1991)", title: "Madame Bovary"))
        #expect(!WikipediaSummaryService.plausible(page: "Albert Camus", title: "L'Étranger"))
    }

    // MARK: - Fusion des catalogues

    /// La source la mieux classée reste la référence ; les autres ne font que
    /// boucher ses trous. C'est ce qui rend un résumé à un scan le jour où
    /// Google Books est en quota.
    @Test func mergeOnlyFillsWhatIsMissing() {
        let base = BookMetadata(isbn: "1", title: "Titre", authors: ["Auteur"],
                                description: nil, subjects: [], coverURLString: nil,
                                publisher: nil, publishedDate: nil, pageCount: nil, language: nil)
        let other = BookMetadata(isbn: "1", title: "Autre titre", authors: ["Autre"],
                                 description: "Un résumé", subjects: ["Roman"],
                                 coverURLString: "https://exemple/couv.jpg",
                                 publisher: "Gallimard", publishedDate: "1971",
                                 pageCount: 191, language: "fr")
        let merged = BookMetadataService.filling(base, with: other)
        #expect(merged.title == "Titre")
        #expect(merged.authors == ["Auteur"])
        #expect(merged.description == "Un résumé")
        #expect(merged.publisher == "Gallimard")
        #expect(merged.pageCount == 191)
    }
}
