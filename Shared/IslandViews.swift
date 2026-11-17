import SwiftUI
import ActivityKit

// Island / Live Activity views. Live in Shared/ so the widget renders them AND the app can show a preview.

// MARK: - Helpers


private func petWord(_ sprite: String) -> String {
    switch PetSprites.base(sprite) {
    case "happy":  return "рад"
    case "hungry": return "жрать"
    case "sleep":  return "сплю"
    case "angry":  return "злой"
    case "music":  return "вайб"
    default:       return "спок"
    }
}

private func uiFont(_ size: CGFloat, _ weight: String = "SemiBold") -> Font { .custom("Inter-\(weight)", size: size) }

/// Pet head for the island: crisp pixels + red eye glow so it reads on pure black.
struct IslandPetHead: View {
    let sprite: String
    let size: CGFloat
    var body: some View {
        ZStack {
            RadialGradient(colors: [DSColors.danger.opacity(0.42), Color.clear],
                           center: UnitPoint(x: 0.5, y: 0.55), startRadius: 0, endRadius: size * 0.62)
            Image("pet_head_\(PetSprites.base(sprite))")
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

struct CoverBadge: View {
    let symbol: String
    let tint: Color
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.35), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(DSColors.line, lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(DSColors.ink)
        }
        .frame(width: size, height: size)
    }
}

/// Static equalizer variants for the island: bars / wave / pulse.
struct IslandEQ: View {
    let style: String     // attributes.symbol from PlayerModel.islandSymbol
    let playing: Bool
    let seed: Int
    let height: CGFloat
    var body: some View {
        switch style {
        case "waveform":
            HStack(alignment: .center, spacing: 1.5) {
                ForEach(0..<7, id: \.self) { i in
                    let v: Double = playing ? 0.25 + 0.75 * abs(sin(Double(i) * 0.9 + Double(seed) * 0.21)) : 0.18
                    Capsule().fill(DSColors.ember).frame(width: 2.2, height: max(2.5, height * CGFloat(v)))
                }
            }
            .frame(height: height)
        case "waveform.path":
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    let v: Double = playing ? 0.45 + 0.55 * abs(sin(Double(seed) * 0.5 + Double(i) * 1.1)) : 0.35
                    Circle().fill(DSColors.ember.opacity(v)).frame(width: height * 0.42 * CGFloat(0.7 + 0.3 * v), height: height * 0.42 * CGFloat(0.7 + 0.3 * v))
                }
            }
            .frame(height: height)
        default:
            EqualizerBars(tint: DSColors.ember, playing: playing, seed: seed, height: height, count: 4)
        }
    }
}

struct StatRow: View {
    let icon: String
    let value: Double
    let tint: Color
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(tint).frame(width: 12)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(tint).frame(width: max(3, g.size.width * CGFloat(min(1, max(0, value)))))
                }
            }
            .frame(height: 4)
            Text("\(Int((min(1, max(0, value))) * 100))")
                .font(uiFont(9, "Medium")).monospacedDigit().foregroundStyle(DSColors.mute).frame(width: 18, alignment: .trailing)
        }
    }
}

private func countdown(_ st: SanyaActivityAttributes.ContentState) -> some View {
    Text(timerInterval: st.start...max(st.start, st.end), countsDown: true)
        .monospacedDigit()
        .lineLimit(1)
        .multilineTextAlignment(.trailing)
}

// MARK: - Compact / minimal

