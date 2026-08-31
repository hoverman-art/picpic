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
                // Bibliothèque de démonstration pour captures d'écran et previews.
                if ProcessInfo.processInfo.arguments.contains("-uitest-demo-books") {
                    try? modelContext.delete(model: Book.self)
                    for book in Self.demoBooks {
                        modelContext.insert(book)
                    }
                    try? modelContext.save()
                }
            }
    }

    private static var demoBooks: [Book] {
        func demo(_ isbn: String, _ title: String, _ author: String,
                  _ status: ReadingStatus, subjects: [String] = []) -> Book {
            Book(isbn: isbn, title: title, authors: [author], subjects: subjects,
                 coverURLString: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg",
                 language: "fr", status: status)
        }
        return [
            demo("9782070360024", "L'Étranger", "Albert Camus", .reading,
                 subjects: ["Roman", "Absurde"]),
            demo("9782070612758", "Le Petit Prince", "Antoine de Saint-Exupéry", .finished,
                 subjects: ["Conte", "Jeunesse"]),
            demo("9782070781935", "L'Élégance du hérisson", "Muriel Barbery", .finished,
                 subjects: ["Roman contemporain"]),
            demo("9782253006329", "Vingt mille lieues sous les mers", "Jules Verne", .toRead,
                 subjects: ["Aventure", "Science-fiction"]),
            demo("9782070360420", "La Peste", "Albert Camus", .toRead,
                 subjects: ["Roman"]),
            demo("9782070413119", "Madame Bovary", "Gustave Flaubert", .wishlist,
                 subjects: ["Classique"]),
        ]
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
