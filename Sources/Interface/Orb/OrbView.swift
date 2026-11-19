import SwiftUI

/// Siri-style ambient surface: the XX orb with a live waveform, a state
/// caption, and the current transcript. Click toggles listening.
struct OrbView: View {
    @ObservedObject var voice: VoiceSession
    var onTap: () -> Void
    var onOpenConversation: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            orb
            caption
            transcript
        }
        .padding(20)
    }

    // MARK: - Orb

    private var orb: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(.ultraThickMaterial)
                    .frame(width: 92, height: 92)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(state == .listening ? 0.9 : 0.25),
                                          lineWidth: state == .listening ? 2.5 : 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)

                Image("XavierMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .opacity(0.9)

                WaveformView(state: state, level: voice.audioLevel)
                    .frame(width: 92, height: 26)
                    .offset(y: 44)
            }
            .frame(width: 96, height: 96)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .scaleEffect(pulse ? 1.04 : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                   value: pulse)
    }

    private var pulse: Bool {
        state == .listening || state == .speaking
    }

    private var state: VoiceSession.State { voice.state }

    private var accessibilityLabel: String {
        switch state {
        case .listening: "Stop listening"
        case .speaking: "Interrupt Xavier"
        default: "Talk to Xavier"
        }
    }

    // MARK: - Caption + transcript

    private var caption: some View {
        Text(captionText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 14)
    }

    private var captionText: String {
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
    private var transcript: some View {
        let text = voice.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            Text(text)
                .font(.callout)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
                .onTapGesture(perform: onOpenConversation)
                .accessibilityHint("Opens the conversation")
        }
    }
}
