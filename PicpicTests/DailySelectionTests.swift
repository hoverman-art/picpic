//
//  DailySelectionTests.swift
//  PicpicTests
//
//  La sélection audio de l'accueil doit tenir deux promesses contradictoires :
//  changer tous les jours, et ne pas bouger dans la journée. Un tirage au sort
//  ordinaire échoue à la seconde — la liste changerait à chaque retour sur
//  l'accueil, et le lecteur ne retrouverait pas ce qu'il a vu le matin.
//
//  On vérifie aussi la fusion des catalogues : deux sources qui décrivent le
//  même livre ne doivent pas produire deux lignes.
//

import Foundation
import Testing
@testable import Picpic

struct DailySelectionTests {

    private func catalogue(_ count: Int) -> [DailyAudiobook] {
        (0..<count).map {
            DailyAudiobook(id: "id\($0)", title: "Titre \($0)", author: "Auteur \($0)")
        }
    }

    /// Le même jour, la même sélection — quelle que soit l'heure.
    @Test func selectionIsStableWithinTheDay() {
        let books = catalogue(60)
        let morning = DailyAudiobooksService.pick(6, from: books, day: 20_340)
        let evening = DailyAudiobooksService.pick(6, from: books, day: 20_340)
        #expect(morning == evening)
        #expect(morning.count == 6)
    }

    /// D'un jour à l'autre, elle tourne : c'est tout l'intérêt.
    @Test func selectionChangesFromDayToDay() {
        let books = catalogue(60)
        let today = DailyAudiobooksService.pick(6, from: books, day: 20_340)
        let tomorrow = DailyAudiobooksService.pick(6, from: books, day: 20_341)
        #expect(today != tomorrow)
    }

    /// Six livres demandés, six livres différents.
    @Test func selectionHasNoDuplicates() {
        let picked = DailyAudiobooksService.pick(6, from: catalogue(60), day: 20_355)
        #expect(Set(picked.map(\.id)).count == picked.count)
    }

    /// Un catalogue plus court que la sélection ne doit ni planter ni répéter.
    @Test func shortCatalogueIsHandled() {
        let picked = DailyAudiobooksService.pick(6, from: catalogue(2), day: 20_355)
        #expect(picked.count == 2)
        #expect(DailyAudiobooksService.pick(6, from: [], day: 20_355).isEmpty)
    }

    /// Archive.org donne les durées tantôt en secondes, tantôt déjà écrites.
    @Test func lengthsAreReadable() {
        #expect(DailyAudiobooksService.readableLength("1109.01") == "18:29")
        #expect(DailyAudiobooksService.readableLength("18:28") == "18:28")
    }

    // MARK: - Fusion des catalogues

    /// Google Books et Open Library décrivent le même roman : une seule ligne.
    @Test func mergeDropsTheSameBookTwice() {
        let google = [CatalogResult(isbn: "9782070413119", title: "Madame Bovary",
                                    authors: ["Gustave Flaubert"], coverURLString: nil, year: "1857")]
        let openLibrary = [CatalogResult(isbn: nil, title: "MADAME BOVARY",
                                         authors: ["Gustave FLAUBERT"], coverURLString: nil, year: "1856"),
                           CatalogResult(isbn: "9782070360420", title: "La Peste",
                                         authors: ["Albert Camus"], coverURLString: nil, year: "1947")]
        let merged = CatalogSearchService.merge(google, openLibrary, limit: 8)
        #expect(merged.count == 2)
        #expect(merged.first?.isbn == "9782070413119")
    }

    /// La limite est respectée : la section de l'accueil n'est pas une liste.
    @Test func mergeRespectsTheLimit() {
        let many = (0..<20).map {
            CatalogResult(isbn: "isbn\($0)", title: "Titre \($0)", authors: ["Auteur"],
                          coverURLString: nil, year: nil)
        }
        #expect(CatalogSearchService.merge(many, [], limit: 8).count == 8)
    }
}
