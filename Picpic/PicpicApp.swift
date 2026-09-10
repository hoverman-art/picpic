//
//  PicpicApp.swift
//  Picpic
//

import SwiftUI
import SwiftData

/// Le magasin SwiftData, partagé entre l'application et ses App Intents.
///
/// La scène le créait pour elle seule (`.modelContainer(for:)`). Un intent —
/// la recherche visuelle, par exemple — s'exécute hors de cette hiérarchie de
/// vues : sans conteneur commun, il ouvrirait une seconde base, vide, et
/// jurerait que la bibliothèque du lecteur n'existe pas.
enum LibraryStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Book.self, Quote.self)
        } catch {
            // Une base illisible se soigne en la recréant : perdre la
            // bibliothèque est grave, mais une app qui refuse de s'ouvrir
            // l'est plus, et le scan la reconstruit.
            return try! ModelContainer(for: Book.self, Quote.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }()
}

@main
struct PicpicApp: App {
    @State private var settings = UserSettings.shared
    @State private var proStore = ProStore.shared
    @State private var goals = ReadingGoalStore.shared
    @State private var revisionStore = RevisionSheetStore.shared
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
                .environment(assistantStore)
                .animation(.easeInOut(duration: 0.5), value: settings.hasCompletedOnboarding)
                .task { await proStore.observeCustomerInfo() }
                .onAppear { goals.refreshStreak() }
        }
        .modelContainer(LibraryStore.container)
    }
}
