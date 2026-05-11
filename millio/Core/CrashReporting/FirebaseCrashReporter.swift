import Foundation
import FirebaseCrashlytics

final class FirebaseCrashReporter: CrashReporter {
    private let crashlytics = Crashlytics.crashlytics()
    
    func setEnabled(_ enabled: Bool) {
        crashlytics.setCrashlyticsCollectionEnabled(enabled)
    }

    func setUserID(_ id: String?) {
        crashlytics.setUserID(id ?? "")
    }

    func log(_ message: String) {
        crashlytics.log(message)
    }
    
    func setCustomValue(_ value: Any, forKey key: String) {
        crashlytics.setCustomValue(value, forKey: key)
    }
    
    func record(error: Error) {
        crashlytics.record(error: error)
    }
}

