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

// MARK: - Live Activity

struct SanyaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SanyaActivityAttributes.self) { context in
            LockScreenView(a: context.attributes, st: context.state)
                .activityBackgroundTint(Color.black.opacity(0.78))
                .activitySystemActionForegroundColor(DSColors.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { ExpandedLeading(a: context.attributes, st: context.state) }
                DynamicIslandExpandedRegion(.trailing) { ExpandedTrailing(a: context.attributes, st: context.state) }
                DynamicIslandExpandedRegion(.center) { ExpandedCenter(a: context.attributes, st: context.state) }
                DynamicIslandExpandedRegion(.bottom) { ExpandedBottom(a: context.attributes, st: context.state) }
            } compactLeading: {
                CompactLeading(a: context.attributes, st: context.state)
            } compactTrailing: {
                CompactTrailing(a: context.attributes, st: context.state)
            } minimal: {
                MinimalView(a: context.attributes, st: context.state)
            }
            .keylineTint(DSColors.sage)
            .widgetURL(URL(string: context.attributes.kind == "pet" ? "sanya://pet" : "sanya://\(context.attributes.kind == "shift" ? "shifts" : (context.attributes.kind == "timer" ? "timers" : "player"))"))
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
