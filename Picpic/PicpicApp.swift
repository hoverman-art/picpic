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

    init() {
        ProStore.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(proStore)
                .animation(.easeInOut(duration: 0.5), value: settings.hasCompletedOnboarding)
                .task { await proStore.observeCustomerInfo() }
        }
        .modelContainer(for: Book.self)
    }
}
