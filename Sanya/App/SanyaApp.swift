import SwiftUI
import UserNotifications

@main
struct SanyaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ZStack {
                LauncherView()
                PetOverlayView()
            }
            .preferredColorScheme(.dark)
            .tint(DS.Color.sage)
            .environment(\.locale, Fmt.ru)
            .onOpenURL { Router.shared.open($0) }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = PetBridge.shared
        UNUserNotificationCenter.current().delegate = self
        Notifier.requestIfNeeded()
        LiveActivityManager.shared.endAll()
        // Check for upcoming shifts on foreground
        checkUpcomingShift()
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        checkUpcomingShift()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    private func checkUpcomingShift() {
        guard let next = ShiftStore.shared.nextShift else { return }
        let mins = Int(next.start.timeIntervalSinceNow / 60)
        guard mins > 0, mins <= 120 else { return }
        EventBus.shared.emit(.shiftUpcoming(minutes: mins))
    }
}

enum AppEnv {
    static let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")
}
