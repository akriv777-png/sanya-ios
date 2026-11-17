import ActivityKit
import SwiftUI

/// Одна общая Live Activity на всё приложение: таймер, смена, плеер или питомец.
public struct SanyaActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var subtitle: String
        public var start: Date
        public var end: Date
        public var colorHex: String
        public var isPlaying: Bool
        public var progress: Double

        // Pet integration fields (Plan C10)
        public var petEmotion: String?
        public var petSatiety: Double?
        public var petEnergy: Double?
        public var petMood: Double?

        public init(
            title: String,
            subtitle: String,
            start: Date,
            end: Date,
            colorHex: String,
            isPlaying: Bool,
            progress: Double,
            petEmotion: String? = nil,
            petSatiety: Double? = nil,
            petEnergy: Double? = nil,
            petMood: Double? = nil
        ) {
            self.title = title
            self.subtitle = subtitle
            self.start = start
            self.end = end
            self.colorHex = colorHex
            self.isPlaying = isPlaying
            self.progress = progress
            self.petEmotion = petEmotion
            self.petSatiety = petSatiety
            self.petEnergy = petEnergy
            self.petMood = petMood
        }
    }

    /// "timer" | "shift" | "player" | "pet"
    public var kind: String
    public var symbol: String

    public init(kind: String, symbol: String) {
        self.kind = kind
        self.symbol = symbol
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count != 6 { s = "FF3B5C" }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Столбики эквалайзера. Высоты зависят от seed — при каждом обновлении активности они плавно меняются.
public struct EqualizerBars: View {
    public let tint: Color
    public let playing: Bool
    public let seed: Int
    public let height: CGFloat
    public var count: Int = 5

    public init(tint: Color, playing: Bool, seed: Int, height: CGFloat, count: Int = 5) {
        self.tint = tint
        self.playing = playing
        self.seed = seed
        self.height = height
        self.count = count
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                let v: Double = playing ? 0.3 + 0.7 * abs(sin(Double(seed) * 0.37 + Double(i) * 1.3)) : 0.2
                Capsule().fill(tint).frame(width: 3, height: max(3, height * CGFloat(v)))
            }
        }
        .frame(height: height)
    }
}
