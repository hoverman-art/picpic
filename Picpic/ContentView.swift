//
//  ContentView.swift
//  Picpic
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(UserSettings.self) private var settings

    var body: some View {
        if settings.hasCompletedOnboarding {
            HomeView()
                .transition(.opacity.combined(with: .scale(scale: 1.03)))
        } else {
            OnboardingView()
                .transition(.opacity)
        }
    }
}

#Preview {
    ContentView()
        .environment(UserSettings.shared)
        .modelContainer(for: Book.self, inMemory: true)
}
