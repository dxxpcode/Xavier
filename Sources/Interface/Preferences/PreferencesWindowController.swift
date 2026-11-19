import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController {
    private var window: NSWindow?

    func show(appState: AppState) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = PreferencesView()
            .environmentObject(appState)
            .environmentObject(appState.modelManager)
            .environmentObject(appState.voiceSession)
            .environmentObject(appState.settings)

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Xavier Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 560, height: 480))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = WindowDelegate.shared
        WindowDelegate.shared.onClose = { [weak self] in
            self?.window = nil
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

private final class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
    }
}
