import SwiftUI
import UserNotifications

@main
struct SanyaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            LauncherView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .environment(\.locale, Fmt.ru)
                .onOpenURL { Router.shared.open($0) }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Notifier.requestIfNeeded()
        LiveActivityManager.shared.endAll()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

enum AppEnv {
    static let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")
}
