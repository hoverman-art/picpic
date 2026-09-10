//
//  BookIntents.swift
//  Picpic
//
//  Picpic dans la recherche visuelle d'iOS 26.
//
//  Ce que ça change, concrètement : on vise un livre avec l'appareil photo —
//  ou on capture une image — et Picpic figure parmi les applications qui
//  savent répondre. Le lecteur voit le titre, l'auteur, et s'il l'a déjà dans
//  sa bibliothèque. Un tap ouvre Picpic dessus.
//
//  Pour le chineur, c'est le geste qui manquait : en brocante, les livres
//  d'avant 1970 n'ont pas de code-barres, et le scan ISBN ne sert à rien. Une
//  couverture, elle, se lit toujours.
//
//  Comment le système s'y branche : `IntentValueQuery` reçoit un
//  `SemanticContentDescriptor` — les étiquettes que la recherche visuelle a
//  posées, et l'image cadrée. Rien à déclarer de plus : les métadonnées App
//  Intents sont compilées avec l'application.
//

import AppIntents
import Foundation
import SwiftData
#if canImport(VisualIntelligence)
import VisualIntelligence
#endif

// MARK: - Le livre, vu par le système

nonisolated struct BookEntity: AppEntity, Identifiable {

    init(id: String, title: String, authors: String, coverURLString: String?, inLibrary: Bool) {
        self.id = id
        self.title = title
        self.authors = authors
        self.coverURLString = coverURLString
        self.inLibrary = inLibrary
    }

    /// Un livre reconnu sur une image. L'identifiant retombe sur « titre |
    /// auteur » quand l'édition n'a pas d'ISBN — ce qui est la règle avant
    /// 1970, et donc la règle en brocante.
    init(_ found: VisualBookLookup.Found) {
        self.init(id: found.isbn ?? "\(found.title)|\(found.authors)",
                  title: found.title,
                  authors: found.authors,
                  coverURLString: found.coverURLString,
                  inLibrary: found.inLibrary)
    }

    /// L'ISBN quand il existe, sinon titre + auteur : la recherche visuelle
    /// tombe régulièrement sur des éditions anciennes qui n'en ont pas.
    let id: String
    let title: String
    let authors: String
    let coverURLString: String?
    let inLibrary: Bool

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Livre", numericFormat: "\(placeholder: .int) livres")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: inLibrary ? "\(authors) · déjà dans ta bibliothèque" : "\(authors)",
            image: coverURLString.flatMap(URL.init(string:)).map { .init(url: $0) }
        )
    }

    static let defaultQuery = BookEntityQuery()
}

/// Retrouve un livre par son identifiant, pour que le système puisse le
/// reconstruire d'une session à l'autre.
nonisolated struct BookEntityQuery: EntityQuery {

    func entities(for identifiers: [String]) async throws -> [BookEntity] {
        guard let context = try? ModelContext(LibraryStore.container) else { return [] }
        let books = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        return identifiers.compactMap { identifier in
            guard let book = books.first(where: { $0.isbn == identifier }) else { return nil }
            return BookEntity(id: book.isbn, title: book.title, authors: book.authorsLabel,
                              coverURLString: book.coverURLString, inLibrary: true)
        }
    }
}

// MARK: - Ce que la recherche visuelle demande

#if canImport(VisualIntelligence)
/// Le pont entre l'image que regarde l'utilisateur et la bibliothèque.
///
/// Sous `canImport` parce que `VisualIntelligence` n'existe que sur
/// l'appareil : le SDK du simulateur ne l'embarque pas, et sans cette garde
/// l'application entière refuserait de compiler pour les tests.
nonisolated struct BookVisualQuery: IntentValueQuery {

    func values(for input: SemanticContentDescriptor) async throws -> [BookEntity] {
        let found = await VisualBookLookup.shared.lookup(pixelBuffer: input.pixelBuffer,
                                                         labels: input.labels)
        return found.map(BookEntity.init)
    }
}
#endif

// MARK: - Ouvrir Picpic dessus

nonisolated struct OpenBookIntent: OpenIntent {

    static let title: LocalizedStringResource = "Ouvrir dans Picpic"
    static let description = IntentDescription("Affiche ce livre dans Picpic : sa fiche, sa disponibilité, son estimation.")

    @Parameter(title: "Livre")
    var target: BookEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        // L'intent s'exécute dans l'application (`openAppWhenRun`) : il suffit
        // de déposer la demande, l'accueil la ramasse.
        PendingBook.shared.request(isbn: target.id.contains("|") ? nil : target.id,
                                   title: target.title)
        return .result()
    }
}

// MARK: - Le relais vers l'écran

/// Ce que la recherche visuelle a demandé d'ouvrir, en attendant que l'accueil
/// s'affiche.
///
/// Un intent ne peut pas naviguer lui-même : il pose ici ce qu'il veut, et
/// `HomeView` s'en saisit à la première occasion. Si le livre est dans la
/// bibliothèque on ouvre sa fiche ; sinon on remplit la recherche avec son
/// titre, et la section « Ailleurs qu'ici » propose de l'ajouter.
@MainActor
@Observable
final class PendingBook {

    static let shared = PendingBook()

    private(set) var isbn: String?
    private(set) var title: String?

    func request(isbn: String?, title: String?) {
        self.isbn = isbn
        self.title = title
    }

    func clear() {
        isbn = nil
        title = nil
    }
}

// MARK: - Raccourcis

/// Rend l'action visible dans Spotlight, Siri et les Raccourcis, sans que le
/// lecteur ait rien à configurer.
nonisolated struct PicpicShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenBookIntent(),
            phrases: ["Ouvre ce livre dans \(.applicationName)",
                      "Montre ce livre dans \(.applicationName)"],
            shortTitle: "Ouvrir un livre",
            systemImageName: "book.closed"
        )
    }
}
