//
//  ReaderProfile.swift
//  Picpic
//

import Foundation
import SwiftUI

enum ReaderProfile: String, CaseIterable, Identifiable, Codable {
    case student
    case casual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .student: return "Étudiant·e"
        case .casual: return "Lecteur·rice"
        }
    }

    var subtitle: String {
        switch self {
        case .student: return "BU, Sudoc, documents liés à ma filière"
        case .casual: return "Romans, médiathèque, librairies locales"
        }
    }

    var symbol: String {
        switch self {
        case .student: return "graduationcap.fill"
        case .casual: return "book.fill"
        }
    }
}

enum StudyField: String, CaseIterable, Identifiable, Codable {
    case droit, sciences, lettres, histoire, eco, sante, info, langues

    var id: String { rawValue }

    var label: String {
        switch self {
        case .droit: return "Droit"
        case .sciences: return "Sciences"
        case .lettres: return "Lettres"
        case .histoire: return "Histoire-Géo"
        case .eco: return "Éco-Gestion"
        case .sante: return "Santé"
        case .info: return "Informatique"
        case .langues: return "Langues"
        }
    }

    var symbol: String {
        switch self {
        case .droit: return "building.columns"
        case .sciences: return "atom"
        case .lettres: return "text.book.closed"
        case .histoire: return "globe.europe.africa"
        case .eco: return "chart.line.uptrend.xyaxis"
        case .sante: return "cross.case"
        case .info: return "chevron.left.forwardslash.chevron.right"
        case .langues: return "character.bubble"
        }
    }

    /// Vedettes-matière Rameau proposées pour la filière, dans l'ordre
    /// d'entrée en matière. Chacune a été vérifiée contre le fonds réel de la
    /// BU de La Rochelle (aucune ne renvoie moins d'une cinquantaine de
    /// notices) : une puce qui ouvre sur une liste vide serait pire qu'absente.
    var sudocSubjects: [String] {
        switch self {
        case .droit:
            return ["droit constitutionnel", "droit civil", "droit administratif",
                    "droit pénal", "droit international", "droit du travail"]
        case .sciences:
            return ["mathématiques", "physique", "chimie", "biologie",
                    "écologie", "statistique"]
        case .lettres:
            return ["littérature française", "roman", "poésie", "théâtre",
                    "littérature comparée", "stylistique"]
        case .histoire:
            return ["histoire de France", "géographie", "archéologie",
                    "géopolitique", "histoire moderne", "histoire contemporaine"]
        case .eco:
            return ["gestion d'entreprise", "management", "économie politique",
                    "marketing", "finances", "comptabilité"]
        case .sante:
            return ["psychologie", "médecine", "santé publique", "anatomie",
                    "soins infirmiers", "pharmacologie"]
        case .info:
            return ["informatique", "réseaux d'ordinateurs", "programmation",
                    "intelligence artificielle", "bases de données", "cybersécurité"]
        case .langues:
            return ["linguistique", "anglais (langue)", "traduction",
                    "espagnol (langue)", "littérature anglaise", "didactique des langues"]
        }
    }
}

/// App-wide user settings persisted in UserDefaults (zero backend).
@Observable
final class UserSettings {
    static let shared = UserSettings()

    var profile: ReaderProfile {
        didSet { UserDefaults.standard.set(profile.rawValue, forKey: "reader.profile") }
    }
    var studyField: StudyField? {
        didSet { UserDefaults.standard.set(studyField?.rawValue, forKey: "reader.studyField") }
    }
    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "onboarding.done") }
    }
    var scanCount: Int {
        didSet { UserDefaults.standard.set(scanCount, forKey: "stats.scanCount") }
    }
    var lastReviewRequestDate: Date? {
        didSet { UserDefaults.standard.set(lastReviewRequestDate, forKey: "review.lastRequest") }
    }
    var didRateApp: Bool {
        didSet { UserDefaults.standard.set(didRateApp, forKey: "review.didRate") }
    }

    private init() {
        let defaults = UserDefaults.standard
        profile = ReaderProfile(rawValue: defaults.string(forKey: "reader.profile") ?? "") ?? .casual
        studyField = StudyField(rawValue: defaults.string(forKey: "reader.studyField") ?? "")
        hasCompletedOnboarding = defaults.bool(forKey: "onboarding.done")
        scanCount = defaults.integer(forKey: "stats.scanCount")
        lastReviewRequestDate = defaults.object(forKey: "review.lastRequest") as? Date
        didRateApp = defaults.bool(forKey: "review.didRate")
    }
}
