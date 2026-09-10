//
//  SearchRankingTests.swift
//  PicpicTests
//
//  La barre de recherche de l'accueil est vendue sur la fiche App Store avec
//  l'exemple « un roman sur la mer ». Elle ne reposait que sur les embeddings
//  d'Apple, et c'est précisément cet exemple qu'elle ratait :
//
//      « un roman sur la mer »      L'Étranger 0,718 · Vingt mille lieues
//                                   sous les mers 0,605 — dernier des cinq
//      « une histoire d'épidémie »  Le Petit Prince 0,697 · La Peste 0,634
//      « un livre pour enfants »    L'Étranger 0,725 · Le Petit Prince 0,721
//
//  (Relevé du 10 septembre 2026, `NLEmbedding.sentenceEmbedding(for: .french)`,
//  sur les textes sémantiques de la bibliothèque de démonstration.)
//
//  Ces tests fixent le comportement attendu sur ces mêmes requêtes, pour que
//  le classement ne reparte pas au hasard.
//

import Foundation
import Testing
@testable import Picpic

struct SearchRankingTests {

    private static func demoLibrary() -> [Book] {
        [
            Book(isbn: "9782070360024", title: "L'Étranger", authors: ["Albert Camus"],
                 bookDescription: "Un homme apprend la mort de sa mère et reste étranger à tout, jusqu'au meurtre sur une plage d'Alger.",
                 subjects: ["Roman", "Absurde"]),
            Book(isbn: "9782253006329", title: "Vingt mille lieues sous les mers", authors: ["Jules Verne"],
                 bookDescription: "Le professeur Aronnax est capturé par le capitaine Nemo à bord du Nautilus et traverse les océans.",
                 subjects: ["Aventure", "Science-fiction"]),
            Book(isbn: "9782070612758", title: "Le Petit Prince", authors: ["Antoine de Saint-Exupéry"],
                 bookDescription: "Un aviateur échoué dans le désert rencontre un enfant venu d'une autre planète.",
                 subjects: ["Conte", "Jeunesse"]),
            Book(isbn: "9782070360420", title: "La Peste", authors: ["Albert Camus"],
                 bookDescription: "La ville d'Oran est frappée par une épidémie et se referme sur elle-même.",
                 subjects: ["Roman"]),
            Book(isbn: "9782070413119", title: "Madame Bovary", authors: ["Gustave Flaubert"],
                 bookDescription: "Emma s'ennuie dans un mariage de province et se perd dans ses rêves.",
                 subjects: ["Classique"]),
        ]
    }

    private func first(_ query: String) -> String? {
        SemanticSearchService.shared.search(query: query, in: Self.demoLibrary()).first?.title
    }

    /// L'exemple affiché dans le champ de recherche. Il doit marcher.
    @Test func theExampleFromTheAppStoreListingWorks() {
        #expect(first("un roman sur la mer") == "Vingt mille lieues sous les mers")
    }

    /// Un mot du résumé suffit quand rien d'autre ne correspond.
    @Test func aWordFromTheSummaryIsEnough() {
        #expect(first("une histoire d'épidémie") == "La Peste")
        #expect(first("un livre pour enfants") == "Le Petit Prince")
    }

    /// Le titre pèse plus que le résumé : chercher un titre le fait remonter,
    /// même si un autre livre en parle.
    @Test func theTitleOutweighsTheSummary() {
        #expect(first("peste") == "La Peste")
        #expect(first("bovary") == "Madame Bovary")
    }

    /// Chercher un auteur rend ses livres, et rien d'autre.
    @Test func searchingAnAuthorReturnsTheirBooks() {
        let results = SemanticSearchService.shared.search(query: "camus", in: Self.demoLibrary())
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.authorsLabel.contains("Camus") })
    }

    /// Accents et pluriels ne doivent pas faire échouer une recherche :
    /// « mer » retrouve « les mers », « epidemie » retrouve « épidémie ».
    @Test func accentsAndPluralsAreForgiven() {
        #expect(first("mers") == "Vingt mille lieues sous les mers")
        #expect(first("epidemie") == "La Peste")
    }

    /// Une requête qui ne correspond à rien rend une liste vide — l'écran dit
    /// alors « essaie une autre idée », ce qui vaut mieux qu'un classement au
    /// hasard présenté comme un résultat.
    @Test func nothingMatchesRatherThanNoise() {
        #expect(SemanticSearchService.shared.search(query: "astrophysique quantique",
                                                    in: Self.demoLibrary()).isEmpty)
    }

    /// Une requête vide rend la bibliothèque entière, dans son ordre.
    @Test func emptyQueryReturnsEverything() {
        let library = Self.demoLibrary()
        #expect(SemanticSearchService.shared.search(query: "  ", in: library).count == library.count)
    }

    /// Les mots vides ne doivent pas peser : « le », « des », « chose » ne
    /// disent rien d'un livre.
    @Test func stopWordsAreIgnored() {
        #expect(SemanticSearchService.meaningfulWords(in: "un livre sur la mer") == ["mer"])
        #expect(SemanticSearchService.meaningfulWords(in: "quelque chose de sombre") == ["sombre"])
    }
}
