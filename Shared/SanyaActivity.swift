import ActivityKit
import SwiftUI

/// Одна общая Live Activity на всё приложение: таймер, смена или плеер.
struct SanyaActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var subtitle: String
        var start: Date
        var end: Date
        var colorHex: String
        var isPlaying: Bool
        var progress: Double
    }
    /// "timer" | "shift" | "player"
    var kind: String
    var symbol: String
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
struct EqualizerBars: View {
    let tint: Color
    let playing: Bool
    let seed: Int
    let height: CGFloat
    var count: Int = 5

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                let v: Double = playing ? 0.3 + 0.7 * abs(sin(Double(seed) * 0.37 + Double(i) * 1.3)) : 0.2
                Capsule().fill(tint).frame(width: 3, height: max(3, height * CGFloat(v)))
            }
        }
        .frame(height: height)
    }
}