struct CompactLeading: View {
    let a: SanyaActivityAttributes
    let st: SanyaActivityAttributes.ContentState
    var body: some View {
        if let e = st.petEmotion, !e.isEmpty {
            IslandPetHead(sprite: e, size: 24)
        } else {
            Image(systemName: a.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(DSColors.sage)
        }
    }
}

struct CompactTrailing: View {
    let a: SanyaActivityAttributes
    let st: SanyaActivityAttributes.ContentState
    var body: some View {
        switch a.kind {
        case "pet":
            HStack(spacing: 3) {
                Circle()
                    .trim(from: 0, to: CGFloat(min(1, max(0.02, st.petMood ?? 0.6))))
                    .stroke(DSColors.sage, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 12, height: 12)
                Text(petWord(st.petEmotion ?? "calm"))
                    .font(uiFont(12))
                    .foregroundStyle((st.petEmotion ?? "") == "angry" ? DSColors.ember : DSColors.sage)
                    .lineLimit(1)
            }
            .frame(maxWidth: 58)
        case "player":
            IslandEQ(style: a.symbol, playing: st.isPlaying, seed: Int(st.progress * 997), height: 14)
                .frame(width: 26)
        case "shift":
            countdown(st).font(uiFont(13)).foregroundStyle(DSColors.sage).frame(maxWidth: 56)
        default:
            countdown(st).font(uiFont(13)).foregroundStyle(DSColors.ember).frame(maxWidth: 56)
        }
    }
}

struct MinimalView: View {
    let a: SanyaActivityAttributes
    let st: SanyaActivityAttributes.ContentState
    var body: some View {
        if let e = st.petEmotion, !e.isEmpty {
            IslandPetHead(sprite: e, size: 20)
        } else {
            Image(systemName: a.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(DSColors.ember)
        }
    }
}

// MARK: - Expanded

struct ExpandedLeading: View {
    let a: SanyaActivityAttributes
    let st: SanyaActivityAttributes.ContentState
    var body: some View {
        Group {
            if let e = st.petEmotion, !e.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DSColors.sage.opacity(0.35), lineWidth: 1)
                    IslandPetHead(sprite: e, size: 46)
                }
                .frame(width: 54, height: 54)
            } else {
                CoverBadge(symbol: a.symbol, tint: Color(hex: st.colorHex), size: 50)
            }
        }
        .padding(.leading, 4)
    }
}

struct ExpandedCenter: View {
    let a: SanyaActivityAttributes
    let st: SanyaActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(st.title).font(uiFont(15)).foregroundStyle(DSColors.ink).lineLimit(1)
            Text(st.subtitle).font(uiFont(12, "Regular")).foregroundStyle(DSColors.mute).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ExpandedTrailing: View {
    let a: SanyaActivityAttributes
    let st: SanyaActivityAttributes.ContentState
    var body: some View {
        Group {
            switch a.kind {
            case "pet":
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int((st.petMood ?? 0.6) * 100))%").font(uiFont(20)).foregroundStyle(DSColors.sage).monospacedDigit()
                    Text("настроение").font(uiFont(9, "Medium")).foregroundStyle(DSColors.mute)
                }
            case "player":
                IslandEQ(style: a.symbol, playing: st.isPlaying, seed: Int(st.progress * 997), height: 22)
                    .frame(width: 34)
            default:
                countdown(st).font(uiFont(20)).foregroundStyle(a.kind == "shift" ? DSColors.sage : DSColors.ember).frame(maxWidth: 90)
            }
        }
        .padding(.trailing, 4)
    }
}

struct ExpandedBottom: View {
    let a: SanyaActivityAttributes
    let st: SanyaActivityAttributes.ContentState
    var body: some View {
        Group {
            if a.kind == "pet" {
                HStack(spacing: 10) {
                    StatRow(icon: "fork.knife", value: st.petSatiety ?? 0.5, tint: DSColors.ember2)
                    StatRow(icon: "bolt.fill", value: st.petEnergy ?? 0.5, tint: DSColors.sage)
                    StatRow(icon: "heart.fill", value: st.petMood ?? 0.5, tint: DSColors.danger)
                }
            } else if a.kind == "player" {
                HStack(spacing: 8) {
                    Image(systemName: st.isPlaying ? "play.fill" : "pause.fill").font(.system(size: 10)).foregroundStyle(DSColors.mute)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.14))
                            Capsule().fill(DSColors.sage).frame(width: max(3, g.size.width * CGFloat(min(1, max(0, st.progress)))))
                        }
                    }
                    .frame(height: 4)
                    if let m = st.petMood {
                        Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(DSColors.danger.opacity(0.4 + 0.6 * m))
                    }
                }
            } else {
                ProgressView(timerInterval: st.start...max(st.start.addingTimeInterval(1), st.end), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(a.kind == "shift" ? DSColors.sage : DSColors.ember)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
    }
}

// MARK: - Lock screen

struct LockScreenView: View {
    let a: SanyaActivityAttributes
    let st: SanyaActivityAttributes.ContentState
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ExpandedLeading(a: a, st: st)
                ExpandedCenter(a: a, st: st)
                ExpandedTrailing(a: a, st: st)
            }
            ExpandedBottom(a: a, st: st)
        }
        .padding(14)
    }
}

