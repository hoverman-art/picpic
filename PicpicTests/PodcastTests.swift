//
//  PodcastTests.swift
//  PicpicTests
//
//  Les flux de podcasts sont écrits par des milliers d'outils différents et
//  sont rarement conformes : CDATA, HTML dans les titres, durées tantôt en
//  secondes tantôt en « 00:22:30 », entrées sans fichier audio. Une erreur
//  d'analyse ne se voit pas — elle donne une liste d'épisodes vide, ou pire,
//  un épisode dont le bouton ne joue rien.
//
//  Les extraits ci-dessous reprennent la forme de flux réels (structure des
//  balises, pas leur contenu).
//

import Foundation
import Testing
@testable import Picpic

struct PodcastTests {

    private static let feed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
    <channel>
      <title>Une émission</title>
      <itunes:image href="https://exemple.fr/jaquette.jpg"/>
      <item>
        <title><![CDATA[EP.103 — Créer sa société]]></title>
        <itunes:duration>00:22:30</itunes:duration>
        <enclosure url="https://exemple.fr/episodes/103.mp3" length="21600000" type="audio/mpeg"/>
      </item>
      <item>
        <title>EP.102 &amp; suite</title>
        <itunes:duration>1350</itunes:duration>
        <enclosure length="18000000" type="audio/mpeg" url="https://exemple.fr/episodes/102.mp3"/>
      </item>
      <item>
        <title>Épisode sans audio</title>
        <itunes:duration>600</itunes:duration>
      </item>
    </channel>
    </rss>
    """

    /// Les épisodes sortent dans l'ordre du flux, avec leur fichier.
    @Test func episodesAreRead() {
        let episodes = PodcastService.episodes(inFeed: Self.feed, limit: 10)
        #expect(episodes.count == 2)
        #expect(episodes[0].title == "EP.103 — Créer sa société")
        #expect(episodes[0].listenURL.absoluteString == "https://exemple.fr/episodes/103.mp3")
        #expect(episodes[0].playtime == "00:22:30")
    }

    /// Une entrée sans fichier audio n'a pas à figurer : le bouton ne
    /// jouerait rien, et le lecteur croirait l'application cassée.
    @Test func entriesWithoutAudioAreDropped() {
        let episodes = PodcastService.episodes(inFeed: Self.feed, limit: 10)
        #expect(!episodes.contains { $0.title.contains("sans audio") })
    }

    /// L'attribut `url` de `enclosure` n'est pas toujours le premier.
    @Test func enclosureAttributeOrderDoesNotMatter() {
        let episodes = PodcastService.episodes(inFeed: Self.feed, limit: 10)
        #expect(episodes[1].listenURL.absoluteString == "https://exemple.fr/episodes/102.mp3")
    }

    /// CDATA et entités HTML se lisent comme du texte.
    @Test func titlesAreCleaned() {
        let episodes = PodcastService.episodes(inFeed: Self.feed, limit: 10)
        #expect(!episodes[0].title.contains("CDATA"))
        #expect(episodes[1].title == "EP.102 & suite")
    }

    /// Le plafond est respecté : personne ne fait défiler huit cents épisodes.
    @Test func limitIsHonoured() {
        #expect(PodcastService.episodes(inFeed: Self.feed, limit: 1).count == 1)
    }

    /// Une durée s'écrit en secondes ou en heures : les deux doivent se lire.
    @Test func durationsAreReadable() {
        #expect(PodcastService.readableDuration("1350") == "22 min")
        #expect(PodcastService.readableDuration("5400") == "1 h 30 min")
        #expect(PodcastService.readableDuration("00:22:30") == "00:22:30")
    }

    /// Un flux vide ne doit pas planter, juste ne rien rendre.
    @Test func emptyFeedIsHandled() {
        #expect(PodcastService.episodes(inFeed: "<rss><channel></channel></rss>", limit: 10).isEmpty)
        #expect(PodcastService.episodes(inFeed: "", limit: 10).isEmpty)
    }

    // MARK: - Ce qui classe les résultats

    private static let searchJSON = """
    {"resultCount": 3, "results": [
      {"collectionId": 1, "collectionName": "Les secrets de l'entrepreneur",
       "artistName": "Dougs", "primaryGenreName": "Entrepreneuriat",
       "feedUrl": "https://exemple.fr/flux1.xml",
       "artworkUrl600": "https://exemple.fr/1.jpg", "genres": ["Entrepreneuriat", "Affaires"]},
      {"collectionId": 2, "collectionName": "Sans flux",
       "artistName": "Personne", "primaryGenreName": "Affaires"},
      {"collectionId": 3, "collectionName": "Mindset",
       "artistName": "Dorès", "primaryGenreName": "Affaires",
       "feedUrl": "https://exemple.fr/flux3.xml"}
    ]}
    """

    /// L'ordre de l'annuaire est conservé tel quel. Reclasser par embeddings
    /// avait été tenté puis abandonné : mesuré le 10 septembre 2026,
    /// `NLEmbedding.sentenceEmbedding` en français met la cuisine devant
    /// l'entrepreneuriat sur « créer sa boîte » (0,659 contre 0,612) et le
    /// jardinage devant tout sur « se lever tôt et réussir » (0,837). Ce test
    /// fixe la décision : le service ne réordonne pas.
    @Test func storeOrderIsKept() throws {
        let data = try #require(Self.searchJSON.data(using: .utf8))
        let shows = PodcastService.podcasts(fromSearchJSON: data, limit: 10)
        #expect(shows.map(\.title) == ["Les secrets de l'entrepreneur", "Mindset"])
    }

    /// Une émission sans flux n'a rien à écouter : elle est écartée.
    @Test func showsWithoutFeedAreDropped() throws {
        let data = try #require(Self.searchJSON.data(using: .utf8))
        let shows = PodcastService.podcasts(fromSearchJSON: data, limit: 10)
        #expect(!shows.contains { $0.title == "Sans flux" })
        #expect(shows.first?.artworkURLString == "https://exemple.fr/1.jpg")
    }

    /// Une réponse illisible ne rend rien plutôt que de planter.
    @Test func brokenJSONIsSurvivable() throws {
        let data = try #require("pas du json".data(using: .utf8))
        #expect(PodcastService.podcasts(fromSearchJSON: data, limit: 10).isEmpty)
    }

}
