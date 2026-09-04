//
//  SudocSearchTests.swift
//  PicpicTests
//
//  Le parseur UNIMARC est la pièce la plus fragile de la recherche Sudoc :
//  ces cas viennent tous de réponses réelles du SRU d'ABES.
//

import Foundation
import Testing
@testable import Picpic

struct SudocQueryTests {

    @Test func scopedToLaRochelleAddsTheLibraryFilter() {
        let query = SudocQuery(terms: "droit du travail")
        #expect(query.cql == #"msu="droit du travail" and rbc="173002101" and lan="fre""#)
    }

    @Test func nationalScopeDropsTheLibraryFilter() {
        let query = SudocQuery(terms: "écologie", scope: .france)
        #expect(query.cql == #"msu="écologie" and lan="fre""#)
    }

    @Test func periodAndIndexAreCarriedIntoTheQuery() {
        let query = SudocQuery(terms: "python", index: .title, scope: .france, sinceYear: 2020)
        #expect(query.cql == #"mti="python" and apu>"2020" and lan="fre""#)
    }

    /// Un guillemet saisi par l'utilisateur casserait la syntaxe CQL : le SRU
    /// d'ABES n'a pas de séquence d'échappement, on neutralise donc en amont.
    @Test func userQuotesCannotBreakOutOfTheTerm() {
        let query = SudocQuery(terms: #"roman" and rbc="000000000"#, scope: .france)
        // Chaque guillemet saisi devient une espace : le terme reste un seul
        // terme, et les quatre guillemets restants sont ceux que l'app pose.
        #expect(query.cql == #"msu="roman  and rbc= 000000000" and lan="fre""#)
        #expect(query.cql.filter { $0 == "\"" }.count == 4)
    }
}

struct SudocUnimarcParserTests {

    /// Extrait réel du SRU (notices raccourcies), avec ses pièges :
    /// caractères de tri autour de l'article, ISBN à tirets, date « DL 2023 »,
    /// auteur en deux sous-champs, et une notice sans ISBN.
    private let fixture = """
    <?xml version="1.0" encoding="UTF-8" ?>
    <srw:searchRetrieveResponse xmlns:srw="http://www.loc.gov/zing/srw/">
      <srw:version>1.1</srw:version>
      <srw:numberOfRecords>1590</srw:numberOfRecords>
      <srw:records>
        <srw:record>
          <srw:recordData>
            <record>
              <controlfield tag="001">262350920</controlfield>
              <datafield tag="010" ind1=" " ind2=" "><subfield code="a">978-2-13-083304-8</subfield><subfield code="d">17 EUR</subfield></datafield>
              <datafield tag="200" ind1="1" ind2=" "><subfield code="a">\u{0098}Les \u{009C}data contre la libert\u{00E9}</subfield><subfield code="f">Patrick Pharo</subfield></datafield>
              <datafield tag="214" ind1=" " ind2=" "><subfield code="a">Paris</subfield><subfield code="c">PUF</subfield><subfield code="d">DL 2022</subfield></datafield>
              <datafield tag="700" ind1=" " ind2="1"><subfield code="a">Pharo</subfield><subfield code="b">Patrick</subfield><subfield code="4">070</subfield></datafield>
              <datafield tag="606" ind1=" " ind2=" "><subfield code="a">Soci\u{00E9}t\u{00E9} num\u{00E9}rique</subfield><subfield code="2">rameau</subfield></datafield>
            </record>
          </srw:recordData>
        </srw:record>
        <srw:record>
          <srw:recordData>
            <record>
              <controlfield tag="001">271929774</controlfield>
              <datafield tag="010" ind1=" " ind2=" "><subfield code="a">978-2-10-084985-7</subfield></datafield>
              <datafield tag="200" ind1="1" ind2=" "><subfield code="a">Que fait l&apos;\u{00E9}cole des donn\u{00E9}es de nos enfants ?</subfield><subfield code="e">30 questions que se posent les parents</subfield><subfield code="f">Gilles Braun, \u{00C9}milie Kerdelhu\u{00E9}</subfield></datafield>
              <datafield tag="214" ind1=" " ind2=" "><subfield code="c">Dunod</subfield><subfield code="d">DL 2023</subfield></datafield>
              <datafield tag="700" ind1=" " ind2="1"><subfield code="a">Braun</subfield><subfield code="b">Gilles</subfield></datafield>
              <datafield tag="701" ind1=" " ind2="1"><subfield code="a">Kerdelhue</subfield><subfield code="b">Emilie</subfield></datafield>
            </record>
          </srw:recordData>
        </srw:record>
        <srw:record>
          <srw:recordData>
            <record>
              <controlfield tag="001">045184011</controlfield>
              <datafield tag="200" ind1="1" ind2=" "><subfield code="a">Trait\u{00E9} de la servitude volontaire</subfield><subfield code="f">\u{00C9}tienne de La Bo\u{00E9}tie</subfield></datafield>
              <datafield tag="210" ind1=" " ind2=" "><subfield code="c">Gallimard</subfield><subfield code="d">cop. 1998</subfield></datafield>
            </record>
          </srw:recordData>
        </srw:record>
      </srw:records>
    </srw:searchRetrieveResponse>
    """

