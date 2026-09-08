//
//  LibraryImportService.swift
//  Picpic
//
//  Import d'une bibliothèque existante depuis un fichier CSV.
//
//  Pourquoi c'est la fonction qui manquait le plus. L'audit de la concurrence
//  américaine (docs/AUDIT-CONCURRENCE.md) est sans ambiguïté : Fable et
//  StoryGraph annoncent l'import Goodreads dès la première ligne de leur fiche
//  App Store. Face à un catalogue déjà rempli ailleurs, on ne se vend pas sur
//  ce qu'on fait de mieux, on se vend sur la facilité du déménagement. Sans
//  import, chaque nouveau lecteur devait rescanner deux cents livres à la main.
//
//  Pourquoi un lecteur générique plutôt qu'un lecteur Goodreads. Babelio,
//  Gleeph, Libib et les tableurs personnels exportent tous du CSV, avec des
//  en-têtes différents et souvent en français. Coder le schéma exact de
//  Goodreads aurait couvert un seul cas et cassé au premier changement de
//  colonne. On reconnaît donc les en-têtes par leur nom, dans les deux langues,
//  et l'ordre des colonnes n'a aucune importance.
//
//  Pourquoi aucun appel réseau à l'import. Deux cents livres, ce sont deux
//  cents requêtes : plusieurs minutes, un risque d'échec à mi-chemin, et un
//  écran bloqué. Le CSV porte déjà titre, auteur, note et pages ; la couverture
//  s'obtient sans requête par l'URL Open Library indexée sur l'ISBN, et
//  `AsyncImage` la charge quand la carte s'affiche. L'import est donc instantané
//  et fonctionne hors connexion.
//

import Foundation

/// Un livre lu dans le fichier, avant tout contact avec la base.
struct ImportedBook {
    let isbn: String
    let title: String
    let authors: [String]
    let rating: Int?
    let pageCount: Int?
    let status: ReadingStatus
    let notes: String
}

/// Ce que le fichier contenait, y compris ce qui n'a pas pu être retenu.
///
/// Les rejets sont comptés et non tus : un import qui annonce « 180 livres »
/// sur un fichier de 200 lignes doit pouvoir dire où sont passées les vingt
/// autres, sinon le lecteur croit à une perte de données.
struct ImportPreview {
    var books: [ImportedBook] = []
    var totalRows = 0
    var skippedNoISBN = 0
    var skippedNoTitle = 0
    var duplicatesInFile = 0

    var skippedTotal: Int { skippedNoISBN + skippedNoTitle + duplicatesInFile }
}

enum ImportError: LocalizedError {
    case unreadable
    case noHeader
    case noRecognizedColumns

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Impossible de lire ce fichier. Vérifie que c'est bien un CSV."
        case .noHeader:
            return "Ce fichier est vide."
        case .noRecognizedColumns:
            return "Aucune colonne reconnue. Il faut au minimum un titre et un ISBN — "
                 + "l'export CSV de Goodreads ou de Babelio convient tel quel."
        }
    }
}

enum LibraryImportService {

    // MARK: - Lecture du fichier

    /// Décode le fichier, quel que soit son encodage.
    ///
    /// Les exports français sortent régulièrement en Latin-1 : décoder en UTF-8
    /// sans repli rendait tout fichier accentué illisible.
    static func text(from data: Data) throws -> String {
        for encoding in [String.Encoding.utf8, .isoLatin1, .windowsCP1252, .utf16] {
            if let s = String(data: data, encoding: encoding) { return s }
        }
        throw ImportError.unreadable
    }

    // MARK: - Analyse

    static func preview(csv raw: String) throws -> ImportPreview {
        let text = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
        let rows = CSVReader.rows(from: text, separator: separator(of: text))
        guard let header = rows.first else { throw ImportError.noHeader }

        let map = ColumnMap(header: header)
        guard map.title != nil, map.isbn != nil else { throw ImportError.noRecognizedColumns }

        var preview = ImportPreview()
        var seen = Set<String>()

        for row in rows.dropFirst() {
            // Une ligne vide en fin de fichier n'est pas un rejet, c'est un
            // retour chariot final : elle ne doit pas gonfler les compteurs.
            guard row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            else { continue }
            preview.totalRows += 1

            let title = map.value(.title, in: row)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { preview.skippedNoTitle += 1; continue }

            guard let isbn = normalizedISBN(map.value(.isbn, in: row)) else {
                preview.skippedNoISBN += 1
                continue
            }
            guard seen.insert(isbn).inserted else {
                preview.duplicatesInFile += 1
                continue
            }

            preview.books.append(ImportedBook(
                isbn: isbn,
                title: title,
                authors: authors(from: map.value(.author, in: row)),
                rating: rating(from: map.value(.rating, in: row)),
                pageCount: map.value(.pages, in: row).flatMap { Int($0.filter(\.isNumber)) },
                status: status(from: map.value(.status, in: row)),
                notes: map.value(.notes, in: row)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            ))
        }
        return preview
    }

    /// Couverture sans requête : Open Library sert l'image indexée sur l'ISBN.
    static func coverURLString(isbn: String) -> String {
        "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg"
    }

    // MARK: - Conversions

