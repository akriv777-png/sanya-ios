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

struct CoverBadge: View {
    let symbol: String
    let tint: Color
    let size: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(LinearGradient(colors: [tint, tint.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct IslandTrailing: View {
    let context: ActivityViewContext<SanyaActivityAttributes>
    let barHeight: CGFloat
    let width: CGFloat
    var body: some View {
        let tint = Color(hex: context.state.colorHex)
        if context.attributes.kind == "player" {
            EqualizerBars(tint: tint, playing: context.state.isPlaying, seed: Int(context.state.progress * 997), height: barHeight)
        } else {
            Text(timerInterval: context.state.start...max(context.state.start, context.state.end), countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(tint)
                .frame(width: width)
        }
    }
}

struct ProgressLine: View {
    let context: ActivityViewContext<SanyaActivityAttributes>
    var body: some View {
        let tint = Color(hex: context.state.colorHex)
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

struct LockScreenView: View {
    let context: ActivityViewContext<SanyaActivityAttributes>
    var body: some View {
        let tint = Color(hex: context.state.colorHex)
        HStack(spacing: 12) {
            CoverBadge(symbol: context.attributes.symbol, tint: tint, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.title).font(.headline).lineLimit(1)
                Text(context.state.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                ProgressLine(context: context)
            }
            IslandTrailing(context: context, barHeight: 26, width: 70)
        }
        .padding(14)
        .foregroundStyle(.white)
    }
}

struct SanyaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SanyaActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let tint = Color(hex: context.state.colorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CoverBadge(symbol: context.attributes.symbol, tint: tint, size: 52)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandTrailing(context: context, barHeight: 30, width: 80)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text(context.state.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressLine(context: context)
                }
            } compactLeading: {
                CoverBadge(symbol: context.attributes.symbol, tint: tint, size: 22)
            } compactTrailing: {
                IslandTrailing(context: context, barHeight: 14, width: 44)
            } minimal: {
                Image(systemName: context.attributes.symbol).foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

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
            .foregroundStyle(.white)
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color(hex: "8A5CFF"), Color(hex: "0B0B12")], startPoint: .top, endPoint: .bottom)
            }
            .widgetURL(URL(string: "sanya://assistant"))
        }
        .configurationDisplayName("Саня")
        .description("Быстрый вызов Сани")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}
