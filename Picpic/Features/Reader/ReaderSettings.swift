//
//  ReaderSettings.swift
//  Picpic
//
//  Les réglages de confort de la liseuse, retenus d'un livre à l'autre.
//

import AVFoundation
import Foundation
import SwiftUI

@Observable
@MainActor
final class ReaderSettings {

    static let shared = ReaderSettings()

    enum Theme: String, CaseIterable, Identifiable {
        case paper, sepia, night

        var id: String { rawValue }

        var label: String {
            switch self {
            case .paper: return "Papier"
            case .sepia: return "Sépia"
            case .night: return "Nuit"
            }
        }

        /// Couleurs en hexadécimal, injectées telles quelles dans la page.
        var backgroundHex: String {
            switch self {
            case .paper: return "#F7F5ED"
            case .sepia: return "#F2E4CC"
            case .night: return "#15151F"
            }
        }

        var textHex: String {
            switch self {
            case .paper: return "#1A1A2E"
            case .sepia: return "#3B2E1A"
            case .night: return "#E4E1EC"
            }
        }

        var background: Color {
            switch self {
            case .paper: return Color(red: 0.97, green: 0.96, blue: 0.93)
            case .sepia: return Color(red: 0.95, green: 0.89, blue: 0.80)
            case .night: return Color(red: 0.08, green: 0.08, blue: 0.12)
            }
        }

        var foreground: Color {
            switch self {
            case .paper: return Color(red: 0.10, green: 0.10, blue: 0.18)
            case .sepia: return Color(red: 0.23, green: 0.18, blue: 0.10)
            case .night: return Color(red: 0.89, green: 0.88, blue: 0.93)
            }
        }
    }

    enum Typeface: String, CaseIterable, Identifiable {
        case serif, sans

        var id: String { rawValue }

        var label: String {
            switch self {
            case .serif: return "Serif"
            case .sans: return "Sans"
            }
        }

        /// Familles système : aucune police à embarquer.
        var cssFamily: String {
            switch self {
            case .serif: return "Georgia, 'Times New Roman', serif"
            case .sans: return "-apple-system, 'Helvetica Neue', sans-serif"
            }
        }
    }

    enum Spacing: String, CaseIterable, Identifiable {
        case compact, normal, airy

        var id: String { rawValue }

        var label: String {
            switch self {
            case .compact: return "Serré"
            case .normal: return "Normal"
            case .airy: return "Aéré"
            }
        }

        var lineHeight: Double {
            switch self {
            case .compact: return 1.4
            case .normal: return 1.7
            case .airy: return 2.0
            }
        }
    }

    var theme: Theme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "reader.theme") }
    }
    var typeface: Typeface {
        didSet { UserDefaults.standard.set(typeface.rawValue, forKey: "reader.typeface") }
    }
    var spacing: Spacing {
        didSet { UserDefaults.standard.set(spacing.rawValue, forKey: "reader.spacing") }
    }
    /// Taille du texte en points CSS.
    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "reader.fontSize") }
    }

    /// Voix de lecture choisie, parmi celles installées sur l'appareil.
    var voiceIdentifier: String? {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: "reader.voice") }
    }

    /// Débit, entre `AVSpeechUtteranceMinimumSpeechRate` et le maximum.
    var speechRate: Double {
        didSet { UserDefaults.standard.set(speechRate, forKey: "reader.speechRate") }
    }

    private init() {
        let defaults = UserDefaults.standard
        theme = Theme(rawValue: defaults.string(forKey: "reader.theme") ?? "") ?? .paper
        typeface = Typeface(rawValue: defaults.string(forKey: "reader.typeface") ?? "") ?? .serif
        spacing = Spacing(rawValue: defaults.string(forKey: "reader.spacing") ?? "") ?? .normal
        let saved = defaults.double(forKey: "reader.fontSize")
        fontSize = saved > 0 ? saved : 19
        voiceIdentifier = defaults.string(forKey: "reader.voice")
        let rate = defaults.double(forKey: "reader.speechRate")
        speechRate = rate > 0 ? rate : Double(AVSpeechUtteranceDefaultSpeechRate)
    }

    // MARK: - Voix

    /// La voix à utiliser : celle choisie si elle est toujours installée,
    /// sinon la meilleure disponible. Une voix peut disparaître (l'utilisateur
    /// l'a supprimée dans les Réglages) — ne pas retomber sur `nil` évite que
    /// la lecture se fasse soudain dans la langue du système.
    func selectedVoice() -> AVSpeechSynthesisVoice? {
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            return voice
        }
        return bestAvailableVoice()
    }

    func bestAvailableVoice(language: String = "fr") -> AVSpeechSynthesisVoice? {
        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
        return best ?? AVSpeechSynthesisVoice(language: "fr-FR")
    }

    // MARK: - Progression

    /// Dernier chapitre lu pour un livre donné.
    func lastChapter(for key: String) -> Int {
        UserDefaults.standard.integer(forKey: "reader.progress.\(key)")
    }

    func setLastChapter(_ index: Int, for key: String) {
        UserDefaults.standard.set(index, forKey: "reader.progress.\(key)")
    }

    /// La feuille de style injectée dans le chapitre affiché.
    func css() -> String {
        """
        :root { color-scheme: \(theme == .night ? "dark" : "light"); }
        html, body {
            margin: 0;
            padding: 0 20px 64px;
            background: \(theme.backgroundHex);
            color: \(theme.textHex);
            font-family: \(typeface.cssFamily);
            font-size: \(Int(fontSize))px;
            line-height: \(spacing.lineHeight);
            -webkit-text-size-adjust: none;
            text-rendering: optimizeLegibility;
        }
        p { margin: 0 0 1em; text-align: justify; hyphens: auto; -webkit-hyphens: auto; }
        h1, h2, h3, h4 { line-height: 1.25; margin: 1.6em 0 0.6em; text-wrap: balance; }
        img, svg, figure { max-width: 100%; height: auto; margin: 1em auto; display: block; }
        a { color: inherit; }
        table { max-width: 100%; display: block; overflow-x: auto; }
        pre { white-space: pre-wrap; word-wrap: break-word; }
        hr { border: 0; border-top: 1px solid currentColor; opacity: 0.2; margin: 2em 0; }
        /* Paragraphe en cours de lecture à voix haute. */
        .pp-now {
            background: rgba(240, 112, 80, 0.20);
            border-radius: 6px;
            box-shadow: 0 0 0 6px rgba(240, 112, 80, 0.20);
        }
        @media (prefers-reduced-motion: no-preference) {
            .pp-now { transition: background 0.25s ease; }
        }
        """
    }
}
