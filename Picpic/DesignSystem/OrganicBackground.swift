//
//  OrganicBackground.swift
//  Picpic
//
//  Generative organic backgrounds in the spirit of haikei.app
//  (layered waves + soft blobs), animated from scratch with
//  TimelineView — no assets, no dependencies.
//

import SwiftUI

/// A wave layer whose surface undulates continuously.
struct WaveShape: Shape {
    var phase: Double
    /// 0 = top of the frame, 1 = bottom.
    var baseline: CGFloat
    var amplitude: CGFloat
    var frequency: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseY = rect.height * baseline
        path.move(to: CGPoint(x: 0, y: baseY))
        let step: CGFloat = 4
        var x: CGFloat = 0
        while x <= rect.width {
            let relative = Double(x / rect.width)
            let y = baseY + amplitude * CGFloat(sin(relative * .pi * 2 * frequency + phase))
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

/// Soft drifting blob, rendered as a heavily blurred ellipse.
private struct DriftingBlob: View {
    let color: Color
    let size: CGFloat
    let xOffset: CGFloat
    let yOffset: CGFloat
    let speed: Double
    let seed: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * speed + seed
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .blur(radius: size * 0.35)
                .offset(
                    x: xOffset + CGFloat(sin(t)) * 40,
                    y: yOffset + CGFloat(cos(t * 0.8)) * 30
                )
        }
    }
}

/// Full-screen animated background: gradient + blobs + two wave layers.
struct OrganicBackground: View {
    let colors: [Color]
    var showWaves: Bool = true

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            DriftingBlob(color: colors.last?.opacity(0.55) ?? .purple.opacity(0.5),
                         size: 280, xOffset: -110, yOffset: -220, speed: 0.35, seed: 0)
            DriftingBlob(color: Theme.accent.opacity(0.30),
                         size: 220, xOffset: 130, yOffset: -60, speed: 0.28, seed: 2.1)
            DriftingBlob(color: .white.opacity(0.14),
                         size: 320, xOffset: 60, yOffset: 260, speed: 0.22, seed: 4.4)

            if showWaves {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    ZStack {
                        WaveShape(phase: t * 0.6, baseline: 0.82, amplitude: 14, frequency: 1.4)
                            .fill(.white.opacity(0.07))
                        WaveShape(phase: t * 0.9 + 1.5, baseline: 0.88, amplitude: 18, frequency: 1.1)
                            .fill(.white.opacity(0.10))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    OrganicBackground(colors: Theme.onboardingGradients[0])
}
