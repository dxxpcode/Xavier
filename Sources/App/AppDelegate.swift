import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private(set) var floatingWindow: FloatingWindowController!
    private var menuBar: MenuBarController!
    private var onboarding = OnboardingWindowController()
    private let preferences = PreferencesWindowController()
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appState.onOpenPreferences = { [weak self] in self?.showPreferences() }
        appState.start()

        floatingWindow = FloatingWindowController(appState: appState)
        menuBar = MenuBarController(appState: appState)
        wireMenuBar()
        registerHotkey()
        registerLocalShortcuts()

        appState.voiceSession.refreshPermissionStatus()
        if !appState.settings.hasCompletedOnboarding {
            onboarding.show(appState: appState) { [weak self] in
                self?.floatingWindow.show()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func wireMenuBar() {
        menuBar.onOpen = { [weak self] in self?.floatingWindow.toggle() }
        menuBar.onVoice = { [weak self] in
            self?.floatingWindow.show()
            self?.appState.voiceSession.startListening()
        }
        menuBar.onNewConversation = { [weak self] in
            self?.appState.orchestrator.newConversation()
            self?.floatingWindow.show()
        }
        menuBar.onOpenConversation = { [weak self] conv in
            self?.appState.orchestrator.load(conversation: conv)
            self?.floatingWindow.show()
        }
        menuBar.onPreferences = { [weak self] in
            guard let self else { return }
            self.preferences.show(appState: self.appState)
        }
    }

    func showPreferences() {
        preferences.show(appState: appState)
    }

    func registerHotkey() {
        let settings = appState.settings
        HotKeyManager.shared.register(keyCode: settings.hotkeyKeyCode,
                                      modifiers: settings.hotkeyModifiers)
        HotKeyManager.shared.onPress = { [weak self] in
            self?.floatingWindow.toggle()
            self?.floatingWindow.noteUserActivity()
        }
    }

    /// ⌥M toggles voice while the panel is key; ⌘N starts a new conversation.
    private func registerLocalShortcuts() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.floatingWindow.panelIsKey else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == [.option], event.keyCode == 46 { // M
                self.appState.voiceSession.toggle()
                return nil
            }
            if flags == [.command], event.keyCode == 45 { // N
                self.appState.orchestrator.newConversation()
                return nil
            }
            return event
        }
    }
}
