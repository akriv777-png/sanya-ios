import SwiftUI

/// Thin deprecated shim — maps old Theme.* to DS tokens.
/// New code should use DS.Color.* directly.
@available(*, deprecated, renamed: "DS.Color")
enum Theme {
    @available(*, deprecated, renamed: "DS.Color.sageDeep")
    static let bg      = Color(hex: "141816")
    @available(*, deprecated)
    static let card    = Color.white.opacity(0.07)
    @available(*, deprecated)
    static let card2   = Color.white.opacity(0.12)
    @available(*, deprecated, renamed: "DS.Color.ember")
    static let accent  = DS.Color.ember
    @available(*, deprecated, renamed: "DS.Color.sage")
    static let violet  = DS.Color.sage
    @available(*, deprecated, renamed: "DS.Color.ember2")
    static let gold    = DS.Color.ember2

    @available(*, deprecated)
    static var background: some View {
        AtmosphereBackground()
    }
}

extension View {
    /// Legacy `.card()` → glass card restyle.
    @available(*, deprecated, renamed: "glassCard()")
    func card() -> some View {
        self
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(DS.Color.line, lineWidth: 1))
    }
}
