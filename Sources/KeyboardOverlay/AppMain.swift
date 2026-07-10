import AppKit
import SwiftUI

/// Schwebendes, nicht-aktivierendes Panel – wie die macOS-Tastaturübersicht:
/// bleibt über anderen Fenstern, stiehlt keiner App den Fokus.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private let state = OverlayState()
    private var controller: OverlayController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = OverlayController(state: state)

        let hosting = NSHostingView(rootView: ContentView(state: state, controller: controller))

        panel = NSPanel(contentRect: NSRect(x: 200, y: 200, width: 960, height: 460),
                        styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
                        backing: .buffered,
                        defer: false)
        panel.title = "Tastaturübersicht+"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.minSize = NSSize(width: 640, height: 320)
        panel.contentView = hosting
        panel.setFrameAutosaveName("KeyboardOverlayPanel")
        panel.makeKeyAndOrderFront(nil)

        controller.start()
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
