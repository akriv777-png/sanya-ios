import XCTest

/// Прогулка по приложению для видео-отчётов. Каждый тест записывается в отдельное видео в CI.
final class SanyaUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-petDemo"]
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
        if e.waitForExistence(timeout: timeout) {
            e.tap()
        }
    }

    func chip(_ i: Int) {
        let e = el("chip_\(i)")
        guard e.waitForExistence(timeout: 6) else { return }
        let w = app.frame.width
        let bar = app.scrollViews.containing(.button, identifier: "chip_0").firstMatch
        if bar.exists {
            if e.frame.maxX > w - 4 { bar.swipeLeft(); pause(0.8) }
            else if e.frame.minX < 4 { bar.swipeRight(); pause(0.8) }
        }
        e.tap()
    }

    func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.waitForExistence(timeout: 3) {
            b.tap()
        }
        pause(1.2)
    }

    func showIsland(_ name: String) {
        XCUIDevice.shared.press(.home)
        pause(3)
        shot(name)
        app.activate()
        pause(1.5)
    }

    // MARK: - Tour 1: Launcher & Core Modules

    func testTour1() {
        shot("v02_01_home")
        app.swipeUp()
        pause(1.5)
        shot("v02_02_home_modules")
        app.swipeDown()
        pause(1)

        // Settings
        tap("dock_settings")
        pause(1.5)
        tap("theme_fog", timeout: 3)
        pause(1)
        shot("v02_03_settings")
        let done = app.buttons["Готово"]
        if done.waitForExistence(timeout: 3) {
            done.tap()
        } else {
            app.swipeDown()
        }
        pause(1.5)

        // Assistant chat
        tap("tile_assistant")
        pause(2)
        chip(0)
        pause(2.5)
        shot("v02_04_chat")
        back()

        // Shifts
        tap("tile_shifts")
        pause(2)
        shot("v02_05_shifts")
        back()

        // Timers
        tap("tile_timers")
        pause(2)
        shot("v02_06_timers")
        back()
    }

    // MARK: - Tour 2: Pet Module

    func testTour2() {
        tap("tile_pet")
        pause(2)
        shot("v02_07_pet")

        // Preview transitions across 5-6 emotions
        for emo in ["happy", "sleep", "music", "angry", "bored", "calm"] {
            tap("emo_\(emo)", timeout: 2)
            pause(1.5)
        }

        // Feed pet
        tap("pet_feed")
        pause(1.5)
        tap("food_0", timeout: 3)
        pause(2)
        shot("v02_08_pet_fed")

        // Play with pet & view suggestions
        tap("pet_play")
        pause(2)
        shot("v02_09_pet_suggest")

        // Pet Diary
        tap("pet_diary")
        pause(2)
        shot("v02_10_diary")
        back()

        // Live Activity on Dynamic Island
        tap("pet_island")
        pause(1.5)
        showIsland("v02_11_island_pet")
        back()
    }

    // MARK: - Tour 3: Player, Island, Counter

    func testTour3() {
        tap("tile_player")
        pause(2)
        tap("player_toggle")
        pause(3)
        shot("v02_12_player")

        // Player on Dynamic Island
        showIsland("v02_13_island_player")
        back()

        // Launcher with pet overlay
        shot("v02_14_home_pet_overlay")

        // Counter module
        app.swipeUp()
        pause(1)
        tap("tile_counter")
        pause(2)

        // Over limit triggers grumble
        tap("counter_plus_energy")
        pause(1.5)
        tap("counter_plus_energy")
        pause(1.5)
        tap("counter_plus_energy")
        pause(2)
        shot("v02_15_counter_grumble")
        back()
    }
}
