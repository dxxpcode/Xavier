import AppKit
import SwiftUI

/// Borderless floating NSPanel hosting the conversation view.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingWindowController {
    static let compactSize = NSSize(width: 420, height: 540)
    static let expandedSize = NSSize(width: 640, height: 740)

    private var panel: FloatingPanel?
    private var inactivityTimer: Timer?
    private var clickOutsideMonitor: Any?
    private var escapeMonitor: Any?
    private var activityMonitor: Any?
    private let appState: AppState

    var panelIsKey: Bool { panel?.isKeyWindow == true }

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Show / hide

    func toggle() {
        if panel?.isVisible == true { hide() } else { show() }
    }

    func show() {
        let panel = ensurePanel()
        positionPanel(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        appState.isPanelVisible = true
        startOutsideMonitors()
        resetInactivityTimer()
    }

    func hide() {
        panel?.orderOut(nil)
        appState.isPanelVisible = false
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        stopOutsideMonitors()
    }

    // MARK: - Panel setup

    private func ensurePanel() -> FloatingPanel {
        if let panel { return panel }
        let size = appState.settings.expandWindow ? Self.expandedSize : Self.compactSize
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 340, height: 400)
        panel.maxSize = NSSize(width: 1000, height: 1200)
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let content = ConversationView()
            .environmentObject(appState)
            .environmentObject(appState.orchestrator)
            .environmentObject(appState.voiceSession)
            .environmentObject(appState.modelManager)
            .environmentObject(appState.settings)
        panel.contentView = NSHostingView(rootView: content)
        self.panel = panel
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = visible.midX - size.width / 2
        let y = visible.maxY - size.height - visible.height * 0.12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func setExpanded(_ expanded: Bool) {
        guard let panel else { return }
        var frame = panel.frame
        let size = expanded ? Self.expandedSize : Self.compactSize
        frame.origin.y += frame.height - size.height
        frame.origin.x += (frame.width - size.width) / 2
        frame.size = size
        panel.setFrame(frame, display: true, animate: true)
    }

    // MARK: - Auto-hide

    private func resetInactivityTimer() {
        inactivityTimer?.invalidate()
        guard appState.settings.autoHideEnabled else { return }
        let timeout = appState.settings.inactivityTimeout
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func noteUserActivity() {
        resetInactivityTimer()
    }

    private func startOutsideMonitors() {
        stopOutsideMonitors()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.hide()
                }
            }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53, self.panel?.isKeyWindow == true {
                self.hide()
                return nil
            }
            self.noteUserActivity()
            return event
        }
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .scrollWheel]) { [weak self] event in
            self?.noteUserActivity()
            return event
        }
    }

    private func stopOutsideMonitors() {
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m) }
        if let m = escapeMonitor { NSEvent.removeMonitor(m) }
        if let m = activityMonitor { NSEvent.removeMonitor(m) }
        clickOutsideMonitor = nil
        escapeMonitor = nil
        activityMonitor = nil
    }
}
