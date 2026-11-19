import SwiftUI

/// Xavier's minimal waveform identity, animated by voice state.
struct WaveformView: View {
    let state: VoiceSession.State
    let level: Float

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    private let barCount = 9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            Canvas { ctx, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let midY = size.height / 2
                let barWidth: CGFloat = 3
                let spacing = (size.width - barWidth) / CGFloat(barCount - 1)

                for i in 0..<barCount {
                    let x = CGFloat(i) * spacing
                    let amp = amplitude(index: i, time: t)
                    let h = max(2, amp * size.height)
                    let rect = CGRect(x: x, y: midY - h / 2, width: barWidth, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2), with: .color(barColor))
                }
            }
        }
        .accessibilityLabel("Xavier \(stateLabel)")
    }

    private var stateLabel: String {
        switch state {
        case .idle: return "idle"
        case .listening: return "listening"
        case .transcribing: return "transcribing"
        case .processing: return "thinking"
        case .speaking: return "speaking"
        case .interrupted: return "interrupted"
        case .error: return "error"
        }
    }

    private var barColor: Color {
        switch state {
        case .error: return .red
        case .interrupted: return .secondary.opacity(0.5)
        case .listening, .speaking: return .accentColor
        default: return .secondary
        }
    }

    private func amplitude(index: Int, time: Double) -> CGFloat {
        let phase = Double(index) * 0.6
        switch state {
        case .idle, .interrupted:
            return 0.15
        case .listening:
            let wobble = reduceMotion ? 0.5 : (sin(time * 3 + phase) + 1) / 2
            return 0.15 + CGFloat(level) * 0.6 + CGFloat(wobble) * 0.15
        case .transcribing, .processing:
            let w = reduceMotion ? 0.4 : (sin(time * 4 + phase) + 1) / 2
            return 0.2 + CGFloat(w) * 0.35
        case .speaking:
            let w = reduceMotion ? 0.5 : abs(sin(time * 5 + phase))
            return 0.2 + CGFloat(w) * 0.6
        case .error:
            return 0.1
        }
    }
}
