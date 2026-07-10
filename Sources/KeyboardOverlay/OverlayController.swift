import AppKit
import Carbon.HIToolbox
import Foundation
import IOKit.hid

/// Verkabelt Event-Tap, BTT-Store, Layout-Wechsel und Berechtigungen.
@MainActor
final class OverlayController {
    let state: OverlayState
    private let eventTap = EventTap()
    private var permissionTimer: Timer?
    private var bttWatcher: DispatchSourceFileSystemObject?
    private var bttReloadWorkItem: DispatchWorkItem?

    init(state: OverlayState) {
        self.state = state
    }

    func start() {
        state.layoutName = state.translator.layoutName
        reloadBTT()

        eventTap.onFlagsChanged = { [weak self] flags in
            self?.state.handleFlagsChanged(flags)
        }
        eventTap.onKey = { [weak self] keyCode, isDown, flags in
            self?.state.handleKey(keyCode: keyCode, isDown: isDown, flags: flags)
        }

        startMonitoringIfPermitted(requestIfNeeded: true)
        observeInputSourceChanges()
        watchBTTDirectory()
    }

    // MARK: - Eingabeüberwachung

    private func startMonitoringIfPermitted(requestIfNeeded: Bool) {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
            state.monitoringActive = eventTap.start()
        } else {
            state.monitoringActive = false
            if requestIfNeeded {
                IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            }
            schedulePermissionRecheck()
        }
    }

    private func schedulePermissionRecheck() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.state.monitoringActive = self.eventTap.start()
                }
            }
        }
    }

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - BTT

    func reloadBTT() {
        Task.detached(priority: .userInitiated) {
            let replacements = BTTStore.loadReplacements()
            await MainActor.run { [weak self] in
                self?.state.bttReplacements = replacements
            }
        }
    }

    /// BTT-Datenverzeichnis beobachten; bei Änderungen (entprellt) neu laden.
    private func watchBTTDirectory() {
        let dir = BTTStore.dataDirectory
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                               eventMask: [.write],
                                                               queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.bttReloadWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.reloadBTT() }
            self.bttReloadWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        bttWatcher = source
    }

    // MARK: - Layout-Wechsel

    private func observeInputSourceChanges() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.state.translator.reload()
                self.state.layoutName = self.state.translator.layoutName
                self.state.liveDeadKeyState = 0
                // Neuzeichnen anstoßen
                self.state.objectWillChange.send()
            }
        }
    }
}
