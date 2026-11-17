import SwiftUI

enum Theme {
    static let bg = Color(hex: "0B0B12")
    static let card = Color(hex: "171724")
    static let card2 = Color(hex: "202034")
    static let accent = Color(hex: "FF3B5C")
    static let violet = Color(hex: "8A5CFF")
    static let gold = Color(hex: "FFB020")

    static var background: some View {
        LinearGradient(colors: [Color(hex: "120A1E"), bg, Color(hex: "07070C")], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.06)))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

enum Fmt {
    static let ru = Locale(identifier: "ru_RU")
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = ru
        c.firstWeekday = 2
        return c
    }
    static func time(_ d: Date) -> String { d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(ru)) }
    static func day(_ d: Date) -> String { d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(ru)) }
    static func longDay(_ d: Date) -> String { d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(ru)) }
    static func month(_ d: Date) -> String { d.formatted(.dateTime.month(.wide).year().locale(ru)).capitalized }
    static func hours(_ h: Double) -> String { String(format: "%.1f ч", h) }
    static func money(_ v: Double) -> String { String(format: "%.0f €", v) }
    static func clock(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
