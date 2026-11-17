import WidgetKit
import SwiftUI
import ActivityKit

@main
struct SanyaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SanyaLiveActivity()
        SanyaQuickWidget()
    }
}

// MARK: - Mini Bar Helper

private func petMiniBar(label: String, value: Double, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(height: 3)
            Capsule()
                .fill(color)
                .frame(width: max(2, 44 * min(1.0, max(0.0, CGFloat(value)))), height: 3)
        }
        .frame(width: 44, height: 3)
    }
}

// MARK: - CoverBadge

struct CoverBadge: View {
    let symbol: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(LinearGradient(colors: [tint.opacity(0.35), DSColors.glass], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                        .stroke(DSColors.line, lineWidth: 1)
                )
            Image(systemName: symbol)
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(DSColors.ink)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - IslandTrailing

struct IslandTrailing: View {
    let context: ActivityViewContext<SanyaActivityAttributes>
    let barHeight: CGFloat
    let width: CGFloat

    var body: some View {
        let tint = DSColors.sage
        if context.attributes.kind == "player" {
            PlayerIslandTrailing(
                symbol: context.attributes.symbol,
                tint: tint,
                playing: context.state.isPlaying,
                progress: context.state.progress,
                barHeight: barHeight
            )
        } else if context.attributes.kind == "pet" {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10))
                Text("\(Int((context.state.petMood ?? 0.7) * 100))%")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(DSColors.sage)
        } else {
            Text(timerInterval: context.state.start...max(context.state.start, context.state.end), countsDown: true)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(tint)
                .frame(width: width)
        }
    }
}

struct PlayerIslandTrailing: View {
    let symbol: String
    let tint: Color
    let playing: Bool
    let progress: Double
    let barHeight: CGFloat

    var body: some View {
        switch symbol {
        case "waveform":
            // Wave style
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<6, id: \.self) { i in
                    let seed = Int(progress * 997) + i * 2
                    let v = playing ? 0.3 + 0.7 * abs(sin(Double(seed) * 0.4 + Double(i) * 0.8)) : 0.2
                    Capsule().fill(tint).frame(width: 2.5, height: max(3, barHeight * CGFloat(v)))
                }
            }
        case "waveform.path":
            // Pulse style
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    let seed = Int(progress * 800) + i * 3
                    let op = playing ? 0.3 + 0.7 * abs(sin(Double(seed) * 0.5)) : 0.3
                    Circle().fill(tint.opacity(op)).frame(width: 5, height: 5)
                }
            }
        default:
            // Bars style
            EqualizerBars(tint: tint, playing: playing, seed: Int(progress * 997), height: barHeight)
        }
    }
}

// MARK: - ProgressLine

struct ProgressLine: View {
    let context: ActivityViewContext<SanyaActivityAttributes>

    var body: some View {
        let tint = DSColors.sage
        if context.attributes.kind == "player" && !context.state.isPlaying {
            ProgressView(value: min(max(context.state.progress, 0), 1)).tint(tint)
        } else {
            ProgressView(timerInterval: context.state.start...max(context.state.start, context.state.end), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(tint)
        }
    }
}

// MARK: - LockScreenView

struct LockScreenView: View {
    let context: ActivityViewContext<SanyaActivityAttributes>

    var body: some View {
        let tint = DSColors.sage
        if context.attributes.kind == "pet" {
            HStack(spacing: 12) {
                PetStaticSprite(sprite: context.state.petEmotion ?? "calm", size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title)
                        .font(.headline)
                        .foregroundStyle(DSColors.ink)
                        .lineLimit(1)
                    Text(context.state.subtitle)
                        .font(.caption)
                        .foregroundStyle(DSColors.mute)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        petMiniBar(label: "Сытость", value: context.state.petSatiety ?? 0.8, color: DSColors.ember)
                        petMiniBar(label: "Энергия", value: context.state.petEnergy ?? 0.7, color: DSColors.ember2)
                        petMiniBar(label: "Настроение", value: context.state.petMood ?? 0.7, color: DSColors.sage)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11))
                    Text("\(Int((context.state.petMood ?? 0.7) * 100))%")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(DSColors.sage)
            }
            .padding(14)
        } else {
            HStack(spacing: 12) {
                if let emo = context.state.petEmotion, !emo.isEmpty {
                    PetStaticSprite(sprite: emo, size: 44)
                } else {
                    CoverBadge(symbol: context.attributes.symbol, tint: tint, size: 44)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title)
                        .font(.headline)
                        .foregroundStyle(DSColors.ink)
                        .lineLimit(1)
                    Text(context.state.subtitle)
                        .font(.caption)
                        .foregroundStyle(DSColors.mute)
                        .lineLimit(1)
                    ProgressLine(context: context)
                }
                IslandTrailing(context: context, barHeight: 26, width: 70)
            }
            .padding(14)
        }
    }
}

