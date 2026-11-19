import SwiftUI

/// Siri-style living orb: a fluid MeshGradient sphere whose color blobs
/// drift and swirl with state and live audio level.
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

    private static let deepSpace = Color(red: 0.02, green: 0.04, blue: 0.16)

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

    // MARK: - Mesh

    /// A 3×3 mesh: dark corners pin the sphere's depth, the four vivid
    /// palette colors ride the edge midpoints, and a hot core drifts at
    /// center. Moving control points carry their colors, so blobs orbit.
    private func meshPoints(t: TimeInterval) -> [SIMD2<Float>] {
        let w = Float(spinSpeed) * .pi / 180 // drift rate, rad/s
        let tt = Float(t)
        let amp: Float = 0.11 + Float(audioBoost) * 0.07
        func drift(_ x: Float, _ y: Float, _ phase: Float, _ scale: Float = 1) -> SIMD2<Float> {
            SIMD2(x + amp * scale * cos(tt * w + phase),
                  y + amp * scale * sin(tt * w * 1.3 + phase))
        }
        return [
            SIMD2(-0.25, -0.25), drift(0.5, -0.15, 0.0), SIMD2(1.25, -0.25),
            drift(-0.15, 0.5, 2.1), drift(0.5, 0.5, 4.2, 1.5), drift(1.15, 0.5, 3.3),
            SIMD2(-0.25, 1.25), drift(0.5, 1.15, 5.1), SIMD2(1.25, 1.25),
        ]
    }

    private var meshColors: [Color] {
        let hot = Color(white: 0.85 + audioBoost * 0.15)
        return [
            Self.deepSpace, Self.palette[0], Self.deepSpace,
            Self.palette[2], hot, Self.palette[3],
            Self.deepSpace, Self.palette[1], Self.deepSpace,
        ]
    }

    // MARK: - Orb

    @ViewBuilder
    private func orb(t: TimeInterval) -> some View {
        ZStack {
            MeshGradient(width: 3, height: 3,
                         points: meshPoints(t: t),
                         colors: meshColors)

            // White-hot center reacting to voice level
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.25 + audioBoost * 0.45), .clear],
                    center: .center, startRadius: 1, endRadius: diameter * 0.3))
                .blur(radius: 5)
                .scaleEffect(1 + audioBoost * 0.3)

            // Specular highlight for liquid-glass depth
            Ellipse()
                .fill(LinearGradient(
                    colors: [.white.opacity(0.4), .clear],
                    startPoint: .top, endPoint: .bottom))
                .frame(width: diameter * 0.65, height: diameter * 0.26)
                .offset(y: -diameter * 0.31)
                .blur(radius: 4)

            // Lower bounce light
            Ellipse()
                .fill(Self.palette[3].opacity(0.35))
                .frame(width: diameter * 0.55, height: diameter * 0.18)
                .offset(y: diameter * 0.36)
                .blur(radius: 8)
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
