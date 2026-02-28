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
    private(set) var enabledValues: [Bool] = []
    private(set) var logs: [String] = []
    private(set) var customValues: [String: Any] = [:]
    private(set) var recordedErrors: [Error] = []
    
    func setEnabled(_ enabled: Bool) {
        enabledValues.append(enabled)
    }
    
    func log(_ message: String) {
        logs.append(message)
    }
    
    func setCustomValue(_ value: Any, forKey key: String) {
        customValues[key] = value
    }
    
    func record(error: Error) {
        recordedErrors.append(error)
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
    
    @Test("CrashReporting forwards logs/keys/errors to reporter")
    func testCrashReportingForwarding() {
        let reporter = MockCrashReporter()
        let previousReporter = CrashReporting.reporter
        CrashReporting.reporter = reporter
        defer { CrashReporting.reporter = previousReporter }
        
        struct SampleError: Error {}
        CrashReporting.setEnabled(true)
        CrashReporting.setCustomValue("v", forKey: "k")
        CrashReporting.log("m")
        CrashReporting.record(error: SampleError())
        
        #expect(reporter.enabledValues == [true])
        #expect(reporter.customValues["k"] as? String == "v")
        #expect(reporter.logs == ["m"])
        #expect(reporter.recordedErrors.count == 1)
    }
}
