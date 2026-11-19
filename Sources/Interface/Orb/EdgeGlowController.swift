import AppKit
import Combine
import SwiftUI

/// Siri's screen-edge halo: a borderless overlay per display that glows in
/// the gradient palette while Xavier is listening, thinking, or speaking.
struct EdgeGlowView: View {
    var state: VoiceSession.State
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private var active: Bool {
        switch state {
        case .listening, .speaking: true
        default: false
        }
    }

    var body: some View {
        let gradient = LinearGradient(
            colors: SiriOrb.palette,
            startPoint: .topLeading, endPoint: .bottomTrailing)
        ZStack {
            Rectangle()
                .strokeBorder(gradient, lineWidth: 34)
                .blur(radius: 44)
            Rectangle()
                .strokeBorder(gradient, lineWidth: 12)
                .blur(radius: 18)
                .opacity(0.7)
        }
        .ignoresSafeArea()
        .opacity(active ? 0.85 : 0.45)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                   value: active)
    }
}

@MainActor
final class EdgeGlowController {
    private var windows: [NSWindow] = []
    private var cancellable: AnyCancellable?
    private let appState: AppState
    private var shown = false

    init(appState: AppState) {
        self.appState = appState
        cancellable = appState.voiceSession.$state.sink { [weak self] state in
            Task { @MainActor in self?.update(state) }
        }
    }

    private func update(_ state: VoiceSession.State) {
        switch state {
        case .listening, .transcribing, .processing, .speaking:
            show(state: state)
        case .idle, .interrupted, .error:
            hide()
        }
    }

    private func show(state: VoiceSession.State) {
        if windows.isEmpty {
            windows = NSScreen.screens.map { screen in
                let window = NSWindow(
                    contentRect: screen.frame,
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false)
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = false
                window.ignoresMouseEvents = true
                window.level = .floating
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
                window.isReleasedWhenClosed = false
                window.alphaValue = 0
                window.contentView = NSHostingView(rootView: EdgeGlowView(state: state))
                return window
            }
        } else {
            for window in windows {
                (window.contentView as? NSHostingView<EdgeGlowView>)?.rootView = EdgeGlowView(state: state)
            }
        }
        for window in windows where window.screen != nil || true {
            window.orderFrontRegardless()
        }
        guard !shown else { return }
        shown = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            for window in windows { window.animator().alphaValue = 1 }
        }
    }

    private func hide() {
        guard shown else { return }
        shown = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.5
            for window in windows { window.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, !self.shown else { return }
                for window in self.windows { window.orderOut(nil) }
            }
        })
    }
}
