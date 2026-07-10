import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Übersetzt virtuelle Keycodes in Zeichen, exakt wie macOS es täte
/// (gleiche API, die auch die Original-Tastaturübersicht nutzt: UCKeyTranslate
/// mit den Layout-Daten der aktuellen Eingabequelle).
final class KeyTranslator {
    private var layoutData: Data?
    private(set) var layoutName: String = ""

    init() {
        reload()
    }

    /// Layout-Daten der aktuell gewählten Eingabequelle neu laden
    /// (z. B. nach Wechsel Deutsch → US).
    func reload() {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return
        }
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let cfData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
            layoutData = cfData as Data
        }
        if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            layoutName = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        }
    }

    struct Result {
        let text: String
        let deadKeyState: UInt32
        /// true = Akzenttaste (dead key): erzeugt allein kein Zeichen,
        /// sondern wartet auf die nächste Taste.
        let isDead: Bool
    }

    func translate(keyCode: Int,
                   cgFlags: CGEventFlags,
                   deadKeyState: UInt32 = 0,
                   ignoreDeadKeys: Bool = false) -> Result {
        guard let data = layoutData, keyCode >= 0 else {
            return Result(text: "", deadKeyState: 0, isDead: false)
        }

        var carbonModifiers: UInt32 = 0
        if cgFlags.contains(.maskShift) { carbonModifiers |= UInt32(shiftKey) }
        if cgFlags.contains(.maskAlternate) { carbonModifiers |= UInt32(optionKey) }
        if cgFlags.contains(.maskControl) { carbonModifiers |= UInt32(controlKey) }
        if cgFlags.contains(.maskCommand) { carbonModifiers |= UInt32(cmdKey) }
        if cgFlags.contains(.maskAlphaShift) { carbonModifiers |= UInt32(alphaLock) }
        let modifierKeyState = (carbonModifiers >> 8) & 0xFF

        var dead: UInt32 = deadKeyState
        var chars = [UniChar](repeating: 0, count: 8)
        var length = 0
        let options: OptionBits = ignoreDeadKeys ? OptionBits(kUCKeyTranslateNoDeadKeysMask) : 0

        let status = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(layout,
                                  UInt16(keyCode),
                                  UInt16(kUCKeyActionDown),
                                  modifierKeyState,
                                  UInt32(LMGetKbdType()),
                                  options,
                                  &dead,
                                  chars.count,
                                  &length,
                                  &chars)
        }
        guard status == noErr else {
            return Result(text: "", deadKeyState: 0, isDead: false)
        }

        let text = String(utf16CodeUnits: chars, count: length)
        let isDead = dead != 0 && length == 0
        return Result(text: text, deadKeyState: dead, isDead: isDead)
    }
}
