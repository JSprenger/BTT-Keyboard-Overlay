import CoreGraphics
import Foundation

/// Eine Taste auf der physischen Tastatur. Koordinaten in „Units“
/// (1 Unit = Breite einer normalen Taste), Ursprung oben links.
struct KeyCap: Identifiable {
    enum Kind {
        /// Zeichentaste – Beschriftung kommt aus UCKeyTranslate bzw. BTT.
        case character
        /// Modifier-Taste; klickbar zum Ein-/Ausschalten in der Vorschau.
        case modifier(CGEventFlags)
        /// Feste Beschriftung (esc, ⌫, ⇥, Pfeile …).
        case special(String)
        /// Funktionstaste F1–F12: zeigt Mediensymbol, mit Fn die F-Nummer.
        case fkey(Int)
        /// ISO-Enter (L-Form über zwei Reihen).
        case isoEnter
    }

    let id: String
    let keyCode: Int
    let kind: Kind
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
}

/// SF-Symbol-Namen der F-Reihe eines aktuellen Apple-Keyboards (F1–F12).
let fRowMediaSymbols = [
    "sun.min", "sun.max", "rectangle.3.group", "magnifyingglass",
    "mic", "moon.fill", "backward.fill", "playpause.fill",
    "forward.fill", "speaker.slash.fill", "speaker.wave.1.fill", "speaker.wave.3.fill",
]

enum KeyboardGeometry {
    static let totalWidth: CGFloat = 14.5
    static let totalHeight: CGFloat = 5.7

    /// Deutsches ISO-Layout eines Apple-Keyboards (MacBook / Magic Keyboard).
    /// Keycodes sind virtuelle (layoutunabhängige) Keycodes; welche Zeichen
    /// darauf liegen, entscheidet zur Laufzeit das aktive Layout.
    static func makeLayout() -> [KeyCap] {
        var keys: [KeyCap] = []

        func add(_ id: String, _ code: Int, _ kind: KeyCap.Kind,
                 _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat = 1) {
            keys.append(KeyCap(id: id, keyCode: code, kind: kind, x: x, y: y, width: w, height: h))
        }

        // ── F-Reihe (etwas flacher) ──────────────────────────────
        let fh: CGFloat = 0.7
        add("esc", 53, .special("esc"), 0, 0, 1.3, fh)
        let fKeyCodes = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for (i, code) in fKeyCodes.enumerated() {
            add("f\(i + 1)", code, .fkey(i + 1), 1.3 + CGFloat(i), 0, 1, fh)
        }
        add("touchid", -1, .special("🔒"), 13.3, 0, 1.2, fh)

        // ── Zahlenreihe ──────────────────────────────────────────
        var x: CGFloat = 0
        let row1: [Int] = [10, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]
        for code in row1 {
            add("r1-\(code)", code, .character, x, 0.7, 1)
            x += 1
        }
        add("backspace", 51, .special("⌫"), x, 0.7, 1.5)

        // ── Q-Reihe ──────────────────────────────────────────────
        add("tab", 48, .special("⇥"), 0, 1.7, 1.5)
        x = 1.5
        let row2: [Int] = [12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30]
        for code in row2 {
            add("r2-\(code)", code, .character, x, 1.7, 1)
            x += 1
        }
        // ISO-Enter: oberer Teil 1 Unit breit, unterer 0.75, über zwei Reihen
        add("return", 36, .isoEnter, 13.5, 1.7, 1, 2)

        // ── A-Reihe ──────────────────────────────────────────────
        add("capslock", 57, .modifier(.maskAlphaShift), 0, 2.7, 1.75)
        x = 1.75
        let row3: [Int] = [0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39, 42]
        for code in row3 {
            add("r3-\(code)", code, .character, x, 2.7, 1)
            x += 1
        }

        // ── Shift-Reihe ──────────────────────────────────────────
        add("lshift", 56, .modifier(.maskShift), 0, 3.7, 1.25)
        x = 1.25
        let row4: [Int] = [50, 6, 7, 8, 9, 11, 45, 46, 43, 47, 44]
        for code in row4 {
            add("r4-\(code)", code, .character, x, 3.7, 1)
            x += 1
        }
        add("rshift", 60, .modifier(.maskShift), x, 3.7, 2.25)

        // ── Unterste Reihe ───────────────────────────────────────
        add("fn", 63, .modifier(.maskSecondaryFn), 0, 4.7, 1)
        add("lctrl", 59, .modifier(.maskControl), 1, 4.7, 1)
        add("lopt", 58, .modifier(.maskAlternate), 2, 4.7, 1)
        add("lcmd", 55, .modifier(.maskCommand), 3, 4.7, 1.25)
        add("space", 49, .special(""), 4.25, 4.7, 5)
        add("rcmd", 54, .modifier(.maskCommand), 9.25, 4.7, 1.25)
        add("ropt", 61, .modifier(.maskAlternate), 10.5, 4.7, 1)
        add("left", 123, .special("◀"), 11.5, 5.2, 1, 0.5)
        add("up", 126, .special("▲"), 12.5, 4.7, 1, 0.5)
        add("down", 125, .special("▼"), 12.5, 5.2, 1, 0.5)
        add("right", 124, .special("▶"), 13.5, 5.2, 1, 0.5)

        return keys
    }
}
