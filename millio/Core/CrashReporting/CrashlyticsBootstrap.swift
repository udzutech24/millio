import Foundation
import FirebaseCore

struct CrashlyticsBootstrapEnvironment: Equatable {
    let isDebug: Bool
    let isUnitTesting: Bool
    let overrideEnabled: Bool?
    
    static func current() -> CrashlyticsBootstrapEnvironment {
        let env = ProcessInfo.processInfo.environment
        let isUnitTesting = env["XCTestConfigurationFilePath"] != nil
        let overrideEnabled: Bool?
        if let raw = env["MILLIO_CRASHLYTICS_ENABLED"]?.lowercased() {
            if ["1", "true", "yes", "y"].contains(raw) {
                overrideEnabled = true
            } else if ["0", "false", "no", "n"].contains(raw) {
                overrideEnabled = false
            } else {
                overrideEnabled = nil
            }
        } else {
            overrideEnabled = nil
        }
        
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        
        return CrashlyticsBootstrapEnvironment(
            isDebug: isDebug,
            isUnitTesting: isUnitTesting,
            overrideEnabled: overrideEnabled
        )
    }
    
    var isCrashlyticsEnabled: Bool {
        if let overrideEnabled { return overrideEnabled }
        if isUnitTesting { return false }
        if isDebug { return false }
        return true
    }
}

protocol FirebaseConfiguring {
    func configureIfNeeded()
}

struct DefaultFirebaseConfigurator: FirebaseConfiguring {
    func configureIfNeeded() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }
}

final class CrashlyticsBootstrap {
    private let environment: CrashlyticsBootstrapEnvironment
    private let firebase: FirebaseConfiguring
    private let crashReporting: CrashReportingSink
    private let reporterFactory: () -> CrashReporter
    private var started = false
    
    init(
        environment: CrashlyticsBootstrapEnvironment = .current(),
        firebase: FirebaseConfiguring = DefaultFirebaseConfigurator(),
        crashReporting: CrashReportingSink = DefaultCrashReportingSink(),
        reporterFactory: @escaping () -> CrashReporter = { FirebaseCrashReporter() }
    ) {
        self.environment = environment
        self.firebase = firebase
        self.crashReporting = crashReporting
        self.reporterFactory = reporterFactory
    }
    
    func start() {
        guard !started else { return }
        started = true
        
        firebase.configureIfNeeded()
        
        crashReporting.setReporter(reporterFactory())
        crashReporting.setEnabled(environment.isCrashlyticsEnabled)
        crashReporting.setCustomValue(environment.isDebug, forKey: "is_debug")
        crashReporting.setCustomValue(environment.isUnitTesting, forKey: "is_unit_testing")
    }
}
