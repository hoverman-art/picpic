//
//  PicpicApp.swift
//  Picpic
//

import SwiftUI
import SwiftData

@main
struct PicpicApp: App {
    @State private var settings = UserSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .animation(.easeInOut(duration: 0.5), value: settings.hasCompletedOnboarding)
        }
        .modelContainer(for: Book.self)
    }
}
