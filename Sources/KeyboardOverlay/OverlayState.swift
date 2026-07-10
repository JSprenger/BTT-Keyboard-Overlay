import AppKit
import Combine
import CoreGraphics
import Foundation

/// Was auf einer Taste angezeigt wird und woher es kommt.
struct KeyDisplay {
    enum Source {
        case system  // normales Layout-Zeichen (wie macOS-Tastaturübersicht)
        case btt     // BTT-Ersetzung überschreibt das Systemzeichen
        case none
    }

    let text: String
    let source: Source
    let isDead: Bool

    static let empty = KeyDisplay(text: "", source: .none, isDead: false)
}

@MainActor
final class OverlayState: ObservableObject {
    /// Modifier, die gerade physisch gedrückt sind (vom Event-Tap).
    @Published var hardwareFlags: CGEventFlags = []
    /// Modifier, die per Klick im Overlay „eingerastet“ wurden.
    @Published var stickyFlags: CGEventFlags = []
    /// Gerade physisch gedrückte Tasten (Keycodes).
    @Published var pressedKeys: Set<Int> = []
    /// Zustand einer offenen Akzenttaste (dead key), z. B. nach ´ oder Option+U.
    @Published var liveDeadKeyState: UInt32 = 0
    /// BTT-Ersetzungen: (Keycode, Modifier) → Text.
    @Published var bttReplacements: [BTTShortcut: String] = [:]
    @Published var layoutName: String = ""
    @Published var monitoringActive: Bool = false
    @Published var toast: String?

    let translator = KeyTranslator()
    private var toastTimer: Timer?

    /// Effektive Modifier für die Vorschau: Hardware ∪ angeklickt.
    var displayFlags: CGEventFlags {
        CGEventFlags(rawValue: hardwareFlags.rawValue | stickyFlags.rawValue)
    }

    func isModifierActive(_ flag: CGEventFlags) -> Bool {
        displayFlags.contains(flag)
    }

    // MARK: - Anzeige pro Taste

    func display(forKeyCode keyCode: Int) -> KeyDisplay {
        let flags = displayFlags

        // BTT fängt den Shortcut ab, bevor das Zeichen die App erreicht –
        // also hat die BTT-Ersetzung Vorrang vor dem Layout-Zeichen.
        let shortcut = BTTShortcut(keyCode: keyCode,
                                   modifiers: flags.rawValue & BTTShortcut.relevantModifierMask)
        if let replacement = bttReplacements[shortcut] {
            return KeyDisplay(text: replacement, source: .btt, isDead: false)
        }

        let result = translator.translate(keyCode: keyCode, cgFlags: flags,
                                          deadKeyState: liveDeadKeyState)
        if result.isDead {
            // Akzenttaste: das Akzentzeichen selbst anzeigen (orange markiert),
            // wie es die macOS-Tastaturübersicht macht.
            let accent = translator.translate(keyCode: keyCode, cgFlags: flags,
                                              deadKeyState: 0, ignoreDeadKeys: true).text
            return KeyDisplay(text: presentable(accent), source: .system, isDead: true)
        }

        var text = result.text
        // Steuerzeichen (z. B. mit Ctrl) nicht anzeigen, stattdessen das Basiszeichen.
        if text.unicodeScalars.allSatisfy({ $0.value < 0x20 || $0.value == 0x7F }) {
            let withoutControl = CGEventFlags(rawValue: flags.rawValue & ~CGEventFlags.maskControl.rawValue)
            text = translator.translate(keyCode: keyCode, cgFlags: withoutControl,
                                        deadKeyState: 0).text
            if text.unicodeScalars.allSatisfy({ $0.value < 0x20 || $0.value == 0x7F }) {
                text = ""
            }
        }
        return KeyDisplay(text: presentable(text), source: .system, isDead: false)
    }

    /// Kombinierende Zeichen (z. B. Vektorpfeil U+20D7) auf ◌ setzen,
    /// damit sie sichtbar sind.
    private func presentable(_ text: String) -> String {
        guard text.unicodeScalars.count == 1,
              let scalar = text.unicodeScalars.first else { return text }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .spacingMark:
            return "◌" + text
        default:
            return text
        }
    }

    /// Tooltip mit Unicode-Details.
    func tooltip(for display: KeyDisplay) -> String {
        guard !display.text.isEmpty else { return "" }
        let codes = display.text.unicodeScalars
            .map { scalar -> String in
                let hex = String(format: "U+%04X", scalar.value)
                if let name = scalar.properties.name {
                    return "\(hex) \(name)"
                }
                return hex
            }
            .joined(separator: ", ")
        var lines = ["\(display.text)  –  \(codes)"]
        if display.source == .btt { lines.append("BTT-Ersetzung") }
        if display.isDead { lines.append("Akzenttaste (wartet auf nächste Taste)") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Interaktion

    func keyClicked(_ cap: KeyCap) {
        switch cap.kind {
        case .modifier(let flag):
            stickyFlags = CGEventFlags(rawValue: stickyFlags.rawValue ^ flag.rawValue)
        case .character, .isoEnter:
            let current = display(forKeyCode: cap.keyCode)
            if current.isDead {
                // Wie in der echten Tastaturübersicht: Klick auf Akzenttaste
                // aktiviert den Akzent-Zustand für die Vorschau.
                let result = translator.translate(keyCode: cap.keyCode, cgFlags: displayFlags,
                                                  deadKeyState: liveDeadKeyState)
                liveDeadKeyState = result.deadKeyState
            } else if !current.text.isEmpty {
                copyToClipboard(current.text)
                liveDeadKeyState = 0
            }
        case .special, .fkey:
            if cap.keyCode == 53 {  // esc bricht den Akzent-Zustand ab
                liveDeadKeyState = 0
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showToast("„\(text)“ kopiert")
    }

    func showToast(_ message: String) {
        toast = message
        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.toast = nil }
        }
    }

    // MARK: - Ereignisse vom Event-Tap

    func handleFlagsChanged(_ flags: CGEventFlags) {
        hardwareFlags = CGEventFlags(rawValue: flags.rawValue & BTTShortcut.relevantModifierMask
            | flags.rawValue & CGEventFlags.maskAlphaShift.rawValue)
    }

    func handleKey(keyCode: Int, isDown: Bool, flags: CGEventFlags) {
        if isDown {
            pressedKeys.insert(keyCode)
            trackDeadKeyState(keyCode: keyCode, flags: flags)
        } else {
            pressedKeys.remove(keyCode)
        }
    }

    /// Akzent-Zustand mitverfolgen, damit das Overlay nach ´, ˆ usw. die
    /// komponierten Zeichen zeigt – wie die Original-Tastaturübersicht.
    private func trackDeadKeyState(keyCode: Int, flags: CGEventFlags) {
        // Wenn BTT den Shortcut abfängt, erreicht er das Textsystem nie:
        // Akzent-Zustand bleibt unverändert.
        let shortcut = BTTShortcut(keyCode: keyCode,
                                   modifiers: flags.rawValue & BTTShortcut.relevantModifierMask)
        guard bttReplacements[shortcut] == nil else { return }

        let result = translator.translate(keyCode: keyCode, cgFlags: flags,
                                          deadKeyState: liveDeadKeyState)
        liveDeadKeyState = result.deadKeyState
    }
}
