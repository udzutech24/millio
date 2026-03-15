import Foundation
import Testing
@testable import millio

private final class MockFirebaseConfigurator: FirebaseConfiguring {
    private(set) var configureCalls = 0
    
    func configureIfNeeded() {
        configureCalls += 1
    }
}

private final class MockCrashReporter: CrashReporter {
    private let lock = NSLock()
    private var _enabledValues: [Bool] = []
    private var _logs: [String] = []
    private var _customValues: [String: Any] = [:]
    private var _recordedErrors: [Error] = []

    var enabledValues: [Bool] {
        withLock { _enabledValues }
    }

    var logs: [String] {
        withLock { _logs }
    }

    var customValues: [String: Any] {
        withLock { _customValues }
    }

    var recordedErrors: [Error] {
        withLock { _recordedErrors }
    }
    
    func setEnabled(_ enabled: Bool) {
        withLock {
            _enabledValues.append(enabled)
        }
    }
    
    func log(_ message: String) {
        withLock {
            _logs.append(message)
        }
    }
    
    func setCustomValue(_ value: Any, forKey key: String) {
        withLock {
            _customValues[key] = value
        }
    }
    
    func record(error: Error) {
        withLock {
            _recordedErrors.append(error)
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private final class MockCrashReportingSink: CrashReportingSink {
    private(set) var reporter: CrashReporter?
    private(set) var enabled: Bool?
    private(set) var customValues: [String: Any] = [:]
    
    func setReporter(_ reporter: CrashReporter) {
        self.reporter = reporter
    }
    
    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
    }
    
    func setCustomValue(_ value: Any, forKey key: String) {
        customValues[key] = value
    }
}

@Suite(.serialized)
struct CrashlyticsBootstrapTests {
    @Test("CrashlyticsBootstrap is idempotent and configures once")
    func testBootstrapIdempotent() {
        let env = CrashlyticsBootstrapEnvironment(isDebug: false, isUnitTesting: true, overrideEnabled: nil)
        let firebase = MockFirebaseConfigurator()
        let sink = MockCrashReportingSink()
        let reporter = MockCrashReporter()
        
        let bootstrap = CrashlyticsBootstrap(
            environment: env,
            firebase: firebase,
            crashReporting: sink,
            reporterFactory: { reporter }
        )
        
        bootstrap.start()
        bootstrap.start()
        
        #expect(firebase.configureCalls == 1)
        #expect(sink.reporter != nil)
        #expect(sink.enabled == false)
        #expect((sink.customValues["is_unit_testing"] as? Bool) == true)
    }

    @Test("CrashlyticsBootstrap does not build Firebase reporter when disabled")
    func testBootstrapSkipsFirebaseReporterFactoryWhenDisabled() {
        let env = CrashlyticsBootstrapEnvironment(isDebug: true, isUnitTesting: false, overrideEnabled: nil)
        let firebase = MockFirebaseConfigurator()
        let sink = MockCrashReportingSink()
        var reporterFactoryCalls = 0

        let bootstrap = CrashlyticsBootstrap(
            environment: env,
            firebase: firebase,
            crashReporting: sink,
            reporterFactory: {
                reporterFactoryCalls += 1
                return MockCrashReporter()
            }
        )

        bootstrap.start()

        #expect(firebase.configureCalls == 1)
        #expect(reporterFactoryCalls == 0)
        #expect(sink.reporter is NoopCrashReporter)
        #expect(sink.enabled == false)
    }
    
    @Test("CrashReporting forwards logs/keys/errors to reporter")
    func testCrashReportingForwarding() {
        let reporter = MockCrashReporter()
        let previousReporter = CrashReporting.reporter
        let previousEnabled = CrashReporting.isEnabled
        CrashReporting.reporter = reporter
        defer {
            CrashReporting.reporter = previousReporter
            CrashReporting.setEnabled(previousEnabled)
        }
        
        struct SampleError: Error {}
        CrashReporting.setEnabled(true)
        CrashReporting.setCustomValue("v", forKey: "k_forwarding")
        CrashReporting.log("m_forwarding")
        CrashReporting.record(error: SampleError())
        
        #expect(reporter.enabledValues.contains(true))
        #expect(reporter.customValues["k_forwarding"] as? String == "v")
        #expect(reporter.logs.contains("m_forwarding"))
        #expect(reporter.recordedErrors.count >= 1)
    }
}
