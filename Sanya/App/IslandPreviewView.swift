import SwiftUI

/// Renders the real island views (Shared/IslandViews.swift) on black pills, so the look can be checked
/// without long-pressing the Dynamic Island. Settings → «Предпросмотр острова».
struct IslandPreviewView: View {
    @ObservedObject private var store = PetStore.shared
    @ObservedObject private var engine = PetEngine.shared

    private var petSprite: String { EmotionRegistry.baseSprite(for: engine.currentEmotion.id) }

    private func state(_ title: String, _ sub: String, minutes: Double, playing: Bool = false, progress: Double = 0.4) -> SanyaActivityAttributes.ContentState {
        SanyaActivityAttributes.ContentState(
            title: title, subtitle: sub, start: Date(), end: Date().addingTimeInterval(minutes * 60),
            colorHex: "A8C5A0", isPlaying: playing, progress: progress,
            petEmotion: petSprite, petSatiety: store.stats.satiety, petEnergy: store.stats.energy, petMood: store.stats.mood)
    }

    private var samples: [(String, SanyaActivityAttributes, SanyaActivityAttributes.ContentState)] {
        [
            ("Питомец", SanyaActivityAttributes(kind: "pet", symbol: "heart.fill"),
             state(store.name, "\(store.bondLevel.name) · \(engine.currentEmotion.name)", minutes: 60, progress: store.stats.mood)),
            ("Плеер", SanyaActivityAttributes(kind: "player", symbol: "chart.bar.fill"),
             state("Ночная смена", "Саня · демо", minutes: 3, playing: true, progress: 0.42)),
            ("Таймер", SanyaActivityAttributes(kind: "timer", symbol: "timer"),
             state("Помодоро", "фокус", minutes: 25)),
        ]
    }

    var body: some View {
        ZStack {
            AtmosphereBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(samples, id: \.0) { item in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(item.0)
                            compact(item.1, item.2)
                            HStack(spacing: 12) {
                                Circle().fill(Color.black).frame(width: 37, height: 37)
                                    .overlay(MinimalView(a: item.1, st: item.2))
                                Text("минимальный").font(DS.Font.caption).foregroundStyle(DS.Color.mute)
                            }
                            expanded(item.1, item.2)
                        }
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Остров")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("island_preview_screen")
    }

    private func compact(_ a: SanyaActivityAttributes, _ st: SanyaActivityAttributes.ContentState) -> some View {
        HStack(spacing: 0) {
            CompactLeading(a: a, st: st).frame(width: 40)
            Spacer(minLength: 110)   // camera area
            CompactTrailing(a: a, st: st).frame(minWidth: 40)
        }
        .padding(.horizontal, 10)
        .frame(height: 37)
        .background(Capsule().fill(Color.black))
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
    }

    private func expanded(_ a: SanyaActivityAttributes, _ st: SanyaActivityAttributes.ContentState) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ExpandedLeading(a: a, st: st)
                ExpandedCenter(a: a, st: st)
                ExpandedTrailing(a: a, st: st)
            }
            ExpandedBottom(a: a, st: st)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Color.black))
    }
}
