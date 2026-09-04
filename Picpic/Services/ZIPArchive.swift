//
//  ZIPArchive.swift
//  Picpic
//
//  Lecteur ZIP minimal, juste ce qu'il faut pour ouvrir un EPUB.
//
//  Un EPUB est une archive ZIP dont les entrées sont soit stockées telles
//  quelles (méthode 0), soit compressées en DEFLATE (méthode 8). Foundation ne
//  sait pas lire un ZIP, mais `Compression` sait inflater du DEFLATE brut : le
//  reste n'est que de la lecture d'en-têtes. Écrire ces ~150 lignes évite
//  d'ajouter une dépendance à une app qui n'en a qu'une.
//
//  Référence : APPNOTE.TXT (PKWARE), sections 4.3.6 à 4.4.
//

import Foundation
import Compression

nonisolated struct ZIPArchive {

    enum Failure: LocalizedError {
        case notAZipFile
        case corrupted
        case unsupportedCompression(UInt16)

        var errorDescription: String? {
            switch self {
            case .notAZipFile: return "Ce fichier n'est pas un EPUB valide."
            case .corrupted: return "L'EPUB est incomplet ou abîmé."
            case .unsupportedCompression: return "Cet EPUB utilise une compression non prise en charge."
            }
        }
    }

    private struct Entry {
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    private let entries: [String: Entry]

    /// Les chemins contenus dans l'archive.
    var paths: [String] { Array(entries.keys) }

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    /// Contenu décompressé d'une entrée, ou nil si le chemin n'existe pas.
    func data(for path: String) throws -> Data? {
        guard let entry = entries[path] else { return nil }

        // L'en-tête local répète le nom et les extras, avec des longueurs qui
        // peuvent différer de celles du répertoire central : c'est lui qui dit
        // où commencent vraiment les octets.
        let header = entry.localHeaderOffset
        guard data.count >= header + 30,
              read32(at: header) == 0x0403_4b50 else { throw Failure.corrupted }
        let nameLength = Int(read16(at: header + 26))
        let extraLength = Int(read16(at: header + 28))
        let start = header + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw Failure.corrupted }
        let payload = data.subdata(in: start ..< start + entry.compressedSize)

        switch entry.compressionMethod {
        case 0:
            return payload
        case 8:
            return try inflate(payload, expectedSize: entry.uncompressedSize)
        default:
            throw Failure.unsupportedCompression(entry.compressionMethod)
        }
    }

    /// Contenu d'une entrée décodé en texte (UTF-8, repli Latin-1).
    func string(for path: String) throws -> String? {
        guard let raw = try data(for: path) else { return nil }
        return String(data: raw, encoding: .utf8) ?? String(data: raw, encoding: .isoLatin1)
    }

    // MARK: - Répertoire central

    private static func readCentralDirectory(_ data: Data) throws -> [String: Entry] {
        // L'EOCD est en fin de fichier, précédé d'un commentaire de taille
        // variable (≤ 64 Kio) : on remonte depuis la fin jusqu'à sa signature.
        let minimumEOCD = 22
        guard data.count >= minimumEOCD else { throw Failure.notAZipFile }
        let searchFloor = max(0, data.count - minimumEOCD - 65_535)
        var eocd: Int?
        var index = data.count - minimumEOCD
        while index >= searchFloor {
            if read32(data, at: index) == 0x0605_4b50 { eocd = index; break }
            index -= 1
        }
        guard let eocd else { throw Failure.notAZipFile }

        let entryCount = Int(read16(data, at: eocd + 10))
        var offset = Int(read32(data, at: eocd + 16))

        var entries: [String: Entry] = [:]
        for _ in 0 ..< entryCount {
            guard offset + 46 <= data.count,
                  read32(data, at: offset) == 0x0201_4b50 else { throw Failure.corrupted }
            let method = read16(data, at: offset + 10)
            let compressed = Int(read32(data, at: offset + 20))
            let uncompressed = Int(read32(data, at: offset + 24))
            let nameLength = Int(read16(data, at: offset + 28))
            let extraLength = Int(read16(data, at: offset + 30))
            let commentLength = Int(read16(data, at: offset + 32))
            let localOffset = Int(read32(data, at: offset + 42))

            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else { throw Failure.corrupted }
            let nameData = data.subdata(in: nameStart ..< nameStart + nameLength)
            if let name = String(data: nameData, encoding: .utf8) {
                entries[name] = Entry(
                    compressionMethod: method,
                    compressedSize: compressed,
                    uncompressedSize: uncompressed,
                    localHeaderOffset: localOffset
                )
            }
            offset = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    // MARK: - DEFLATE

    private func inflate(_ payload: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        // `COMPRESSION_ZLIB` décode du DEFLATE brut (RFC 1951), qui est
        // exactement ce que stocke un ZIP — sans en-tête zlib.
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return payload.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase, expectedSize,
                    sourceBase, payload.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw Failure.corrupted }
        return written == expectedSize ? output : output.prefix(written)
    }

    // MARK: - Lecture d'entiers petit-boutiens

    private func read16(at offset: Int) -> UInt16 { Self.read16(data, at: offset) }
    private func read32(at offset: Int) -> UInt32 { Self.read32(data, at: offset) }

    private static func read16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[data.startIndex + offset])
            | UInt16(data[data.startIndex + offset + 1]) << 8
    }

    private static func read32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[data.startIndex + offset])
            | UInt32(data[data.startIndex + offset + 1]) << 8
            | UInt32(data[data.startIndex + offset + 2]) << 16
            | UInt32(data[data.startIndex + offset + 3]) << 24
    }
}
