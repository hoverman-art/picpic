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
