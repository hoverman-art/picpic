//
//  NarratorVoiceTests.swift
//  PicpicTests
//
//  Le classement des voix décide de celle qui lira un livre entier par défaut.
//  Comme aucune voix « Améliorée » n'est installée d'origine (constaté : 18 voix
//  françaises sur un Mac, toutes déclarées « standard »), départager uniquement
//  par palier de qualité revient à s'en remettre à l'ordre de la liste système.
//  Ces tests fixent l'ordre voulu.
//

import AVFoundation
import Testing
@testable import Picpic

@MainActor
struct NarratorVoiceTests {

    private func voice(_ id: String, _ name: String, _ language: String,
                       _ quality: AVSpeechSynthesisVoiceQuality = .default) -> NarratorVoice {
        NarratorVoice(id: id, name: name, language: language, quality: quality)
    }

    private func sorted(_ voices: [NarratorVoice]) -> [String] {
        voices
            .sorted { NarratorVoice.preferred($0, $1, preferredLanguage: "fr-FR") }
            .map(\.name)
    }

    @Test func qualityStillWinsWhenItDiffers() {
        let list = [
            voice("com.apple.voice.compact.fr-FR.Thomas", "Thomas", "fr-FR"),
            voice("com.apple.voice.premium.fr-FR.Marie", "Marie", "fr-FR", .premium),
            voice("com.apple.voice.enhanced.fr-FR.Paul", "Paul", "fr-FR", .enhanced),
        ]
        #expect(sorted(list) == ["Marie", "Paul", "Thomas"])
    }

    /// Le cas qui compte : tout le monde à « standard ».
    @Test func noveltyVoicesNeverWinByDefault() {
        let list = [
            voice("com.apple.eloquence.fr-FR.Grandma", "Grandma", "fr-FR"),
            voice("com.apple.eloquence.fr-FR.Rocko", "Rocko", "fr-FR"),
            voice("com.apple.voice.compact.fr-FR.Thomas", "Thomas", "fr-FR"),
        ]
        #expect(sorted(list).first == "Thomas")
    }

    @Test func exactLanguageBeatsOtherRegions() {
        let list = [
            voice("com.apple.voice.compact.fr-CA.Amelie", "Amélie", "fr-CA"),
            voice("com.apple.voice.compact.fr-FR.Thomas", "Thomas", "fr-FR"),
        ]
        #expect(sorted(list) == ["Thomas", "Amélie"])
    }

    @Test func superCompactIsTheLastResortAmongRealVoices() {
        let list = [
            voice("com.apple.voice.super-compact.fr-FR.Aaron", "Aaron", "fr-FR"),
            voice("com.apple.voice.compact.fr-FR.Zoe", "Zoé", "fr-FR"),
        ]
        // Zoé passe devant malgré l'ordre alphabétique : la variante allégée
        // sonne nettement plus métallique.
        #expect(sorted(list) == ["Zoé", "Aaron"])
    }

    /// L'étiquette doit dire au lecteur ce qu'il choisit.
    @Test func noveltyVoicesAreLabelledAsSuch() {
        #expect(voice("com.apple.eloquence.fr-FR.Rocko", "Rocko", "fr-FR").qualityLabel == "Classique")
        #expect(voice("com.apple.voice.compact.fr-FR.Thomas", "Thomas", "fr-FR").qualityLabel == "Standard")
        #expect(voice("x.premium.y", "Marie", "fr-FR", .premium).qualityLabel == "Premium")
    }

    @Test func onlyDownloadedVoicesCountAsHighQuality() {
        #expect(!voice("com.apple.voice.compact.fr-FR.Thomas", "Thomas", "fr-FR").isHighQuality)
        #expect(voice("x", "Paul", "fr-FR", .enhanced).isHighQuality)
    }
}
