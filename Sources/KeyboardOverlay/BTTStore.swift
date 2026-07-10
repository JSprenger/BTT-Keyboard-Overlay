import Foundation
import SQLite3

/// Ein Tastenkürzel, wie BTT es speichert: virtueller Keycode + Modifier-Flags
/// (CGEventFlags-Bits, inkl. Fn = 0x800000).
struct BTTShortcut: Hashable {
    let keyCode: Int
    let modifiers: UInt64

    /// Nur diese Modifier-Bits sind für den Vergleich relevant.
    static let relevantModifierMask: UInt64 = 0x0002_0000  // Shift
        | 0x0004_0000  // Control
        | 0x0008_0000  // Option
        | 0x0010_0000  // Command
        | 0x0080_0000  // Fn
}

/// Liest die in BetterTouchTool gespeicherten Text-Ersetzungen
/// (Aktion „Text eingeben/einfügen“, BTTActionTextToPaste) aus dem
/// Core-Data-SQLite-Store von BTT.
enum BTTStore {

    static var dataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BetterTouchTool", isDirectory: true)
    }

    /// Neueste btt_data_store-Datei finden (BTT hängt die Versionsnummer an den Namen an).
    static func currentStoreURL() -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dataDirectory,
                                                        includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return nil
        }
        let candidates = entries.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("btt_data_store")
                && !name.contains("tmp_backup")
                && !name.hasSuffix("-wal")
                && !name.hasSuffix("-shm")
        }
        return candidates.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
    }

    /// Alle aktiven Tastatur-Trigger mit Einfüge-Text laden.
    static func loadReplacements() -> [BTTShortcut: String] {
        guard let storeURL = currentStoreURL(),
              let workingCopy = makeWorkingCopy(of: storeURL) else {
            return [:]
        }
        defer { try? FileManager.default.removeItem(at: workingCopy.deletingLastPathComponent()) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(workingCopy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return [:]
        }
        defer { sqlite3_close(db) }

        guard let gestureEnt = entityNumber(db: db, name: "Gesture") else { return [:] }

        struct Row {
            let pk: Int64
            let parent: Int64?
            let keyCode: Int
            let modifiers: Int64
            let enabled: Bool
            let actionData: Data?
        }

        var rows: [Int64: Row] = [:]
        let sql = """
            SELECT Z_PK, ZPARENT, ZKEYCODE, ZMODIFIERKEYS, ZENABLEDNEW, ZACTIONDATA
            FROM ZBTTBASEENTITY WHERE Z_ENT = ?
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, gestureEnt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let pk = sqlite3_column_int64(stmt, 0)
            let parent: Int64? = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 1)
            let keyCode = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? -1 : Int(sqlite3_column_int64(stmt, 2))
            let modifiers = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? -1 : sqlite3_column_int64(stmt, 3)
            let enabled = sqlite3_column_type(stmt, 4) == SQLITE_NULL || sqlite3_column_int64(stmt, 4) != 0
            var actionData: Data?
            if sqlite3_column_type(stmt, 5) != SQLITE_NULL, let blob = sqlite3_column_blob(stmt, 5) {
                actionData = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 5)))
            }
            rows[pk] = Row(pk: pk, parent: parent, keyCode: keyCode, modifiers: modifiers,
                           enabled: enabled, actionData: actionData)
        }

        var result: [BTTShortcut: String] = [:]
        for row in rows.values {
            guard row.enabled,
                  let data = row.actionData,
                  let text = pasteText(fromActionData: data), !text.isEmpty else { continue }

            // Keycode/Modifier stehen entweder am Trigger selbst oder –
            // bei als Kind-Aktion gespeicherten Einfügungen – am Parent.
            var keyCode = row.keyCode
            var modifiers = row.modifiers
            if keyCode < 0, let parentPK = row.parent, let parent = rows[parentPK] {
                guard parent.enabled else { continue }
                keyCode = parent.keyCode
                modifiers = parent.modifiers
            }
            guard keyCode >= 0, modifiers >= 0 else { continue }

            let shortcut = BTTShortcut(keyCode: keyCode,
                                       modifiers: UInt64(modifiers) & BTTShortcut.relevantModifierMask)
            result[shortcut] = text
        }
        return result
    }

    // MARK: - Hilfen

    /// BTT hält die DB offen (WAL-Modus). Wir kopieren db+wal+shm in ein
    /// Temp-Verzeichnis und lesen die Kopie, um Locking-Konflikte zu vermeiden.
    private static func makeWorkingCopy(of storeURL: URL) -> URL? {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("btt-overlay-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            let dest = tmpDir.appendingPathComponent("store.sqlite")
            try fm.copyItem(at: storeURL, to: dest)
            for suffix in ["-wal", "-shm"] {
                let side = URL(fileURLWithPath: storeURL.path + suffix)
                if fm.fileExists(atPath: side.path) {
                    try? fm.copyItem(at: side, to: URL(fileURLWithPath: dest.path + suffix))
                }
            }
            return dest
        } catch {
            try? fm.removeItem(at: tmpDir)
            return nil
        }
    }

    private static func entityNumber(db: OpaquePointer, name: String) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = ?", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, name, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    /// ZACTIONDATA ist JSON; der Einfüge-Text steckt in "BTTActionTextToPaste"
    /// und liegt in einem von drei Formaten vor:
    ///   1. Klartext
    ///   2. RTF (beginnt mit "{\rtf")
    ///   3. Base64-kodiertes NSArchiver-"streamtyped"-Archiv (NSTextStorage)
    static func pasteText(fromActionData data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["BTTActionTextToPaste"] as? String else {
            return nil
        }
        if raw.hasPrefix("{\\rtf") {
            if let rtfData = raw.data(using: .utf8),
               let attributed = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
                return attributed.string.trimmingCharacters(in: .newlines)
            }
            return nil
        }
        // BTT nutzt Base64 mit '_' (und teils '-') statt '/' und '+'.
        let normalized = raw
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "-", with: "+")
        if let decoded = Data(base64Encoded: normalized),
           decoded.starts(with: [0x04, 0x0B]),  // "streamtyped"-Magic
           let text = streamtypedString(from: decoded) {
            return text
        }
        return raw
    }

    /// Minimaler Parser für NSArchiver-"streamtyped"-Daten: extrahiert den
    /// ersten NSString-Inhalt (bei NSTextStorage ist das der eigentliche Text).
    /// Muster: 0x84 0x01 '+' <Länge> <UTF-8-Bytes>
    static func streamtypedString(from data: Data) -> String? {
        let bytes = [UInt8](data)
        var i = 0
        while i + 3 < bytes.count {
            if bytes[i] == 0x84, bytes[i + 1] == 0x01, bytes[i + 2] == UInt8(ascii: "+") {
                var j = i + 3
                let first = bytes[j]
                var length = 0
                if first <= 0x7F {
                    length = Int(first)
                    j += 1
                } else if first == 0x81, j + 2 < bytes.count {
                    length = Int(bytes[j + 1]) | (Int(bytes[j + 2]) << 8)
                    j += 3
                } else if first == 0x82, j + 4 < bytes.count {
                    length = Int(bytes[j + 1]) | (Int(bytes[j + 2]) << 8)
                        | (Int(bytes[j + 3]) << 16) | (Int(bytes[j + 4]) << 24)
                    j += 5
                } else {
                    i += 1
                    continue
                }
                guard length > 0, j + length <= bytes.count else { return nil }
                return String(bytes: bytes[j..<(j + length)], encoding: .utf8)
            }
            i += 1
        }
        return nil
    }
}
