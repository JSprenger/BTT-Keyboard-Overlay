import CoreGraphics
import Foundation

/// Passiver (listen-only) Event-Tap für Tastendrücke und Modifier-Änderungen.
/// Braucht die Berechtigung „Eingabeüberwachung“ (Input Monitoring).
final class EventTap {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onKey: ((_ keyCode: Int, _ isDown: Bool, _ flags: CGEventFlags) -> Void)?
    var onFlagsChanged: ((CGEventFlags) -> Void)?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
            me.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        tap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        case .flagsChanged:
            let flags = event.flags
            DispatchQueue.main.async { [weak self] in
                self?.onFlagsChanged?(flags)
            }
        case .keyDown, .keyUp:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let isDown = type == .keyDown
            let flags = event.flags
            DispatchQueue.main.async { [weak self] in
                self?.onKey?(keyCode, isDown, flags)
            }
        default:
            break
        }
    }

    deinit {
        stop()
    }
}
