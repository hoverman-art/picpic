//
//  PaperBackground.swift
//  Picpic
//
//  Le fond des écrans pleine page — onboarding et didacticiel.
//
//  Il remplace `OrganicBackground`, qui posait quatre dégradés sombres
//  saturés là où le reste de l'application est en encre sur crème. La mesure
//  du 8 septembre 2026 (docs/DESIGN-SYSTEME.md) : l'accueil est neutre à
//  81 %, l'onboarding à 2 %. C'était deux applications en un tapotement sur
//  « Continuer ».
//
//  Le mouvement, lui, est conservé : ce n'est pas lui qui trahissait le
//  produit, c'était la couleur. Les vagues restent, en encre très diluée.
//

import SwiftUI

/// Une vague dont la surface ondule en continu.
struct WaveShape: Shape {
    var phase: Double
    /// 0 = haut du cadre, 1 = bas.
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

/// Voile dérivant, ellipse très floutée. Les opacités sont volontairement
/// basses : au-delà, la teinte redevient un aplat et la page cesse d'être
/// du papier.
private struct DriftingWash: View {
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

/// Fond pleine page : papier, deux voiles d'encre, deux vagues.
///
/// `variation` décale les vagues d'une page à l'autre — assez pour que le
/// fond respire au fil des étapes, pas assez pour qu'il change d'identité.
struct PaperBackground: View {
    var variation: Int = 0
    var showWaves: Bool = true

    var body: some View {
        ZStack {
            Theme.paper

            DriftingWash(color: Theme.ink.opacity(0.05),
                         size: 300, xOffset: -110, yOffset: -230, speed: 0.35,
                         seed: Double(variation) * 1.3)
            DriftingWash(color: Theme.accent.opacity(0.06),
                         size: 240, xOffset: 130, yOffset: -60, speed: 0.28,
                         seed: 2.1 + Double(variation) * 1.3)

            if showWaves {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let shift = Double(variation) * 0.7
                    ZStack {
                        WaveShape(phase: t * 0.6 + shift, baseline: 0.82, amplitude: 14, frequency: 1.4)
                            .fill(Theme.ink.opacity(0.04))
                        WaveShape(phase: t * 0.9 + 1.5 + shift, baseline: 0.88, amplitude: 18, frequency: 1.1)
                            .fill(Theme.ink.opacity(0.06))
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    PaperBackground()
}
