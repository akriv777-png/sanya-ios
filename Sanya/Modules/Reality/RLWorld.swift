import Foundation
import CoreGraphics
import SpriteKit

/// Painted, image-based zones. Coordinates in this file are authored in IMAGE pixels
/// (origin top-left, 1280×720) and converted to scene space (origin bottom-left).
struct RLDoor { let rect: CGRect; let to: RLZone; let spawn: CGPoint; let label: String; let open: Bool }
enum RLInteractKind: String { case sleep, cook, terminal, couch, shift, jukebox, shopCounter, vending, noodle, railing, trash, mirror }
struct RLInteract { let at: CGPoint; let kind: RLInteractKind; let label: String; var radius: CGFloat = 60 }
struct RLLightDef { let at: CGPoint; let color: SKColor; let falloff: CGFloat; var flicker = false }
struct RLPuddle { let at: CGPoint; let size: CGSize }
struct RLSign { let text: String; let at: CGPoint; let color: SKColor; let size: CGFloat; var flicker = false }

struct RLZoneMap {
    let zone: RLZone
    let bg: String
    let size = CGSize(width: 1280, height: 720)
    var walk: [[CGPoint]] = []
    var block: [[CGPoint]] = []
    var spots: [String: CGPoint] = [:]
    var doors: [RLDoor] = []
    var interacts: [RLInteract] = []
    var lights: [RLLightDef] = []
    var puddles: [RLPuddle] = []
    var signs: [RLSign] = []
    var steam: [CGPoint] = []
    var walkerLanes: [[CGPoint]] = []
    var ambient: SKColor = SKColor(red: 0.62, green: 0.6, blue: 0.72, alpha: 1)
    var rain = true

    static func img(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: 720 - y) }
    static func poly(_ pts: [(CGFloat, CGFloat)]) -> [CGPoint] { pts.map { img($0.0, $0.1) } }

    private static func inside(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        var c = false; var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y + 0.0001) + a.x { c.toggle() }
            j = i
        }
        return c
    }
    func walkable(_ p: CGPoint) -> Bool {
        guard walk.contains(where: { RLZoneMap.inside(p, $0) }) else { return false }
        return !block.contains(where: { RLZoneMap.inside(p, $0) })
    }
    /// Moves along the vector, sliding along walls.
    func slide(from p: CGPoint, by v: CGVector, r: CGFloat = 7) -> CGPoint {
        func ok(_ q: CGPoint) -> Bool { walkable(q) && walkable(CGPoint(x: q.x - r, y: q.y)) && walkable(CGPoint(x: q.x + r, y: q.y)) && walkable(CGPoint(x: q.x, y: q.y + r * 0.6)) }
        let full = CGPoint(x: p.x + v.dx, y: p.y + v.dy)
        if ok(full) { return full }
        let xOnly = CGPoint(x: p.x + v.dx, y: p.y)
        if ok(xOnly) { return xOnly }
        let yOnly = CGPoint(x: p.x, y: p.y + v.dy)
        if ok(yOnly) { return yOnly }
        return p
    }

    // MARK: grid path (16 px cells)
    func path(from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        let cs: CGFloat = 16
        let W = Int(size.width / cs), H = Int(size.height / cs)
        func cell(_ p: CGPoint) -> (Int, Int) { (max(0, min(W - 1, Int(p.x / cs))), max(0, min(H - 1, Int(p.y / cs)))) }
        func center(_ c: (Int, Int)) -> CGPoint { CGPoint(x: CGFloat(c.0) * cs + cs / 2, y: CGFloat(c.1) * cs + cs / 2) }
        let s = cell(a), g = cell(b)
        var prev = [Int](repeating: -1, count: W * H)
        var q = [s.1 * W + s.0]; prev[q[0]] = q[0]; var head = 0
        let goal = g.1 * W + g.0
        while head < q.count {
            let cur = q[head]; head += 1
            if cur == goal { break }
            let cx = cur % W, cy = cur / W
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)] {
                let nx = cx + dx, ny = cy + dy
                guard nx >= 0, ny >= 0, nx < W, ny < H else { continue }
                let n = ny * W + nx
                if prev[n] != -1 { continue }
                if n != goal && !walkable(center((nx, ny))) { continue }
                prev[n] = cur; q.append(n)
            }
        }
        guard prev[goal] != -1 else { return [b] }
        var out: [CGPoint] = [b]; var cur = prev[goal]
        while cur != prev[cur] { out.append(center((cur % W, cur / W))); cur = prev[cur] }
        out.reverse()
        // thin the path: keep every 2nd waypoint
        return out.enumerated().filter { $0.offset % 2 == 1 || $0.offset == out.count - 1 }.map { $0.element }
    }

    func randomWalkable(near p: CGPoint, radius: CGFloat) -> CGPoint {
        for _ in 0..<12 {
            let q = CGPoint(x: p.x + .random(in: -radius...radius), y: p.y + .random(in: -radius...radius))
            if walkable(q) { return q }
        }
        return p
    }
}

