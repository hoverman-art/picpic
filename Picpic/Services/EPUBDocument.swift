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
}

nonisolated struct EPUBDocument: Sendable {

    let title: String
    let author: String?
    let chapters: [EPUBChapter]

    private let archive: ZIPArchive
    /// Dossier de l'OPF : les chemins du manifeste en sont relatifs.
    private let rootPath: String

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
        var chapters: [EPUBChapter] = []
        for (index, idref) in spine.enumerated() {
            guard let href = manifest[idref] else { continue }
            let path = Self.resolve(href, relativeTo: rootPath)
            // Un vrai titre plutôt que « Chapitre 3 » : le premier titre du
            // document, à défaut son <title>, à défaut le rang.
            let raw = (try? archive.string(for: path)) ?? nil
            chapters.append(EPUBChapter(
                id: idref,
                title: raw.flatMap(Self.headingTitle) ?? "Chapitre \(index + 1)",
                path: path
            ))
        }
        guard !chapters.isEmpty else { throw Failure.noChapters }
        self.chapters = chapters
    }

    /// Le XHTML d'un chapitre, prêt à être affiché.
    func html(for chapter: EPUBChapter) throws -> String? {
        guard let raw = try archive.string(for: chapter.path) else { return nil }
        return inliningImages(in: Self.bodyContent(of: raw), chapterPath: chapter.path)
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
