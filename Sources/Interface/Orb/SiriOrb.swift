import SwiftUI

/// Siri-style living orb: layered color washes spinning inside a clipped
/// sphere, breathing with state and live audio level.
struct SiriOrb: View {
    var state: VoiceSession.State
    var level: CGFloat = 0
    var diameter: CGFloat = 92
    var reduceMotion: Bool = false
    /// Brand mark stays at rest, fades out while Xavier is working.
    var showMark: Bool = true

    static let palette: [Color] = [
        Color(red: 0.36, green: 0.95, blue: 0.98), // cyan
        Color(red: 0.24, green: 0.52, blue: 1.00), // blue
        Color(red: 0.61, green: 0.35, blue: 1.00), // violet
        Color(red: 1.00, green: 0.38, blue: 0.81), // magenta
    ]

    var body: some View {
        if reduceMotion {
            orb(t: 0)
        } else {
            TimelineView(.animation) { context in
                orb(t: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private var energy: Double {
        switch state {
        case .listening: 1.0
        case .transcribing, .processing: 0.9
        case .speaking: 1.0
        case .interrupted, .error: 0.35
        case .idle: 0.55
        }
    }

    private var spinSpeed: Double {
        switch state {
        case .idle: 14
        case .listening: 40
        case .transcribing, .processing: 90
        case .speaking: 60
        case .interrupted, .error: 8
        }
    }

    private var audioBoost: Double {
        state == .listening ? Double(min(max(level, 0), 1)) : 0
    }

    @ViewBuilder
    private func orb(t: TimeInterval) -> some View {
        ZStack {
            // Deep-space core
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0.03, green: 0.05, blue: 0.20),
                             Color(red: 0.0, green: 0.0, blue: 0.05)],
                    center: .center, startRadius: 2, endRadius: diameter * 0.55))

            // Spinning color washes
            colorWash(Self.palette[0], Self.palette[1], angle: t * spinSpeed)
            colorWash(Self.palette[2], Self.palette[3], angle: -t * spinSpeed * 1.35 + 120)
            colorWash(Self.palette[3], Self.palette[0], angle: t * spinSpeed * 1.7 + 250)

            // White-hot center reacting to voice level
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.30 + audioBoost * 0.45), .clear],
                    center: .center, startRadius: 1, endRadius: diameter * 0.3))
                .blur(radius: 5)
                .scaleEffect(1 + audioBoost * 0.3)

            // Top specular highlight
            Ellipse()
                .fill(LinearGradient(
                    colors: [.white.opacity(0.35), .clear],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: diameter * 0.7, height: diameter * 0.30)
                .offset(y: -diameter * 0.30)
                .blur(radius: 5)
        }
        .opacity(energy)
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(LinearGradient(
                    colors: [.white.opacity(0.55), .white.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
        )
        .overlay(markOverlay)
        .shadow(color: Self.palette[2].opacity(0.65 + audioBoost * 0.3),
                radius: 16 + audioBoost * 18)
        .scaleEffect(scale(t: t))
    }

    @ViewBuilder
    private var markOverlay: some View {
        if showMark {
            Image("XavierMark")
                .resizable()
                .scaledToFit()
                .frame(width: diameter * 0.38, height: diameter * 0.38)
                .opacity(state == .idle ? 0.6 : 0.0)
        }
    }

    private func colorWash(_ a: Color, _ b: Color, angle: Double) -> some View {
        AngularGradient(
            colors: [a, b, .clear, .clear, a.opacity(0), a],
            center: .center)
            .blur(radius: 10)
            .rotationEffect(.degrees(angle))
    }

    private func scale(t: TimeInterval) -> CGFloat {
        var s: Double = 1
        switch state {
        case .listening, .speaking:
            s += 0.045 * sin(t * 2.4)
        case .transcribing, .processing:
            s += 0.02 * sin(t * 5)
        default:
            break
        }
        return s + audioBoost * 0.10
    }
}
