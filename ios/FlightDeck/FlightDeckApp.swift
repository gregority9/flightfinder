import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let value = token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(value, forKey: "apnsToken")
        Task { try? await registerDevice(value) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        UserDefaults.standard.set("APNs niedostępne. Sprawdź podpis aplikacji i uprawnienie Push Notifications; możesz użyć ntfy.", forKey: "pushError")
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
func registerDevice(_ token: String) async throws {
    struct Body: Encodable { let token: String }
    let _: OK = try await API.saved.request("/v1/devices", method: "POST", body: API.saved.encode(Body(token: token)))
}
@main struct FlightDeckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = FlightStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).preferredColorScheme(.dark).tint(Theme.lime)
        }
    }
}