    /// `,` ou `;` : les exports français sortent en point-virgule, parce que la
    /// virgule y est le séparateur décimal.
    private static func separator(of text: String) -> Character {
        let firstLine = text.prefix(while: { $0 != "\n" && $0 != "\r" && $0 != "\r\n" })
        var commas = 0, semis = 0, inQuotes = false
        for c in firstLine {
            if c == "\"" { inQuotes.toggle() }
            guard !inQuotes else { continue }
            if c == "," { commas += 1 } else if c == ";" { semis += 1 }
        }
        return semis > commas ? ";" : ","
    }

    /// Goodreads exporte `="9782070360024"` — la formule qui empêche Excel de
    /// transformer l'ISBN en nombre. Sans ce nettoyage, aucun ISBN ne passe.
    static func normalizedISBN(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let digits = raw.uppercased().filter { $0.isNumber || $0 == "X" }
        guard digits.count == 10 || digits.count == 13 else { return nil }
        return digits
    }

    private static func authors(from raw: String?) -> [String] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else { return [] }
        // Découpage sur le point-virgule seulement : Babelio écrit « Nom,
        // Prénom », et couper sur la virgule inventerait deux auteurs.
        return raw.split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 0 chez Goodreads veut dire « pas noté », pas « zéro étoile ».
    private static func rating(from raw: String?) -> Int? {
        guard let value = raw?.trimmingCharacters(in: .whitespaces),
              let number = Double(value.replacingOccurrences(of: ",", with: ".")),
              number > 0 else { return nil }
        return min(5, max(1, Int(number.rounded())))
    }

    static func status(from raw: String?) -> ReadingStatus {
        let n = fold(raw ?? "")
        // L'ordre compte : « toread » contient « read », et le tester après
        // rangerait toute la pile à lire dans les livres terminés.
        if n.contains("currently") || n.contains("encours") || n.contains("enlecture") {
            return .reading
        }
        if n.contains("toread") || n.contains("alire") || n == "pal" { return .toRead }
        if n.contains("envie") || n.contains("wish") || n.contains("souhait") { return .wishlist }
        if n.contains("read") || n.contains("termine") || n.contains("fini")
            || n == "lu" || n == "dejalu" { return .finished }
        return .toRead
    }

    /// Minuscules, sans accents, sans espaces ni ponctuation : « Nombre de
    /// pages », « nombre_de_pages » et « Number of Pages » doivent se comparer.
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr"))
            .filter { $0.isLetter || $0.isNumber }
    }
}

// MARK: - Correspondance des colonnes

/// Reconnaît les colonnes par leur nom, dans les deux langues.
///
/// Les alias sont classés par priorité et cherchés en égalité exacte, jamais en
/// sous-chaîne : Goodreads exporte à la fois « My Rating » et « Average
/// Rating », et une recherche par sous-chaîne sur « rating » importerait la
/// note moyenne des autres lecteurs à la place de la sienne.
struct ColumnMap {
    enum Field { case title, author, isbn, rating, pages, status, notes }

    private static let aliases: [Field: [String]] = [
        .title:  ["title", "titre", "booktitle", "nom"],
        .author: ["author", "auteur", "auteurs", "authors", "authorlf", "ecrivain"],
        .isbn:   ["isbn13", "isbn", "ean", "code"],
        .rating: ["myrating", "manote", "note", "notation", "rating", "etoiles"],
        .pages:  ["numberofpages", "pages", "nombredepages", "nbpages", "pagecount"],
        .status: ["exclusiveshelf", "etatdelecture", "statut", "etat", "statutdelecture",
                  "bookshelves", "etagere", "shelf"],
        .notes:  ["myreview", "privatenotes", "notes", "commentaire", "critique", "avis"],
    ]

    private var indices: [Field: Int] = [:]

    var title: Int? { indices[.title] }
    var isbn: Int? { indices[.isbn] }

    init(header: [String]) {
        let folded = header.map { LibraryImportService.fold($0) }
        for (field, names) in Self.aliases {
            for name in names {
                if let index = folded.firstIndex(of: name) {
                    indices[field] = index
                    break
                }
            }
        }
    }

    func value(_ field: Field, in row: [String]) -> String? {
        guard let index = indices[field], index < row.count else { return nil }
        let value = row[index]
        return value.isEmpty ? nil : value
    }
}

// MARK: - Lecteur CSV

/// Lecteur RFC 4180 : guillemets, guillemets doublés, séparateurs et retours à
/// la ligne à l'intérieur d'un champ.
///
/// Écrit à la main parce qu'un `split(separator:)` casse sur la première
/// critique Goodreads contenant une virgule — c'est-à-dire à peu près toutes.
enum CSVReader {
    static func rows(from text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while let c = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
                continue
            }
            switch c {
            case "\"": inQuotes = true
            case separator: endField()
            // Swift compte en grappes de graphèmes, et CR LF en est UNE :
            // `Character("\r\n")` n'est égal ni à "\r" ni à "\n". Sans ce cas
            // littéral, un fichier à fins de ligne Windows — c'est-à-dire tout
            // export Goodreads — se lit comme une seule ligne géante, et
            // l'import annonce « 1 livre » sur deux cents.
            case "\n", "\r\n", "\r": endRow()
            default: field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
