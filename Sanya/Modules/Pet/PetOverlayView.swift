// PetOverlayView.swift — floating pet overlay above all screens
// Sanya/Modules/Pet/PetOverlayView.swift

import SwiftUI

/// Floating pet overlay.
/// Place once in a full-screen ZStack at the app root.
/// Only the pet itself allows hit-testing (`.allowsHitTesting` on rest = false).
/// Toggle via @AppStorage("petOverlay"). Hidden on the pet module screen.
public struct PetOverlayView: View {
    @AppStorage("petOverlay") private var enabled: Bool = true

    @ObservedObject private var engine = PetEngine.shared
    @ObservedObject private var life = PetLife.shared
    @ObservedObject private var router = Router.shared

    @State private var dragOffset: CGSize = .zero
    @State private var baseX: CGFloat = 0.15   // normalised in [0,1]
    @State private var showBubble: Bool = false
    @State private var tapFeedback: Bool = false

    private let petSize: CGFloat = 64
    private let screenPad: CGFloat = 8

    public init() {}

    private var isVisible: Bool {
        enabled && !router.path.contains(.pet)
    }

    public var body: some View {
        GeometryReader { geo in
            if isVisible {
                ZStack(alignment: .bottomLeading) {
                    // Transparent layer — passes all hits through
                    Color.clear
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("pet_overlay")

                    // Bubble (above pet)
                    if let bubble = engine.bubbleText {
                        bubbleView(bubble)
                            .offset(x: petXOffset(geo).width, y: petXOffset(geo).height - (petSize + 36))
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Pet sprite — ONLY this has hit-testing
                    PetSpriteView(emotion: engine.currentEmotion, size: petSize)
                        .scaleEffect(x: life.isMirrored ? -1 : 1, anchor: .bottom)
                        .scaleEffect(tapFeedback ? 1.15 : 1.0)
                        .offset(petXOffset(geo) + dragOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    dragOffset = v.translation
                                }
                                .onEnded { v in
                                    // Commit position
                                    let newX = (petXOffset(geo).width + v.translation.width + petSize / 2) / geo.size.width
                                    life.setPosition(Double(newX))
                                    dragOffset = .zero
                                }
                        )
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded {
                                    PetStore.shared.pet()
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                                        tapFeedback = true
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        withAnimation { tapFeedback = false }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            TapGesture(count: 2)
                                .onEnded {
                                    Router.shared.go(.pet)
                                }
                        )
                        .allowsHitTesting(true)
                        .animation(.easeInOut(duration: 2.0), value: life.wanderPosition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .allowsHitTesting(isVisible)
        .ignoresSafeArea()
    }

    // MARK: - Helpers

    private func petXOffset(_ geo: GeometryProxy) -> CGSize {
        let x = CGFloat(life.wanderPosition) * (geo.size.width - petSize) + screenPad
        let y = -geo.safeAreaInsets.bottom - screenPad
        return CGSize(width: x, height: y)
    }

    private func bubbleView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(hex: "EEF1EC"))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
            )
    }
}

extension CGSize {
    static func + (l: CGSize, r: CGSize) -> CGSize { CGSize(width: l.width + r.width, height: l.height + r.height) }
}
