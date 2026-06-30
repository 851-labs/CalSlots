import SwiftUI
import UIKit

@main
struct CalSlotsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(SyncEngine.shared)
        }
    }
}

/// Drives sync setup from `didFinishLaunching` so that HealthKit background
/// relaunches re-register the observer query even when no UI is shown.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { await SyncEngine.shared.bootstrap() }
        return true
    }
}