    private func parse() throws -> SudocSearchResult {
        let result = SudocUnimarcParser().parse(Data(fixture.utf8))
        return try #require(result)
    }

    @Test func readsTheTotalCountNotJustThePage() throws {
        let result = try parse()
        #expect(result.totalRecords == 1590)
        #expect(result.records.count == 3)
    }

    /// Le Sudoc encadre l'article initial de caractères de tri invisibles.
    @Test func stripsNonSortingCharactersFromTitles() throws {
        let record = try #require(try parse().records.first)
        #expect(record.title == "Les data contre la liberté")
    }

    @Test func normalizesTheISBNAndReadsTheImprint() throws {
        let record = try #require(try parse().records.first)
        #expect(record.isbn == "9782130833048")
        #expect(record.publisher == "PUF")
        #expect(record.year == "2022")
        #expect(record.imprintLabel == "PUF, 2022")
    }

    @Test func joinsForenameAndSurnameForEveryAuthorField() throws {
        let record = try parse().records[1]
        #expect(record.authors == ["Gilles Braun", "Emilie Kerdelhue"])
        #expect(record.subtitle == "30 questions que se posent les parents")
        #expect(record.title == "Que fait l'école des données de nos enfants ?")
    }

    /// « cop. 1998 », « DL 2023 », « [2021] » : l'année est noyée dans du texte.
    @Test func extractsTheYearFromACatalogersDate() throws {
        let record = try parse().records[2]
        #expect(record.year == "1998")
    }

    /// Sans vedette auteur, la mention de responsabilité prend le relais —
    /// et l'absence d'ISBN doit rester silencieuse, pas produire un ISBN faux.
    @Test func fallsBackToTheStatementOfResponsibility() throws {
        let record = try parse().records[2]
        #expect(record.authors == ["Étienne de La Boétie"])
        #expect(record.isbn == nil)
    }

    @Test func everyRecordKeepsItsOwnPPN() throws {
        let ppns = try parse().records.map(\.ppn)
        #expect(ppns == ["262350920", "271929774", "045184011"])
        #expect(Set(ppns).count == 3)
    }

    /// Une réponse vide (sujet inconnu) n'est pas une erreur.
    @Test func emptyResultSetParsesCleanly() throws {
        let empty = """
        <srw:searchRetrieveResponse xmlns:srw="http://www.loc.gov/zing/srw/">
          <srw:numberOfRecords>0</srw:numberOfRecords>
          <srw:records></srw:records>
        </srw:searchRetrieveResponse>
        """
        let result = try #require(SudocUnimarcParser().parse(Data(empty.utf8)))
        #expect(result.totalRecords == 0)
        #expect(result.records.isEmpty)
    }
}
