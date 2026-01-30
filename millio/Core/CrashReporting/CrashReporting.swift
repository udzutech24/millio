import Foundation

protocol CrashReporter {
    func setEnabled(_ enabled: Bool)
    func log(_ message: String)
    func setCustomValue(_ value: Any, forKey key: String)
    func record(error: Error)
}

protocol CrashReportingSink {
    func setReporter(_ reporter: CrashReporter)
    func setEnabled(_ enabled: Bool)
    func setCustomValue(_ value: Any, forKey key: String)
}

enum CrashReporting {
    static var reporter: CrashReporter = NoopCrashReporter()
    
    static func setEnabled(_ enabled: Bool) {
        reporter.setEnabled(enabled)
    }
    
    static func log(_ message: String) {
        reporter.log(message)
    }
    
    static func setCustomValue(_ value: Any, forKey key: String) {
        reporter.setCustomValue(value, forKey: key)
    }
    
    static func record(error: Error) {
        reporter.record(error: error)
    }
}

struct DefaultCrashReportingSink: CrashReportingSink {
    func setReporter(_ reporter: CrashReporter) {
        CrashReporting.reporter = reporter
    }
    
    func setEnabled(_ enabled: Bool) {
        CrashReporting.setEnabled(enabled)
    }
    
    func setCustomValue(_ value: Any, forKey key: String) {
        CrashReporting.setCustomValue(value, forKey: key)
    }
}

struct NoopCrashReporter: CrashReporter {
    func setEnabled(_ enabled: Bool) {}
    func log(_ message: String) {}
    func setCustomValue(_ value: Any, forKey key: String) {}
    func record(error: Error) {}
}
