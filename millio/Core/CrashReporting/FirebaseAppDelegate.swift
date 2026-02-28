import UIKit
import FirebaseCore

final class FirebaseAppDelegate: NSObject, UIApplicationDelegate {
    private let crashlyticsBootstrap = CrashlyticsBootstrap()
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        crashlyticsBootstrap.start()
        return true
    }
}
