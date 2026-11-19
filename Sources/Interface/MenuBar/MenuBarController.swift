import AppKit
import SwiftUI

/// Persistent menu bar presence via NSStatusItem.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let appState: AppState
    private var recentsItems: [NSMenuItem] = []

    var onOpen: (() -> Void)?
    var onVoice: (() -> Void)?
    var onNewConversation: (() -> Void)?
    var onOpenConversation: ((Conversation) -> Void)?
    var onPreferences: (() -> Void)?

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        rebuildMenu()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(named: "XavierMark") {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            button.image = image
        } else {
            button.title = "𝕏"
        }
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .leftMouseUp {
            onOpen?()
        } else {
            statusItem.menu = menu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        }
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open Xavier", action: #selector(openPressed), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let voice = NSMenuItem(title: "Start Voice Conversation", action: #selector(voicePressed), keyEquivalent: "")
        voice.target = self
        menu.addItem(voice)

        let newConv = NSMenuItem(title: "New Conversation", action: #selector(newPressed), keyEquivalent: "")
        newConv.target = self
        menu.addItem(newConv)

        menu.addItem(.separator())

        // Recent conversations
        let recents = (try? appState.conversationStore.listConversations(limit: 8)) ?? []
        if !recents.isEmpty {
            let header = NSMenuItem(title: "Recent Conversations", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for conv in recents {
                let item = NSMenuItem(title: conv.title.isEmpty ? "Conversation" : conv.title,
                                      action: #selector(recentPressed(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = conv
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let prefs = NSMenuItem(title: "Preferences…", action: #selector(prefsPressed), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Xavier", action: #selector(quitPressed), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    func rebuildMenu() {
        // Recents are rebuilt each time the menu opens; nothing to cache.
    }

    @objc private func openPressed() { onOpen?() }
    @objc private func voicePressed() { onVoice?() }
    @objc private func newPressed() { onNewConversation?() }
    @objc private func recentPressed(_ item: NSMenuItem) {
        if let conv = item.representedObject as? Conversation { onOpenConversation?(conv) }
    }
    @objc private func prefsPressed() { onPreferences?() }
    @objc private func quitPressed() { NSApp.terminate(nil) }
}