// MARK: - SanyaLiveActivity

struct SanyaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SanyaActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(DSColors.bgBot)
                .activitySystemActionForegroundColor(DSColors.ink)
        } dynamicIsland: { context in
            let tint = DSColors.sage
            let isPet = context.attributes.kind == "pet"

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if isPet {
                        PetStaticSprite(sprite: context.state.petEmotion ?? "calm", size: 56)
                    } else if let emo = context.state.petEmotion, !emo.isEmpty {
                        HStack(spacing: 6) {
                            CoverBadge(symbol: context.attributes.symbol, tint: tint, size: 40)
                            PetStaticSprite(sprite: emo, size: 36)
                        }
                    } else {
                        CoverBadge(symbol: context.attributes.symbol, tint: tint, size: 52)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if isPet {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 11))
                            Text("\(Int((context.state.petMood ?? 0.7) * 100))%")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(DSColors.sage)
                    } else {
                        IslandTrailing(context: context, barHeight: 30, width: 80)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.headline)
                            .foregroundStyle(DSColors.ink)
                            .lineLimit(1)
                        Text(context.state.subtitle)
                            .font(.caption)
                            .foregroundStyle(DSColors.mute)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if isPet {
                        HStack(spacing: 12) {
                            petMiniBar(label: "Сытость", value: context.state.petSatiety ?? 0.8, color: DSColors.ember)
                            petMiniBar(label: "Энергия", value: context.state.petEnergy ?? 0.7, color: DSColors.ember2)
                            petMiniBar(label: "Настроение", value: context.state.petMood ?? 0.7, color: DSColors.sage)
                        }
                    } else {
                        ProgressLine(context: context)
                    }
                }
            } compactLeading: {
                if isPet {
                    PetStaticSprite(sprite: context.state.petEmotion ?? "calm", size: 24)
                } else if let emo = context.state.petEmotion, !emo.isEmpty {
                    PetStaticSprite(sprite: emo, size: 24)
                } else {
                    CoverBadge(symbol: context.attributes.symbol, tint: tint, size: 22)
                }
            } compactTrailing: {
                if isPet {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                        Text("\(Int((context.state.petMood ?? 0.7) * 100))%")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(DSColors.sage)
                } else {
                    IslandTrailing(context: context, barHeight: 14, width: 62)
                }
            } minimal: {
                if isPet {
                    PetStaticSprite(sprite: context.state.petEmotion ?? "calm", size: 20)
                } else if let emo = context.state.petEmotion, !emo.isEmpty {
                    PetStaticSprite(sprite: emo, size: 20)
                } else {
                    Image(systemName: context.attributes.symbol).foregroundStyle(tint)
                }
            }
            .keylineTint(tint)
        }
    }
}

// MARK: - SanyaQuickWidget

struct QuickEntry: TimelineEntry { let date: Date }

struct QuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) { completion(QuickEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
        completion(Timeline(entries: [QuickEntry(date: Date())], policy: .never))
    }
}

struct SanyaQuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SanyaQuick", provider: QuickProvider()) { _ in
            VStack(spacing: 6) {
                Image(systemName: "sparkles").font(.largeTitle)
                Text("Саня").font(.headline)
            }
            .foregroundStyle(DSColors.ink)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [DSColors.sageDeep, DSColors.bgBot], startPoint: .top, endPoint: .bottom)
            }
            .widgetURL(URL(string: "sanya://assistant"))
        }
        .configurationDisplayName("Саня")
        .description("Быстрый вызов Сани")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
