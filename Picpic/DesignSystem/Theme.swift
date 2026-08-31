//
//  Theme.swift
//  Picpic
//

import SwiftUI

enum Theme {
    // Palette encre & papier, accent corail chaleureux.
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.18)
    static let paper = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let accent = Color(red: 0.95, green: 0.44, blue: 0.31)
    static let lavender = Color(red: 0.56, green: 0.50, blue: 0.96)
    static let teal = Color(red: 0.17, green: 0.62, blue: 0.60)
    static let gold = Color(red: 0.93, green: 0.72, blue: 0.28)

    static let onboardingGradients: [[Color]] = [
        [Color(red: 0.13, green: 0.12, blue: 0.28), Color(red: 0.32, green: 0.16, blue: 0.40)],
        [Color(red: 0.09, green: 0.24, blue: 0.32), Color(red: 0.13, green: 0.42, blue: 0.42)],
        [Color(red: 0.30, green: 0.13, blue: 0.22), Color(red: 0.62, green: 0.26, blue: 0.24)],
        [Color(red: 0.11, green: 0.14, blue: 0.30), Color(red: 0.20, green: 0.30, blue: 0.55)],
    ]
}

extension Font {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }
}
