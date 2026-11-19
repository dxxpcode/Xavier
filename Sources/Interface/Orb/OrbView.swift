import SwiftUI

/// Siri-style ambient surface: the living gradient orb, a transient answer
/// card, a state caption, live transcript, and a Type-to-Siri field.
/// Click the orb to toggle listening; the keyboard button opens typed input.
struct OrbView: View {
    @ObservedObject var voice: VoiceSession
    @ObservedObject var controller: OrbWindowController
    @ObservedObject var appState: AppState
    var onTap: () -> Void
    var onOpenConversation: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @FocusState private var typeFieldFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            if let exchange = appState.lastExchange {
                AnswerCard(exchange: exchange, onOpenConversation: onOpenConversation)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
            }
            Spacer(minLength: 0)
            orb
            caption
            input
        }
        .padding(20)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8),
                   value: appState.lastExchange != nil)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85),
                   value: appState.lastExchange?.answer != nil)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82),
                   value: controller.typeMode)
        .onChange(of: controller.typeMode) { _, mode in
            typeFieldFocused = mode
        }
    }

    // MARK: - Orb

    private var orb: some View {
        ZStack(alignment: .bottomTrailing) {
            Button(action: onTap) {
                SiriOrb(state: state, level: CGFloat(voice.audioLevel),
                        diameter: 96, reduceMotion: reduceMotion)
                    .frame(width: 100, height: 100)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)

            if showsTypeButton {
                Button(action: { controller.enterTypeMode() }) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Type to Xavier")
                .accessibilityLabel("Type to Xavier")
            }
        }
    }

    private var showsTypeButton: Bool {
        switch state {
        case .idle, .interrupted, .error: !controller.typeMode
        default: false
        }
    }

    private var state: VoiceSession.State { voice.state }

    private var accessibilityLabel: String {
        switch state {
        case .listening: "Stop listening"
        case .speaking: "Interrupt Xavier"
        default: "Talk to Xavier"
        }
    }

    // MARK: - Caption + input

    private var caption: some View {
        Text(captionText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 14)
    }

    private var captionText: String {
        if controller.typeMode { return "Type to Xavier — ⏎ sends, Esc closes" }
        switch state {
        case .idle: return "Say “Hey Xavier”"
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .processing: return "Thinking…"
        case .speaking: return "Speaking — tap to interrupt"
        case .interrupted: return "Interrupted"
        case .error(let message): return message
        }
    }

    @ViewBuilder
    private var input: some View {
        if controller.typeMode {
            TextField("Ask Xavier anything", text: $controller.typeText)
                .textFieldStyle(.plain)
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
                .frame(maxWidth: 280)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .focused($typeFieldFocused)
                .onSubmit { controller.submitType() }
        } else {
            let text = voice.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                Text(text)
                    .font(.callout)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .onTapGesture(perform: onOpenConversation)
                    .accessibilityHint("Opens the conversation")
            }
        }
    }
}
