import SwiftUI

/// Design-system color tokens — compiled into BOTH app and widget extension.
/// Keep in Shared/ and do NOT use UIKit/app-only types here.
public enum DSColors {
    // MARK: – Brand palette (from kit.css)
    public static let sage      = Color(hex: "A8C5A0")
    public static let sage2     = Color(hex: "7FA384")
    public static let sageDeep  = Color(hex: "3C5A45")
    public static let ember     = Color(hex: "E8894A")
    public static let ember2    = Color(hex: "F2B25C")
    public static let ink       = Color(hex: "EEF1EC")
    public static let mute      = Color(hex: "9AA59C")
    public static let dim       = Color(hex: "6B756D")
    public static let danger    = Color(hex: "D9675B")

    // MARK: – Glass surfaces (rgba equivalents)
    /// rgba(22,26,24,.55)
    public static let glass     = Color(red: 22/255, green: 26/255, blue: 24/255).opacity(0.55)
    /// rgba(40,46,42,.5)
    public static let glass2    = Color(red: 40/255, green: 46/255, blue: 42/255).opacity(0.5)
    /// white 12%
    public static let line      = Color.white.opacity(0.12)

    // MARK: – Background gradient stops (from kit.css .bg::after)
    public static let bgTop     = Color(red: 14/255, green: 18/255, blue: 16/255).opacity(0.55)
    public static let bgMid     = Color(red: 14/255, green: 18/255, blue: 16/255).opacity(0.78)
    public static let bgBot     = Color(red: 10/255, green: 12/255, blue: 11/255).opacity(0.9)
}
