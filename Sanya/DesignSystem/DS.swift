import SwiftUI

// MARK: - DS (Design System)

/// Central design-system namespace. All UI components should import and use DS exclusively.
/// Background images are app-only and live here (not in Shared/).
public enum DS {

    // MARK: – Color aliases
    public enum Color {
        public static let sage      = DSColors.sage
        public static let sage2     = DSColors.sage2
        public static let sageDeep  = DSColors.sageDeep
        public static let ember     = DSColors.ember
        public static let ember2    = DSColors.ember2
        public static let ink       = DSColors.ink
        public static let mute      = DSColors.mute
        public static let dim       = DSColors.dim
        public static let danger    = DSColors.danger
        public static let glass     = DSColors.glass
        public static let glass2    = DSColors.glass2
        public static let line      = DSColors.line
    }

    // MARK: – Typography
    public enum Font {
        /// Cormorant Garamond Medium — display/titles/clock
        public static func display(_ size: CGFloat) -> SwiftUI.Font {
            .custom("CormorantGaramond-Medium", size: size)
        }
        /// Cormorant Garamond SemiBold — section headers
        public static func displaySemiBold(_ size: CGFloat) -> SwiftUI.Font {
            .custom("CormorantGaramond-SemiBold", size: size)
        }
        /// Inter Regular 15 — body
        public static let body    = SwiftUI.Font.custom("Inter-Regular",   size: 15)
        /// Inter Medium 12 — labels
        public static let label   = SwiftUI.Font.custom("Inter-Medium",    size: 12)
        /// Inter SemiBold 15
        public static let bodyMed = SwiftUI.Font.custom("Inter-Medium",    size: 15)
        /// Inter 12 — captions
        public static let caption = SwiftUI.Font.custom("Inter-Regular",   size: 12)
        /// Inter SemiBold 13 — chip labels
        public static let chip    = SwiftUI.Font.custom("Inter-SemiBold",  size: 13)

        /// Inter font convenience matching View.ui
        public static func ui(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            let name: String
            switch weight {
            case .semibold, .bold, .heavy, .black: name = "Inter-SemiBold"
            case .medium: name = "Inter-Medium"
            default: name = "Inter-Regular"
            }
            return .custom(name, size: size)
        }
    }

    // MARK: – Radii
    public enum Radius {
        public static let card:  CGFloat = 28
        public static let tile:  CGFloat = 20
        public static let small: CGFloat = 14
        public static let pill:  CGFloat = 999
    }
}

// MARK: - Font convenience

extension View {
    /// Inter body/label shorthand
    func ui(_ size: CGFloat, weight: SwiftUI.Font.Weight = .regular) -> some View {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "Inter-SemiBold"
        case .medium: name = "Inter-Medium"
        default: name = "Inter-Regular"
        }
        return self.font(.custom(name, size: size))
    }
}

// MARK: - GlassCard

/// Full glass card — .ultraThinMaterial + tint + 1 px line stroke + radius 28 + drop shadow.
struct GlassCard<Content: View>: View {
    let radius: CGFloat
    let padding: CGFloat
    let content: () -> Content

    init(radius: CGFloat = DS.Radius.card, padding: CGFloat = 18, @ViewBuilder content: @escaping () -> Content) {
        self.radius = radius
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(DSColors.glass)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .stroke(DSColors.line, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
            }
    }
}

extension View {
    func glassCard(radius: CGFloat = DS.Radius.card, padding: CGFloat = 18) -> some View {
        GlassCard(radius: radius, padding: padding) { self }
    }
}

// MARK: - GlassButtonStyle

enum GlassButtonKind { case primary, secondary, ember, ghost }

