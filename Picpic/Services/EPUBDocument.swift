//
//  EPUBDocument.swift
//  Picpic
//
//  Ouvre un EPUB téléchargé et en sort ce qu'il faut pour le lire :
//  le titre, l'auteur, et les chapitres dans l'ordre du livre.
//
//  Chemin normalisé d'un EPUB :
//    META-INF/container.xml  → où est le fichier OPF
//    <...>.opf               → métadonnées, manifeste (les fichiers) et
//                              « spine » (l'ordre de lecture)
//    chaque chapitre          → un XHTML du manifeste
//

import Foundation

nonisolated struct EPUBChapter: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Chemin de la ressource dans l'archive.
    let path: String
    /// Rang du morceau quand le fichier a été redécoupé sur ses titres.
    /// `nil` = le fichier entier est le chapitre.
    var segment: Int?
}

nonisolated struct EPUBDocument: Sendable {

    let title: String
    let author: String?
    let chapters: [EPUBChapter]

    private let archive: ZIPArchive
    /// Dossier de l'OPF : les chemins du manifeste en sont relatifs.
    private let rootPath: String
    /// Morceaux déjà découpés, par chemin de fichier.
    private let segments: [String: [String]]

    enum Failure: LocalizedError {
        case noContainer
        case noPackage
        case noChapters

        var errorDescription: String? {
            switch self {
            case .noContainer, .noPackage:
                return "Cet EPUB a une structure inattendue et ne peut pas être ouvert."
            case .noChapters:
                return "Cet EPUB ne contient aucun chapitre lisible."
            }
        }
    }

    init(data: Data) throws {
        archive = try ZIPArchive(data: data)

        guard let container = try archive.string(for: "META-INF/container.xml"),
              let opfPath = Self.attribute("full-path", inTag: "rootfile", of: container) else {
            throw Failure.noContainer
        }
        guard let package = try archive.string(for: opfPath) else { throw Failure.noPackage }

        rootPath = (opfPath as NSString).deletingLastPathComponent
        title = Self.text(inTag: "dc:title", of: package)
            ?? Self.text(inTag: "title", of: package)
            ?? "Livre"
        author = Self.text(inTag: "dc:creator", of: package) ?? Self.text(inTag: "creator", of: package)

        let manifest = Self.manifest(from: package)
        let spine = Self.spine(from: package)

        // Le spine donne l'ordre de lecture ; le manifeste donne les chemins.
        //
        // Il ne donne pas les chapitres pour autant : un EPUB du Projet
        // Gutenberg tient tout le roman dans UN fichier, et « Le Fantôme de
        // l'Opéra » s'ouvrait donc en six pages — couverture, titre, le livre
        // entier d'un bloc, puis la licence en anglais. Impossible d'avancer,
        // impossible de reprendre où l'on en était. On redécoupe ces gros
        // fichiers sur leurs propres titres.
        var chapters: [EPUBChapter] = []
        var segments: [String: [String]] = [:]
        var firstWithText: Int?
        for (index, idref) in spine.enumerated() {
            guard let href = manifest[idref] else { continue }
            let path = Self.resolve(href, relativeTo: rootPath)
            guard let raw = (try? archive.string(for: path)) ?? nil else { continue }
            let body = Self.bodyContent(of: raw)

            // Le fichier est d'abord redécoupé, ensuite seulement filtré : chez
            // le Projet Gutenberg, l'en-tête anglais et les neuf premiers
            // chapitres du roman vivent dans LE MÊME fichier. Jeter le fichier
            // entier parce qu'il commence par la licence amputait le livre —
            // constaté sur « Le Fantôme de l'Opéra », qui s'ouvrait alors au
            // chapitre X.
            let kept = Self.split(body).filter { !Self.isBoilerplate($0.html) }
            guard !kept.isEmpty else { continue }

            segments[path] = kept.map(\.html)
            for (rank, piece) in kept.enumerated() {
                if firstWithText == nil, piece.html.count > 1_500 {
                    firstWithText = chapters.count
                }
                chapters.append(EPUBChapter(
                    id: kept.count > 1 ? "\(idref)#\(rank)" : idref,
                    title: piece.title
                        ?? Self.headingTitle(raw)
                        ?? "Chapitre \(index + 1)",
                    path: path,
                    segment: rank
                ))
            }
        }
        guard !chapters.isEmpty else { throw Failure.noChapters }
        self.chapters = chapters
        self.segments = segments
        self.firstReadableChapter = firstWithText ?? 0
    }

    /// Le premier chapitre qui a du texte : sur quoi ouvrir quand on n'a pas
    /// encore lu. Sans ça, le livre s'ouvrait sur sa couverture et on pouvait
    /// croire qu'il ne s'était pas chargé.
    ///
    /// Calculé une fois à l'ouverture, avec le texte qu'on vient déjà de
    /// parcourir : le déduire en rappelant `readable` sur chaque chapitre
    /// remettait l'inlining des images et le marquage des paragraphes sur le
    /// fil principal, et l'écran restait sur « Téléchargement du livre… ».
    let firstReadableChapter: Int

    /// Le XHTML d'un chapitre, prêt à être affiché.
    func html(for chapter: EPUBChapter) throws -> String? {
        try readable(chapter)?.html
    }

    /// Le chapitre découpé pour la lecture à voix haute : le HTML dont chaque
    /// bloc porte un `data-pp`, et le texte de ces blocs dans le même ordre.
    /// Les deux tableaux sont alignés par indice — c'est ce qui permet de
    /// surligner le paragraphe qu'on entend.
    func readable(_ chapter: EPUBChapter) throws -> (html: String, paragraphs: [String])? {
        let source: String
        if let segment = chapter.segment, let pieces = segments[chapter.path],
           pieces.indices.contains(segment) {
            source = pieces[segment]
        } else {
            guard let raw = try archive.string(for: chapter.path) else { return nil }
            source = Self.bodyContent(of: raw)
        }
        let body = Self.strippingScripts(source)
        let inlined = inliningImages(in: body, chapterPath: chapter.path)
        return Self.markingParagraphs(in: inlined)
    }

    // MARK: - Découpage d'un gros fichier en chapitres

    /// Un morceau de fichier : son titre s'il en a un, et son HTML.
    private struct Piece { let title: String?; let html: String }

    /// Titres sur lesquels un livre se découpe. `h1` d'abord : si le fichier
    /// n'en a pas assez, on descend d'un cran plutôt que de renvoyer un pavé.
    ///
    /// `h4` en fait partie parce que c'est ce qu'utilise le Projet Gutenberg :
    /// « Le Fantôme de l'Opéra » place ses chapitres en `h4`, ses deux `h2`
    /// servant à l'en-tête du fichier. S'arrêter à `h3` laissait le roman en
    /// un seul bloc.
    private static let splitTags = ["h1", "h2", "h3", "h4"]

    /// Redécoupe le corps d'un fichier sur ses titres.
    ///
    /// Ne découpe que ce qui le mérite : un fichier court est déjà un
    /// chapitre, et le fractionner ferait une table des matières de vingt
    /// lignes pour trois pages de texte.
    private static func split(_ body: String) -> [Piece] {
        // On mesure le HTML brut, pas le texte : `strippingTags` parcourt la
        // chaîne caractère par caractère, ce qui coûte des secondes sur un
        // roman entier en build de débogage — l'écran restait sur
        // « Téléchargement du livre… » alors que le fichier était là.
        guard body.count > 20_000 else { return [Piece(title: nil, html: body)] }

        for tag in splitTags {
            let starts = headingStarts(of: tag, in: body)
            guard starts.count >= 3 else { continue }

            var pieces: [Piece] = []
            // Ce qui précède le premier titre (dédicace, exergue) reste avec lui.
            for (rank, start) in starts.enumerated() {
                let from = rank == 0 ? body.startIndex : start
                let to = rank + 1 < starts.count ? starts[rank + 1] : body.endIndex
                let html = String(body[from ..< to])
                pieces.append(Piece(title: headingTitle(html), html: html))
            }
            return pieces
        }
        return [Piece(title: nil, html: body)]
    }

    /// Position de chaque `<tag …>` d'ouverture, dans l'ordre.
    private static func headingStarts(of tag: String, in html: String) -> [String.Index] {
        var starts: [String.Index] = []
        var cursor = html.startIndex
        while let open = html.range(of: "<\(tag)", options: .caseInsensitive,
                                   range: cursor ..< html.endIndex) {
            let after = open.upperBound
            // `<h1` ne doit pas capturer `<h1x` : il faut un délimiteur.
            if after < html.endIndex, let scalar = html[after].unicodeScalars.first,
               CharacterSet.alphanumerics.contains(scalar) {
                cursor = after
                continue
            }
            starts.append(open.lowerBound)
            cursor = after
        }
        return starts
    }

    /// La licence du Projet Gutenberg, présente dans tous ses EPUB, en
    /// anglais et sans intérêt pour le lecteur.
    private static func isBoilerplate(_ body: String) -> Bool {
        guard body.count > 800 else { return false }
        // Recherche sur le HTML brut : les marqueurs de la licence ne sont
        // jamais coupés par une balise, et parcourir le texte nettoyé coûterait
        // un balayage de plus par fichier.
        func has(_ needle: String) -> Bool {
            body.range(of: needle, options: .caseInsensitive) != nil
        }
        return has("START: FULL LICENSE")
            || has("THE FULL PROJECT GUTENBERG LICENSE")
            || (has("PROJECT GUTENBERG") && has("Section 1."))
            // L'en-tête, en anglais lui aussi : titre, licence, date de mise
            // en ligne, encodage. Le livre s'ouvrait dessus.
            || has("This eBook is for the use of anyone anywhere")
            || (has("Release date:") && has("Language:") && has("Credits:"))
    }

    /// Retire les scripts de l'EPUB. La liseuse exécute son propre script pour
    /// surligner ce qui est lu ; hors de question de laisser tourner en plus
    /// celui d'un fichier venu du web.
    private static func strippingScripts(_ html: String) -> String {
        var result = ""
        var rest = Substring(html)
        while let open = rest.range(of: "<script", options: .caseInsensitive) {
            result += rest[rest.startIndex ..< open.lowerBound]
            guard let close = rest.range(of: "</script>", options: .caseInsensitive,
                                         range: open.upperBound ..< rest.endIndex) else {
                return result
            }
            rest = rest[close.upperBound...]
        }
        result += rest
        // Et les gestionnaires en attribut (`onclick="…"`), même raison.
        return result.replacingOccurrences(
            of: "\\son[a-z]+\\s*=\\s*\"[^\"]*\"",
            with: "", options: [.regularExpression, .caseInsensitive])
    }

    /// Balises de bloc dont le texte forme une unité de lecture.
    private static let blockTags = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "li"]

    private static func markingParagraphs(in html: String) -> (html: String, paragraphs: [String]) {
        var output = ""
        var paragraphs: [String] = []
        var cursor = html.startIndex

        while cursor < html.endIndex {
            guard let (tagName, open, openEnd) = nextBlockTag(in: html, from: cursor) else {
                output += html[cursor...]
                break
            }
            guard let close = matchingClose(of: tagName, in: html, after: openEnd) else {
                output += html[cursor ..< openEnd]
                cursor = openEnd
                continue
            }

            let inner = String(html[openEnd ..< close.lowerBound])
            let text = strippingTags(inner)
            output += html[cursor ..< open.lowerBound]

            if text.count >= 2 {
                // On insère le marqueur juste après le nom de la balise, ce qui
                // préserve les attributs déjà présents.
                let openTag = String(html[open.lowerBound ..< openEnd])
                let marked = openTag.replacingOccurrences(
                    of: "<\(tagName)", with: "<\(tagName) data-pp=\"\(paragraphs.count)\"",
                    options: .caseInsensitive, range: openTag.range(of: "<\(tagName)", options: .caseInsensitive))
                output += marked
                paragraphs.append(text)
            } else {
                output += html[open.lowerBound ..< openEnd]
            }
            output += html[openEnd ..< close.lowerBound]
            output += html[close.lowerBound ..< close.upperBound]
            cursor = close.upperBound
        }
        return (output, paragraphs)
    }

    private static func nextBlockTag(
        in html: String, from index: String.Index
    ) -> (name: String, open: Range<String.Index>, contentStart: String.Index)? {
        var best: (String, Range<String.Index>, String.Index)?
        for tag in blockTags {
            var searchFrom = index
            // `<p` ne doit pas capturer `<param` : on exige un délimiteur après.
            while let open = html.range(of: "<\(tag)", options: .caseInsensitive,
                                        range: searchFrom ..< html.endIndex) {
                let after = open.upperBound
                if after < html.endIndex, let scalar = html[after].unicodeScalars.first,
                   CharacterSet.alphanumerics.contains(scalar) {
                    searchFrom = after
                    continue
                }
                guard let end = html.range(of: ">", range: after ..< html.endIndex) else { break }
                if best == nil || open.lowerBound < best!.1.lowerBound {
                    best = (tag, open, end.upperBound)
                }
                break
            }
        }
        return best.map { (name: $0.0, open: $0.1, contentStart: $0.2) }
    }

    /// Balise fermante correspondante, en tenant compte des imbrications
    /// (`<li>` dans `<li>`).
    private static func matchingClose(
        of tag: String, in html: String, after index: String.Index
    ) -> Range<String.Index>? {
        var depth = 1
        var cursor = index
        while cursor < html.endIndex {
            let nextOpen = html.range(of: "<\(tag)", options: .caseInsensitive, range: cursor ..< html.endIndex)
            guard let nextClose = html.range(of: "</\(tag)>", options: .caseInsensitive,
                                             range: cursor ..< html.endIndex) else { return nil }
            if let nextOpen, nextOpen.lowerBound < nextClose.lowerBound {
                depth += 1
                cursor = nextOpen.upperBound
                continue
            }
            depth -= 1
            if depth == 0 { return nextClose }
            cursor = nextClose.upperBound
        }
        return nil
    }

    /// Remplace les images relatives par leur contenu en `data:`.
    ///
    /// La liseuse affiche le chapitre sans URL de base : une couverture
    /// (`<img src="cover.jpg">`, ou un `<image xlink:href>` dans un SVG comme
    /// en produit Gutenberg) donnerait sinon une page blanche.
    private func inliningImages(in html: String, chapterPath: String) -> String {
        let directory = (chapterPath as NSString).deletingLastPathComponent
        var result = html
        for attribute in ["src", "xlink:href", "href"] {
            for reference in Self.attributeValues(attribute, in: result) {
                guard !reference.hasPrefix("data:"),
                      !reference.hasPrefix("http"),
                      !reference.hasPrefix("#"),
                      let mime = Self.imageMIME(for: reference) else { continue }
                let resolved = Self.normalize(Self.resolve(
                    reference.removingPercentEncoding ?? reference, relativeTo: directory))
                guard let bytes = try? archive.data(for: resolved), !bytes.isEmpty else { continue }
                result = result.replacingOccurrences(
                    of: "\(attribute)=\"\(reference)\"",
                    with: "\(attribute)=\"data:\(mime);base64,\(bytes.base64EncodedString())\""
                )
            }
        }
        return result
    }

    private static func attributeValues(_ name: String, in html: String) -> Set<String> {
        var values: Set<String> = []
        var cursor = html.startIndex
        let pattern = "\(name)=\""
        while let start = html.range(of: pattern, range: cursor ..< html.endIndex) {
            guard let end = html.range(of: "\"", range: start.upperBound ..< html.endIndex) else { break }
            values.insert(String(html[start.upperBound ..< end.lowerBound]))
            cursor = end.upperBound
        }
        return values
    }

    private static func imageMIME(for path: String) -> String? {
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "webp": return "image/webp"
        default: return nil
        }
    }

    /// Résout les « ../ » : un chapitre dans `text/` référence souvent
    /// `../images/cover.jpg`.
    private static func normalize(_ path: String) -> String {
        var components: [String] = []
        for part in path.components(separatedBy: "/") {
            switch part {
            case "", ".": continue
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(part)
            }
        }
        return components.joined(separator: "/")
    }

    /// Premier titre du document, nettoyé.
    private static func headingTitle(_ html: String) -> String? {
        for tag in ["h1", "h2", "h3", "title"] {
            guard let value = text(inTag: tag, of: html) else { continue }
            let cleaned = strippingTags(value)
            if !cleaned.isEmpty, cleaned.count <= 90 { return cleaned }
        }
        return nil
    }

    /// Premier paragraphe d'un chapitre, pour la table des matières.
    /// Volontairement sans passer par `html(for:)` : encoder les images en
    /// base64 pour chaque ligne d'une table des matières serait ruineux.
    func excerpt(for chapter: EPUBChapter) -> String? {
        guard let raw = (try? archive.string(for: chapter.path)) ?? nil else { return nil }
        let text = Self.strippingTags(Self.bodyContent(of: raw))
        return text.isEmpty ? nil : String(text.prefix(90))
    }

    // MARK: - OPF

    private static func manifest(from package: String) -> [String: String] {
        var result: [String: String] = [:]
        for item in tags(named: "item", in: package) {
            guard let id = attribute("id", in: item), let href = attribute("href", in: item) else { continue }
            result[id] = href.removingPercentEncoding ?? href
        }
        return result
    }

    private static func spine(from package: String) -> [String] {
        // Ne garder que le spine : le manifeste contient aussi les images,
        // les CSS et la couverture, qui ne sont pas des chapitres.
        guard let spineBlock = block(named: "spine", in: package) else { return [] }
        return tags(named: "itemref", in: spineBlock).compactMap { attribute("idref", in: $0) }
    }

    /// « OEBPS/text/ch1.xhtml » à partir de « text/ch1.xhtml » et de « OEBPS ».
    private static func resolve(_ href: String, relativeTo root: String) -> String {
        guard !root.isEmpty else { return href }
        return (root as NSString).appendingPathComponent(href)
    }

    // MARK: - Analyse XML au fil du texte
    //
    // Les EPUB du domaine public sont souvent mal formés (entités inconnues,
    // balises non fermées) : XMLParser s'y arrête, une lecture tolérante non.

    private static func block(named name: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(name)", options: .caseInsensitive),
              let close = xml.range(of: "</\(name)>", options: .caseInsensitive, range: open.upperBound ..< xml.endIndex)
        else { return nil }
        return String(xml[open.lowerBound ..< close.lowerBound])
    }

    private static func tags(named name: String, in xml: String) -> [String] {
        var tags: [String] = []
        var cursor = xml.startIndex
        while let open = xml.range(of: "<\(name)", options: .caseInsensitive, range: cursor ..< xml.endIndex) {
            guard let end = xml.range(of: ">", range: open.upperBound ..< xml.endIndex) else { break }
            tags.append(String(xml[open.lowerBound ..< end.upperBound]))
            cursor = end.upperBound
        }
        return tags
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        for quote in ["\"", "'"] {
            let pattern = "\(name)=\(quote)"
            if let start = tag.range(of: pattern, options: .caseInsensitive),
               let end = tag.range(of: quote, range: start.upperBound ..< tag.endIndex) {
                return String(tag[start.upperBound ..< end.lowerBound])
            }
        }
        return nil
    }

    private static func attribute(_ name: String, inTag tagName: String, of xml: String) -> String? {
        tags(named: tagName, in: xml).compactMap { attribute(name, in: $0) }.first
    }

    private static func text(inTag name: String, of xml: String) -> String? {
        guard let open = xml.range(of: "<\(name)", options: .caseInsensitive),
              let openEnd = xml.range(of: ">", range: open.upperBound ..< xml.endIndex),
              let close = xml.range(of: "</\(name)>", options: .caseInsensitive, range: openEnd.upperBound ..< xml.endIndex)
        else { return nil }
        let value = String(xml[openEnd.upperBound ..< close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : decodingEntities(value)
    }

    /// Ne garder que l'intérieur de `<body>` : le `<head>` du chapitre porte
    /// des feuilles de style qui écraseraient celle de la liseuse.
    private static func bodyContent(of html: String) -> String {
        guard let open = html.range(of: "<body", options: .caseInsensitive),
              let openEnd = html.range(of: ">", range: open.upperBound ..< html.endIndex),
              let close = html.range(of: "</body>", options: .caseInsensitive, range: openEnd.upperBound ..< html.endIndex)
        else { return html }
        return String(html[openEnd.upperBound ..< close.lowerBound])
    }

    private static func strippingTags(_ html: String) -> String {
        var text = ""
        var insideTag = false
        for character in html {
            switch character {
            case "<": insideTag = true
            case ">": insideTag = false
            default: if !insideTag { text.append(character) }
            }
        }
        return decodingEntities(text)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodingEntities(_ text: String) -> String {
        var result = text
        for (entity, character) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                    ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
                                    ("&nbsp;", "\u{00A0}")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}
