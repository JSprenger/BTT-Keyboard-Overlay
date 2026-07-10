import AppKit
import Combine
import SwiftUI

/// Schwebendes, nicht-aktivierendes Panel – wie die macOS-Tastaturübersicht:
/// bleibt über anderen Fenstern, stiehlt keiner App den Fokus.
/// Randlos (keine Titelleiste); geschlossen wird über das ✕ im Overlay.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private let state = OverlayState()
    private var controller: OverlayController!
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = OverlayController(state: state)

        let hosting = NSHostingView(rootView: ContentView(state: state, controller: controller))

        let aspect = NSSize(width: KeyboardGeometry.contentUnitsWide,
                            height: KeyboardGeometry.contentUnitsHigh)
        let initialWidth: CGFloat = 960
        panel = NSPanel(contentRect: NSRect(x: 200, y: 200,
                                            width: initialWidth,
                                            height: initialWidth * aspect.height / aspect.width),
                        styleMask: [.borderless, .resizable, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        // Randlos + transparent: das abgerundete Material zeichnet SwiftUI.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Seitenverhältnis fixieren, damit keine leeren Ränder entstehen.
        panel.contentAspectRatio = aspect
        panel.minSize = NSSize(width: 600, height: 600 * aspect.height / aspect.width)
        panel.contentView = hosting
        panel.setFrameAutosaveName("KeyboardOverlayPanel")
        normalizeFrameToAspect()
        panel.makeKeyAndOrderFront(nil)

        // Transparenz-Slider steuert die Deckkraft des ganzen Panels.
        state.$windowAlpha
            .sink { [weak panel] alpha in panel?.alphaValue = alpha }
            .store(in: &cancellables)

        controller.start()
    }

    /// Gespeicherte Fenstergröße kann vom alten Seitenverhältnis stammen –
    /// Höhe an die Breite anpassen.
    private func normalizeFrameToAspect() {
        var frame = panel.frame
        let targetHeight = frame.width * KeyboardGeometry.contentUnitsHigh / KeyboardGeometry.contentUnitsWide
        guard abs(frame.height - targetHeight) > 0.5 else { return }
        frame.origin.y += frame.height - targetHeight
        frame.size.height = targetHeight
        panel.setFrame(frame, display: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
enum AppMain {
    @MainActor
    static func main() {
        // Debug: BTT-Ersetzungen auf stdout ausgeben und beenden.
        if CommandLine.arguments.contains("--dump-btt") {
            let replacements = BTTStore.loadReplacements()
            for (shortcut, text) in replacements.sorted(by: { ($0.key.modifiers, $0.key.keyCode) < ($1.key.modifiers, $1.key.keyCode) }) {
                print("keycode=\(shortcut.keyCode) modifiers=0x\(String(shortcut.modifiers, radix: 16)) text=\(text)")
            }
            print("\(replacements.count) Ersetzungen")
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)

        // Minimales Hauptmenü, damit ⌘Q funktioniert, wenn die App aktiv ist.
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Tastaturübersicht+ beenden",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        app.mainMenu = mainMenu

        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