enum RLWorld {
    static let street = makeStreet()
    static let apartment = makeApartment()
    static let bar = makeBar()
    static func map(_ z: RLZone) -> RLZoneMap {
        switch z { case .apartment: return apartment; case .bar: return bar; default: return street }
    }

    static let magenta = SKColor(red: 1, green: 0.24, blue: 0.75, alpha: 1)
    static let green = SKColor(red: 0.25, green: 1, blue: 0.45, alpha: 1)
    static let cyan = SKColor(red: 0.2, green: 0.9, blue: 1, alpha: 1)
    static let amber = SKColor(red: 1, green: 0.62, blue: 0.3, alpha: 1)
    static let red = SKColor(red: 1, green: 0.16, blue: 0.2, alpha: 1)

    private static func makeStreet() -> RLZoneMap {
        var m = RLZoneMap(zone: .street, bg: "rl_bg_street.jpg")
        let I = RLZoneMap.img
        m.walk = [
            RLZoneMap.poly([(560, 0), (880, 0), (905, 190), (1000, 300), (1075, 360), (1120, 410), (1030, 470), (1005, 560), (885, 600), (870, 720),
                            (520, 720), (505, 610), (300, 600), (215, 525), (250, 485), (408, 478), (412, 250), (520, 212)])
        ]
        m.spots = [
            "spawn": I(660, 540), "noodle_stand": I(434, 422), "noodle_front": I(380, 520), "noodle_side": I(470, 500),
            "bar_front": I(1000, 420), "alley_mouth": I(860, 120), "plaza_mid": I(700, 360), "plaza_low": I(640, 620),
            "railing_mid": I(760, 250), "railing_east": I(920, 520), "vending": I(560, 250),
        ]
        m.doors = [
            RLDoor(rect: CGRect(origin: I(1068, 412), size: CGSize(width: 56, height: 62)), to: .bar, spawn: I(1020, 450), label: "«Высота»", open: false),
        ]
        m.interacts = [
            RLInteract(at: I(380, 500), kind: .noodle, label: "Лапшичная", radius: 85),
        ]
        m.lights = [
            RLLightDef(at: I(250, 380), color: SKColor(red: 1, green: 0.5, blue: 0.62, alpha: 1), falloff: 1.3, flicker: true),
            RLLightDef(at: I(1092, 392), color: green, falloff: 1.4),
            RLLightDef(at: I(437, 110), color: magenta, falloff: 1.5),
        ]
        m.puddles = [
            RLPuddle(at: I(452, 330), size: CGSize(width: 90, height: 130)),
            RLPuddle(at: I(652, 420), size: CGSize(width: 70, height: 360)),
            RLPuddle(at: I(838, 300), size: CGSize(width: 70, height: 100)),
            RLPuddle(at: I(1080, 480), size: CGSize(width: 110, height: 120)),
            RLPuddle(at: I(310, 540), size: CGSize(width: 100, height: 60)),
            RLPuddle(at: I(560, 495), size: CGSize(width: 50, height: 80)),
            RLPuddle(at: I(735, 495), size: CGSize(width: 60, height: 90)),
            RLPuddle(at: I(785, 660), size: CGSize(width: 70, height: 80)),
        ]
        m.signs = [
            RLSign(text: "ЛАПША", at: I(258, 300), color: SKColor(red: 1, green: 0.55, blue: 0.85, alpha: 1), size: 24, flicker: true),
            RLSign(text: "ОРАКУЛ", at: I(437, 162), color: SKColor(red: 1, green: 0.3, blue: 0.4, alpha: 1), size: 13),
            RLSign(text: "ВЫСОТА", at: I(1062, 258), color: green, size: 19),
            RLSign(text: "БАР", at: I(1062, 236), color: green, size: 12, flicker: true),
        ]
        m.steam = [I(370, 272), I(330, 300)]
        m.walkerLanes = [
            [I(720, -40), I(700, 300), I(640, 760)],
            [I(820, 760), I(760, 400), I(760, -40)],
            [I(240, 560), I(600, 560), I(950, 520), I(1100, 420)],
            [I(600, -40), I(560, 260), I(420, 500), I(250, 540)],
        ]
        return m
    }

