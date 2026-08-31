//
//  ContentView.swift
//  Picpic
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        content
            .task {
                // UI tests pass this flag to start from an empty library.
                if ProcessInfo.processInfo.arguments.contains("-uitest-reset-books") {
                    try? modelContext.delete(model: Book.self)
                    try? modelContext.save()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
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
