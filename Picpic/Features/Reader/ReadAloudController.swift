//
//  ReadAloudController.swift
//  Picpic
//
//  Lecture à voix haute d'un chapitre, paragraphe par paragraphe.
//
//  Tout se passe sur l'appareil : `AVSpeechSynthesizer` n'appelle aucun
//  serveur, donc écouter un livre marche en avion comme le reste de Picpic.
//  Le découpage par paragraphe (et non par phrase) est délibéré : c'est une
//  unité que l'on peut surligner de façon fiable dans la page, et une bonne
//  granularité pour reculer de « un bout » quand on a décroché.
//

import AVFoundation
import MediaPlayer
import SwiftUI

/// Une voix installée sur l'appareil, telle qu'on la présente à l'utilisateur.
struct NarratorVoice: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String
    let quality: AVSpeechSynthesisVoiceQuality

    var qualityLabel: String {
        if isNovelty { return "Classique" }
        switch quality {
        case .premium: return "Premium"
        case .enhanced: return "Améliorée"
        default: return "Standard"
        }
    }

    /// Les voix Premium et Améliorées sont nettement plus naturelles ; c'est
    /// le premier critère de tri.
    var qualityRank: Int {
        switch quality {
        case .premium: return 2
        case .enhanced: return 1
        default: return 0
        }
    }

    var isHighQuality: Bool { qualityRank > 0 }

    /// Voix Eloquence : la vieille synthèse à formants d'Apple (« Grandma »,
    /// « Rocko »…). Le système les annonce à la même qualité que les autres,
    /// mais elles sont inécoutables sur la longueur d'un roman.
    var isNovelty: Bool { id.contains(".eloquence.") }

    /// Variante la plus légère, au rendu le plus métallique.
    var isSuperCompact: Bool { id.contains(".super-compact.") }

    /// Ordre de préférence pour la lecture d'un livre, du meilleur au pire.
    /// Explicite à dessein : à qualité déclarée égale — le cas courant, car
    /// aucune voix « Améliorée » n'est installée par défaut — trier seulement
    /// par qualité revient à s'en remettre à l'ordre de la liste système.
    static func preferred(_ a: NarratorVoice, _ b: NarratorVoice,
                          preferredLanguage: String) -> Bool {
        if a.qualityRank != b.qualityRank { return a.qualityRank > b.qualityRank }
        if a.isNovelty != b.isNovelty { return !a.isNovelty }
        let aExact = a.language.caseInsensitiveCompare(preferredLanguage) == .orderedSame
        let bExact = b.language.caseInsensitiveCompare(preferredLanguage) == .orderedSame
        if aExact != bExact { return aExact }
        if a.isSuperCompact != b.isSuperCompact { return !a.isSuperCompact }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }
}

@Observable
@MainActor
final class ReadAloudController: NSObject {

    /// Voix installées, meilleures d'abord, pour la langue du livre puis les
    /// autres variantes de la même langue (fr-CA après fr-FR, par exemple).
    static func availableVoices(matching languagePrefix: String = "fr",
                                preferredLanguage: String = "fr-FR") -> [NarratorVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languagePrefix) }
            .map {
                NarratorVoice(id: $0.identifier, name: $0.name,
                              language: $0.language, quality: $0.quality)
            }
            .sorted { NarratorVoice.preferred($0, $1, preferredLanguage: preferredLanguage) }
    }

    /// Vrai si l'appareil ne propose que des voix standard : la liseuse le dit
    /// alors franchement plutôt que de laisser croire à un défaut de l'app.
    static var onlyStandardVoicesInstalled: Bool {
        !availableVoices().contains { $0.isHighQuality }
    }

    private(set) var isSpeaking = false
    private(set) var isPaused = false
    private(set) var currentParagraph: Int?

    /// Appelé quand le chapitre est fini, pour enchaîner sur le suivant.
    var onFinishedChapter: (() -> Void)?
    /// Appelé à chaque changement de paragraphe, pour surligner la page.
    var onParagraphChange: ((Int) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var paragraphs: [String] = []
    private var index = 0
    private var bookTitle = ""
    private var chapterTitle = ""

    override init() {
        super.init()
        synthesizer.delegate = self
        configureRemoteCommands()
    }

    // MARK: - Commandes

    func start(paragraphs: [String], from paragraph: Int = 0,
               bookTitle: String, chapterTitle: String) {
        guard !paragraphs.isEmpty else { return }
        self.paragraphs = paragraphs
        self.bookTitle = bookTitle
        self.chapterTitle = chapterTitle
        index = min(max(0, paragraph), paragraphs.count - 1)
        activateSession()
        isSpeaking = true
        isPaused = false
        speakCurrent()
    }

    func pause() {
        guard isSpeaking, !isPaused else { return }
        synthesizer.pauseSpeaking(at: .word)
        isPaused = true
        updateNowPlaying()
    }

    func resume() {
        guard isPaused else { return }
        synthesizer.continueSpeaking()
        isPaused = false
        updateNowPlaying()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        currentParagraph = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func skipForward() { jump(to: index + 1) }
    func skipBackward() { jump(to: index - 1) }

    /// Reprend la lecture au paragraphe touché dans la page.
    func jump(to paragraph: Int) {
        guard isSpeaking, paragraphs.indices.contains(paragraph) else { return }
        index = paragraph
        // `stopSpeaking` déclenche `didCancel`, pas `didFinish` : la file est
        // vidée sans faire avancer l'index toute seule.
        synthesizer.stopSpeaking(at: .immediate)
        isPaused = false
        speakCurrent()
    }

    /// Relit le paragraphe courant avec la nouvelle voix ou vitesse.
    func restartCurrentUtterance() {
        guard isSpeaking else { return }
        jump(to: index)
    }

    // MARK: - Synthèse

    private func speakCurrent() {
        guard paragraphs.indices.contains(index) else {
            finishChapter()
            return
        }
        currentParagraph = index
        onParagraphChange?(index)

        let settings = ReaderSettings.shared
        let utterance = AVSpeechUtterance(string: paragraphs[index])
        utterance.voice = settings.selectedVoice()
        utterance.rate = Float(settings.speechRate)
        utterance.pitchMultiplier = 1.0
        // Un souffle entre deux paragraphes : sans lui, la lecture est
        // épuisante à suivre.
        utterance.postUtteranceDelay = 0.35
        synthesizer.speak(utterance)
        updateNowPlaying()
    }

    private func finishChapter() {
        currentParagraph = nil
        onFinishedChapter?()
    }

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    // MARK: - Écran verrouillé

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.resume(); return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause(); return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.skipForward(); return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.skipBackward(); return .success
        }
    }

    private func updateNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapterTitle.isEmpty ? bookTitle : chapterTitle,
            MPMediaItemPropertyArtist: bookTitle,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
        if !paragraphs.isEmpty {
            info[MPNowPlayingInfoPropertyPlaybackProgress] = Double(index) / Double(paragraphs.count)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension ReadAloudController: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard isSpeaking, !isPaused else { return }
            index += 1
            speakCurrent()
        }
    }
}
