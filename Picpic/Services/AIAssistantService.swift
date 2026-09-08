//
//  AIAssistantService.swift
//  Picpic
//
//  L'assistant de lecture, sur le modèle embarqué d'Apple Intelligence.
//
//  Pourquoi le modèle système et pas une API distante. Picpic n'a pas de
//  serveurs — c'est écrit dans docs/PRIVACY.md et c'est l'argument central du
//  paywall. Un LLM distant casserait cette promesse, ferait sortir la
//  bibliothèque de l'iPhone, et coûterait à chaque requête, ce qui rendrait un
//  palier gratuit intenable. Le modèle de Foundation Models tourne sur
//  l'appareil : rien ne part, rien ne coûte, et le palier gratuit tient.
//
//  Ce que l'assistant ne fait pas. Il ne résume jamais une œuvre. C'est une
//  décision déjà prise pour les fiches de révision (Features/Revision), pour la
//  même raison : résumer un livre protégé à la place de son lecteur n'est ni
//  utile ni défendable. L'assistant parle de TA bibliothèque — ce que tu as, où
//  tu en es, ce que tu as noté — jamais du contenu des livres.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// État du modèle embarqué sur cet appareil.
enum AssistantAvailability: Equatable {
    case ready
    /// Apple Intelligence absent, désactivé, ou modèle pas encore téléchargé.
    case unavailable(String)

    var isReady: Bool { self == .ready }
}

enum AssistantError: LocalizedError {
    case unavailable(String)
    case emptyLibrary
    case failed

    var errorDescription: String? {
        switch self {
        case .unavailable(let why): return why
        case .emptyLibrary:
            return "Scanne d'abord quelques livres : l'assistant parle de ta bibliothèque, pas de la mienne."
        case .failed:
            return "L'assistant n'a pas réussi à répondre. Reformule ta question, ou pose-la autrement."
        }
    }
}

/// Un livre réduit à ce que l'assistant a le droit de savoir.
///
/// `status` est le type et non son étiquette : c'est lui qui décide quels
/// livres entrent dans la fenêtre du modèle, et trier sur une chaîne traduite
/// casserait au premier changement de libellé.
struct AssistantBook {
    let title: String
    let authors: String
    let subjects: [String]
    let status: ReadingStatus
    let pageCount: Int?
    let rating: Int?
    let notes: String
}

struct AIAssistantService {

    static let shared = AIAssistantService()

    /// Nombre de livres décrits au modèle.
    ///
    /// La fenêtre du modèle embarqué est de 4 096 jetons, entrée et sortie
    /// confondues. À 40 livres annotés on la dépassait, et le lecteur le plus
    /// assidu — celui qui achète le Pro — était le seul à ne jamais obtenir de
    /// réponse. Quinze livres suffisent à répondre « lequel ensuite ».
    static let maxBooks = 15

    /// Les quinze livres qui entrent dans la fenêtre, et dans quel ordre.
    ///
    /// La récence seule était le mauvais critère : « qu'est-ce que je lis
    /// ensuite ? » se répond avec ce qu'on a en cours et ce dont on a envie,
    /// pas avec les derniers scans. Un livre commencé il y a six mois compte
    /// plus qu'un livre ajouté hier et déjà terminé.
    ///
    /// À rang égal l'ordre d'entrée est conservé — la liste arrive déjà triée
    /// par date d'ajout décroissante, et `sorted(by:)` n'est pas stable.
    static func select(_ library: [AssistantBook]) -> [AssistantBook] {
        func rank(_ status: ReadingStatus) -> Int {
            switch status {
            case .reading: return 0
            case .wishlist: return 1
            case .toRead: return 2
            case .finished: return 3
            }
        }
        return library.enumerated()
            .sorted { a, b in
                let (ra, rb) = (rank(a.element.status), rank(b.element.status))
                return ra == rb ? a.offset < b.offset : ra < rb
            }
            .prefix(maxBooks)
            .map(\.element)
    }

    private static let instructions = """
    Tu es l'assistant de lecture de Picpic. Tu t'adresses à un étudiant français, \
    en le tutoyant, sur un ton chaleureux et direct.

    Tu ne connais QUE la bibliothèque personnelle qu'on te donne. Tu parles de ces \
    livres-là : lesquels lire ensuite, lesquels correspondent à une envie, ce que \
    les notes du lecteur en disent, où il en est de ses lectures.

    Règles absolues :
    - Ne résume JAMAIS le contenu d'un livre, même si on te le demande. Réponds \
    alors que tu ne résumes pas les œuvres, et propose plutôt d'aider à choisir.
    - N'invente aucun livre, aucun auteur, aucune donnée. Si la bibliothèque ne \
    permet pas de répondre, dis-le franchement.
    - Réponds court : trois phrases, ou une liste de trois titres maximum.
    - Cite les titres exactement comme ils te sont donnés.
    """

    /// Le modèle est-il utilisable ici et maintenant ?
    func availability() -> AssistantAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            return .unavailable("Cet iPhone ne prend pas en charge Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Active Apple Intelligence dans Réglages pour utiliser l'assistant.")
        case .unavailable(.modelNotReady):
            return .unavailable("Le modèle se télécharge encore. Réessaie dans quelques minutes.")
        case .unavailable:
            return .unavailable("L'assistant n'est pas disponible sur cet appareil.")
        }
        #else
        return .unavailable("L'assistant demande iOS 26 et Apple Intelligence.")
        #endif
    }

    /// Répond à une question, avec la bibliothèque pour seul contexte.
    func answer(question: String, library: [AssistantBook]) async throws -> String {
        guard !library.isEmpty else { throw AssistantError.emptyLibrary }
        if case .unavailable(let why) = availability() { throw AssistantError.unavailable(why) }

        #if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: Self.instructions)
        let prompt = """
        Voici ma bibliothèque :

        \(Self.describe(Self.select(library)))

        Ma question : \(question)
        """
        do {
            return try await session.respond(to: prompt).content
        } catch {
            throw AssistantError.failed
        }
        #else
        throw AssistantError.unavailable("L'assistant demande iOS 26 et Apple Intelligence.")
        #endif
    }

    /// Bibliothèque mise à plat, une ligne par livre.
    ///
    /// Ne tronque pas : la sélection est le travail de `select`, et la vue doit
    /// pouvoir annoncer combien de livres ont réellement servi.
    ///
    /// Les notes personnelles sont tronquées : elles peuvent être longues, et
    /// une seule note bavarde suffirait à évincer trente livres du contexte.
    static func describe(_ library: [AssistantBook]) -> String {
        library.map { book in
            var line = "- « \(book.title) », \(book.authors) — \(book.status.label)"
            if let pages = book.pageCount { line += ", \(pages) pages" }
            if let rating = book.rating { line += ", noté \(rating)/5" }
            if !book.subjects.isEmpty {
                line += ", thèmes : \(book.subjects.prefix(4).joined(separator: ", "))"
            }
            let notes = book.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty { line += "\n  ma note : \(notes.prefix(80))" }
            return line
        }.joined(separator: "\n")
    }
}
