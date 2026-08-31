//
//  MascotView.swift
//  Picpic
//
//  The Picpic mascot (blue scholar bird) with its 15 poses,
//  plus a springy entrance animation.
//

import SwiftUI

enum MascotPose: String {
    case idle = "mascot-idle"
    case wave = "mascot-wave"
    case reading = "mascot-reading"
    case thumbsUp = "mascot-thumbsup"
    case flying = "mascot-flying"
    case question = "mascot-question"
    case idea = "mascot-idea"
    case okay = "mascot-okay"
    case heart = "mascot-heart"
    case study = "mascot-study"
    case cheer = "mascot-cheer"
    case open = "mascot-open"
    case walk = "mascot-walk"
    case party = "mascot-party"
    case bookStack = "mascot-bookstack"
}

struct MascotView: View {
    let pose: MascotPose
    var height: CGFloat = 140
    /// Springy pop-in + gentle idle float.
    var animated: Bool = true

    @State private var appeared = false

    var body: some View {
        Image(pose.rawValue)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .scaleEffect(appeared || !animated ? 1 : 0.4)
            .opacity(appeared || !animated ? 1 : 0)
            .modifier(FloatingModifier(active: animated && appeared))
            .onAppear {
                guard animated else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                    appeared = true
                }
            }
    }
}

/// Gentle perpetual float, like the mascot is breathing.
private struct FloatingModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                content
                    .offset(y: CGFloat(sin(t * 1.6)) * 4)
                    .rotationEffect(.degrees(sin(t * 0.9) * 1.5))
            }
        } else {
            content
        }
    }
}

#Preview {
    VStack {
        MascotView(pose: .wave)
        MascotView(pose: .heart, height: 100)
    }
}
