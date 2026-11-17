import XCTest

/// Прогулка по приложению для видео-отчётов. Каждый тест записывается в отдельное видео в CI.
final class SanyaUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
        pause(2)
    }

    func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SHOT_DIR"] {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func tap(_ id: String, timeout: TimeInterval = 6) {
        let e = el(id)
        if e.waitForExistence(timeout: timeout) { e.tap() } else { XCTFail("Не нашёл \(id)") }
    }

    func chip(_ i: Int) {
        let e = el("chip_\(i)")
        guard e.waitForExistence(timeout: 6) else { XCTFail("нет chip_\(i)"); return }
        if !e.isHittable { app.scrollViews.containing(.button, identifier: "chip_0").firstMatch.swipeLeft(); pause(0.6) }
        e.tap()
    }

    func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.waitForExistence(timeout: 3) { b.tap() }
        pause(1.2)
    }

    func showIsland(_ name: String) {
        XCUIDevice.shared.press(.home)
        pause(3)
        shot(name)
        app.activate()
        pause(1.5)
    }

    func testTour1() {
        shot("01_home")
        app.swipeUp(); pause(1.5)
        shot("02_home_soon")
        app.swipeDown(); pause(1)
        tap("tile_assistant"); pause(1.5)
        chip(0); pause(2.5)
        chip(1); pause(3)
        shot("03_assistant")
        chip(3); pause(2.5)
        chip(2); pause(3)
        shot("04_assistant_timer")
        showIsland("05_island_timer")
        chip(4); pause(3)
        shot("06_shifts_from_voice")
        back()
    }

    func testTour2() {
        tap("tile_shifts"); pause(2)
        shot("07_shifts_week")
        app.swipeUp(); pause(1.2)
        app.swipeDown(); pause(0.8)
        let month = app.buttons["Месяц"]
        if month.waitForExistence(timeout: 3) { month.tap() }
        pause(1.5)
        shot("08_shifts_month")
        tap("shift_add"); pause(1.5)
        shot("09_shift_editor")
        tap("shift_save"); pause(1.5)
        if app.buttons["Неделя"].exists { app.buttons["Неделя"].tap() }
        pause(1)
        app.swipeUp(); pause(1)
        tap("shift_island"); pause(1)
        showIsland("10_island_shift")
        back()
        tap("tile_book"); pause(9)
        shot("11_book")
        app.swipeUp(); pause(2)
        shot("12_book_scroll")
        back()
    }

    func testTour3() {
        tap("tile_timers"); pause(1.5)
        tap("preset_0"); pause(1)
        tap("preset_5"); pause(2)
        shot("13_timers")
        back()
        tap("tile_player"); pause(1.5)
        tap("player_toggle"); pause(4)
        shot("14_player")
        showIsland("15_island_player")
        let flame = app.buttons["Пламя"]
        if flame.waitForExistence(timeout: 3) { flame.tap() }
        pause(2)
        showIsland("16_island_player_flame")
        back()
        shot("17_home_now_playing")
        app.swipeUp(); pause(1)
        tap("tile_vault"); pause(2)
        shot("18_coming_soon")
        back()
    }
}