struct GlassButtonStyle: ButtonStyle {
    var kind: GlassButtonKind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .ui(15, weight: .semibold)
            .padding(.horizontal, 24)
            .frame(height: 52)
            .foregroundStyle(labelColor)
            .background(bg.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).stroke(strokeColor, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var labelColor: SwiftUI.Color {
        switch kind {
        case .primary: return SwiftUI.Color(hex: "18221B")
        case .ember:   return SwiftUI.Color(hex: "1B0F08")
        case .secondary, .ghost: return DSColors.ink
        }
    }

    @ViewBuilder private var bg: some View {
        switch kind {
        case .primary:   DSColors.sage
        case .ember:     LinearGradient(colors: [DSColors.ember, SwiftUI.Color(hex: "C4562E")], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .secondary: DSColors.glass
        case .ghost:     SwiftUI.Color.clear
        }
    }

    private var strokeColor: SwiftUI.Color {
        switch kind {
        case .primary:   DSColors.sage.opacity(0.3)
        case .ember:     DSColors.ember.opacity(0.3)
        case .secondary: DSColors.line
        case .ghost:     .clear
        }
    }
}

// MARK: - IconButton

/// Round 44-pt glass icon button.
struct IconButton: View {
    let systemName: String
    var tint: SwiftUI.Color = DSColors.ink
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.38, weight: .light))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(DSColors.glass, in: Circle())
                .overlay(Circle().stroke(DSColors.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chip

struct DSChip: View {
    let title: String
    var selected: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) { label }
                    .buttonStyle(.plain)
            } else {
                label
            }
        }
    }

    private var label: some View {
        Text(title)
            .font(DS.Font.chip)
            .foregroundStyle(selected ? DS.Color.sage : DS.Color.ink)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? DS.Color.sage.opacity(0.18) : SwiftUI.Color.white.opacity(0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(selected ? DS.Color.sage : DS.Color.line, lineWidth: 1)
            )
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    init(_ title: String) {
        self.title = title
    }

    init<T: View>(_ title: String, trailing: T) {
        self.title = title
        self.trailing = AnyView(trailing)
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .font(DS.Font.displaySemiBold(20))
                .tracking(3)
                .foregroundStyle(DS.Color.ink)
            Rectangle()
                .fill(DS.Color.line)
                .frame(height: 1)
                .layoutPriority(-1)
            if let t = trailing { t }
        }
    }
}

// MARK: - DSToggleStyle

struct DSToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? DS.Color.sage : SwiftUI.Color.white.opacity(0.12))
                    .overlay(Capsule().stroke(DS.Color.line, lineWidth: 1))
                    .frame(width: 56, height: 32)
                Circle()
                    .fill(configuration.isOn ? SwiftUI.Color(hex: "18221B") : SwiftUI.Color(hex: "CFD6CF"))
                    .frame(width: 24, height: 24)
                    .padding(4)
            }
            .onTapGesture { withAnimation(.spring(duration: 0.25)) { configuration.isOn.toggle() } }
        }
    }
}

// MARK: - ProgressBar

struct DSProgressBar: View {
    let value: Double   // 0…1
    var tint: SwiftUI.Color = DS.Color.sage
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(SwiftUI.Color.white.opacity(0.1)).frame(height: height)
                Capsule()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * CGFloat(min(1, max(0, value)))), height: height)
            }
        }
        .frame(height: height)
    }
}

// MARK: - AtmosphereBackground

typealias Chip = DSChip
typealias ProgressBar = DSProgressBar

/// Full-screen background from AppStorage("bgTheme"): sea / fog / city / concrete.
struct AtmosphereBackground: View {
    @AppStorage("bgTheme") private var theme: String = "sea"

    init() {}

    var body: some View {
        let valid = ["sea", "fog", "city", "concrete"]
        let safeTheme = valid.contains(theme) ? theme : "sea"
        ZStack {
            let img = "bg_\(safeTheme)"
            Image(img)
                .resizable()
                .scaledToFill()
                .saturation(0.8)
                .ignoresSafeArea()
            LinearGradient(
                stops: [
                    .init(color: SwiftUI.Color(red: 14/255, green: 18/255, blue: 16/255).opacity(0.55), location: 0),
                    .init(color: SwiftUI.Color(red: 14/255, green: 18/255, blue: 16/255).opacity(0.78), location: 0.45),
                    .init(color: SwiftUI.Color(red: 10/255, green: 12/255, blue: 11/255).opacity(0.9),  location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - ModuleTile (DS version)

/// 88 pt glass tile for the launcher grid.
struct DSModuleTile: View {
    let info: ModuleInfo
    var hasBadge: Bool = false
    var badgeLabel: String? = nil

    var body: some View {
        let tint = SwiftUI.Color(hex: info.tint)
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(info.emoji)
                .font(.system(size: 30))
            Text(info.title)
                .font(DS.Font.label)
                .tracking(0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(DS.Color.ink)
            if !info.ready {
                Text(info.wave)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.dim)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                        .fill(tint.opacity(info.ready ? 0.14 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.tile, style: .continuous)
                        .stroke(tint.opacity(info.ready ? 0.5 : 0.18), lineWidth: 1)
                )
        }
        .opacity(info.ready ? 1.0 : 0.65)
        .overlay(alignment: .topTrailing) {
            if hasBadge {
                if let label = badgeLabel {
                    Text(label)
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Color.ember2)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(DS.Color.ember.opacity(0.25), in: Capsule())
                        .overlay(Capsule().stroke(DS.Color.ember2.opacity(0.5), lineWidth: 1))
                        .padding(6)
                } else {
                    Circle()
                        .fill(DS.Color.ember)
                        .frame(width: 10, height: 10)
                        .padding(8)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
