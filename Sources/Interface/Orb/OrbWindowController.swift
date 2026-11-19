import AppKit
import Combine
import SwiftUI

/// Borderless floating panel hosting the Siri-style orb. Shown on wake word
/// or the global hotkey, bottom-center on the active display; auto-hides a
/// few seconds after the assistant comes to rest. `allowsKey` is flipped on
/// in type mode so the orb can take keyboard input like "Type to Siri".
final class OrbPanel: NSPanel {
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OrbWindowController: ObservableObject {
    private var panel: OrbPanel?
    private let appState: AppState
    private let edgeGlow: EdgeGlowController
    private var onOpenConversation: (() -> Void)?
    private var hideTask: Task<Void, Never>?
    private var cancellable: AnyCancellable?
    private var escapeGlobalMonitor: Any?
    private var escapeLocalMonitor: Any?

    /// Type-to-Siri input: expanded by the keyboard affordance, submitted
    /// into the normal pipeline, dismissed by Escape or submit.
    @Published var typeMode = false
    @Published var typeText = ""

    private static let restDelay: Duration = .seconds(6)

    init(appState: AppState) {
        self.appState = appState
        self.edgeGlow = EdgeGlowController(appState: appState)
        cancellable = appState.voiceSession.$state.sink { [weak self] state in
            Task { @MainActor in self?.stateChanged(state) }
        }
    }

    var isVisible: Bool { panel?.isVisible == true }

    // MARK: - Show / hide

    /// Summon the orb and start listening — the Siri activation gesture.
    func summon() {
        show()
        appState.voiceSession.startListening()
    }

    func toggle() {
        if isVisible { hide() } else { summon() }
    }

    func show() {
        let panel = ensurePanel()
        positionPanel(panel)
        panel.orderFrontRegardless()
        cancelHide()
        startEscapeMonitor()
    }

    func hide() {
        exitTypeMode()
        // Dismissing the orb mid-dictation must end capture; otherwise the
        // hidden recognizer can still deliver a transcript with no UI.
        switch appState.voiceSession.state {
        case .listening, .transcribing:
            appState.voiceSession.cancelListening()
        default:
            break
        }
        panel?.orderOut(nil)
        cancelHide()
        stopEscapeMonitor()
    }

    // MARK: - Type mode

    func enterTypeMode() {
        guard let panel = ensurePanel() as OrbPanel? else { return }
        show()
        typeMode = true
        panel.allowsKey = true
        panel.makeKey()
        cancelHide()
    }

    func exitTypeMode() {
        guard typeMode else { return }
        typeMode = false
        typeText = ""
        panel?.allowsKey = false
        panel?.resignKey()
    }

    func submitType() {
        let text = typeText
        typeText = ""
        exitTypeMode()
        appState.sendTyped(text)
    }

    // MARK: - State-driven visibility

    private func stateChanged(_ state: VoiceSession.State) {
        switch state {
        case .listening, .transcribing, .processing, .speaking:
            if isVisible { cancelHide() }
        case .idle, .interrupted, .error:
            if !typeMode { scheduleHide() }
        }
    }

    private func scheduleHide() {
        guard isVisible else { return }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.restDelay)
            guard let self, !Task.isCancelled else { return }
            switch self.appState.voiceSession.state {
            case .idle, .interrupted, .error:
                self.hide()
            default:
                break
            }
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    /// Global monitor sees keys delivered to other apps (needs Input
    /// Monitoring trust); the local one covers Xavier-owned windows, which
    /// global monitors never see.
    private func startEscapeMonitor() {
        if escapeGlobalMonitor == nil {
            escapeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return }
                Task { @MainActor in self?.escapeIfVisible() }
            }
        }
        if escapeLocalMonitor == nil {
            escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                guard let self, self.isVisible else { return event }
                self.escapeIfVisible()
                return nil
            }
        }
    }

    private func stopEscapeMonitor() {
        if let monitor = escapeGlobalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = escapeLocalMonitor { NSEvent.removeMonitor(monitor) }
        escapeGlobalMonitor = nil
        escapeLocalMonitor = nil
    }

    /// Escape only dismisses the orb while it is on screen — a hidden orb
    /// must not cancel dictation running elsewhere (e.g. the chat panel).
    private func escapeIfVisible() {
        guard isVisible else { return }
        hide()
    }

    // MARK: - Panel setup

    private func ensurePanel() -> OrbPanel {
        if let panel { return panel }
        let panel = OrbPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 460),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow

        let content = OrbView(
            voice: appState.voiceSession,
            controller: self,
            appState: appState,
            onTap: { [weak self] in self?.appState.voiceSession.toggle() },
            onOpenConversation: { [weak self] in self?.onOpenConversation?() }
        )
        panel.contentView = NSHostingView(rootView: content)
        self.panel = panel
        return panel
    }

    func setOpenConversationHandler(_ handler: @escaping () -> Void) {
        onOpenConversation = handler
    }

    private func positionPanel(_ panel: OrbPanel) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + visible.height * 0.04
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