    private static func makeApartment() -> RLZoneMap {
        var m = RLZoneMap(zone: .apartment, bg: "rl_bg_apartment.jpg")
        let I = RLZoneMap.img
        m.walk = [RLZoneMap.poly([(240, 190), (1000, 190), (1040, 330), (1000, 470), (1060, 640), (230, 640), (220, 560), (480, 560), (420, 430)])]
        m.spots = ["spawn": I(640, 620)]
        m.doors = [RLDoor(rect: CGRect(origin: I(560, 715), size: CGSize(width: 160, height: 40)), to: .street, spawn: I(660, 540), label: "На улицу", open: true)]
        m.interacts = [
            RLInteract(at: I(380, 360), kind: .sleep, label: "Лечь спать", radius: 90),
            RLInteract(at: I(900, 280), kind: .terminal, label: "Терминал", radius: 70),
            RLInteract(at: I(1010, 400), kind: .cook, label: "Плита", radius: 70),
            RLInteract(at: I(300, 560), kind: .couch, label: "Упасть на диван", radius: 80),
        ]
        m.lights = [
            RLLightDef(at: I(930, 200), color: cyan, falloff: 1.5, flicker: true),
            RLLightDef(at: I(830, 90), color: magenta, falloff: 1.6),
            RLLightDef(at: I(180, 450), color: amber, falloff: 1.4),
        ]
        m.ambient = SKColor(red: 0.62, green: 0.58, blue: 0.7, alpha: 1)
        m.rain = false
        return m
    }

    private static func makeBar() -> RLZoneMap {
        var m = RLZoneMap(zone: .bar, bg: "rl_bg_bar.jpg")
        let I = RLZoneMap.img
        m.walk = [RLZoneMap.poly([(300, 330), (650, 250), (900, 230), (1000, 300), (960, 520), (820, 560), (700, 560), (430, 540), (280, 430)])]
        m.spots = ["spawn": I(620, 520), "bar_alex": I(520, 230), "bar_tati": I(600, 210), "bar_office": I(760, 140)]
        m.doors = [RLDoor(rect: CGRect(origin: I(560, 600), size: CGSize(width: 110, height: 50)), to: .street, spawn: I(1020, 450), label: "Лифт вниз", open: true)]
        m.interacts = [RLInteract(at: I(560, 300), kind: .shift, label: "Стойка", radius: 110), RLInteract(at: I(720, 120), kind: .jukebox, label: "Музыкальный автомат", radius: 70)]
        m.lights = [RLLightDef(at: I(450, 160), color: amber, falloff: 1.4), RLLightDef(at: I(720, 110), color: magenta, falloff: 1.5, flicker: true)]
        m.rain = false
        return m
    }
}
