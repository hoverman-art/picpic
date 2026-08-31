//
//  MotionPrimitives.swift
//  Picpic
//
//  Small reusable motion building blocks in the spirit of
//  motion-primitives.com, written from scratch in SwiftUI:
//  staggered entrances, animated per-character text, springy
//  press feedback, and a blur+slide transition.
//

import SwiftUI

// MARK: - Staggered entrance

/// Slides + fades a view in, delayed by its index for cascade effects.
struct StaggeredAppear: ViewModifier {
    let index: Int
    let isVisible: Bool
    var baseDelay: Double = 0.08

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 24)
            .blur(radius: isVisible ? 0 : 6)
            .animation(
                .spring(response: 0.55, dampingFraction: 0.82)
                    .delay(Double(index) * baseDelay),
                value: isVisible
            )
    }
}

extension View {
    func staggeredAppear(index: Int, isVisible: Bool, baseDelay: Double = 0.08) -> some View {
        modifier(StaggeredAppear(index: index, isVisible: isVisible, baseDelay: baseDelay))
    }
}

// MARK: - Animated text (per-word reveal)

struct AnimatedText: View {
    let text: String
    let isVisible: Bool
    var font: Font = .display(34)
    var color: Color = .white

    var body: some View {
        let words = text.split(separator: " ").map(String.init)
        // Flow layout via wrapping HStack of words.
        WrappingHStack(spacing: 8) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(word)
                    .font(font)
                    .foregroundStyle(color)
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 14)
                    .rotationEffect(.degrees(isVisible ? 0 : 3), anchor: .bottomLeading)
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(0.05 * Double(index)),
                        value: isVisible
                    )
            }
        }
    }
}

/// Minimal wrapping horizontal layout.
struct WrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Springy press feedback

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Blur + slide transition

extension AnyTransition {
    /// Fluid page transition: content slides while blurring out.
    static func blurSlide(edge: Edge = .trailing) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurSlideModifier(offset: edge == .trailing ? 60 : -60, blur: 12, opacity: 0),
                identity: BlurSlideModifier(offset: 0, blur: 0, opacity: 1)
            ),
            removal: .modifier(
                active: BlurSlideModifier(offset: edge == .trailing ? -60 : 60, blur: 12, opacity: 0),
                identity: BlurSlideModifier(offset: 0, blur: 0, opacity: 1)
            )
        )
    }
}

private struct BlurSlideModifier: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}
