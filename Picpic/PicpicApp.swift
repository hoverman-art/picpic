//
//  PicpicApp.swift
//  Picpic
//

import SwiftUI
import SwiftData

@main
struct PicpicApp: App {
    @State private var settings = UserSettings.shared
    @State private var proStore = ProStore.shared
    @State private var goals = ReadingGoalStore.shared
    @State private var revisionStore = RevisionSheetStore.shared
    @State private var readerSettings = ReaderSettings.shared
    @State private var assistantStore = AssistantStore.shared

    init() {
        ProStore.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(proStore)
                .environment(goals)
                .environment(revisionStore)
                .environment(readerSettings)
                .environment(assistantStore)
                .animation(.easeInOut(duration: 0.5), value: settings.hasCompletedOnboarding)
                .task { await proStore.observeCustomerInfo() }
                .onAppear { goals.refreshStreak() }
        }
        .modelContainer(for: [Book.self, Quote.self])
    }
}
