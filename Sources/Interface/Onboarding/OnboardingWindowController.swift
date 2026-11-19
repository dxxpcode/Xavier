import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(appState: AppState, onFinish: @escaping () -> Void) {
        let view = OnboardingView(onFinish: { [weak self] in
            self?.close()
            onFinish()
        })
        .environmentObject(appState)
        .environmentObject(appState.modelManager)
        .environmentObject(appState.voiceSession)
        .environmentObject(appState.settings)

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Xavier"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 440))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = WindowDelegate.shared
        WindowDelegate.shared.onClose = { [weak self] in
            self?.window = nil
            onFinish()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func close() {
        window?.close()
        window = nil
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
