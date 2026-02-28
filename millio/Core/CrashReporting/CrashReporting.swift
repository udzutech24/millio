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
    private static let lock = NSLock()
    private static var _reporter: CrashReporter = NoopCrashReporter()
    private static var _isEnabled: Bool = false

    static var reporter: CrashReporter {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _reporter
        }
        set {
            lock.lock()
            _reporter = newValue
            lock.unlock()
        }
    }

    static var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isEnabled
    }
    
    static func setEnabled(_ enabled: Bool) {
        let reporter: CrashReporter
        lock.lock()
        _isEnabled = enabled
        reporter = _reporter
        lock.unlock()
        reporter.setEnabled(enabled)
    }
    
    static func log(_ message: String) {
        let reporter: CrashReporter
        lock.lock()
        let enabled = _isEnabled
        reporter = _reporter
        lock.unlock()
        guard enabled else { return }
        reporter.log(sanitizeForCrashlytics(message))
    }
    
    static func setCustomValue(_ value: Any, forKey key: String) {
        let reporter: CrashReporter
        lock.lock()
        reporter = _reporter
        lock.unlock()
        reporter.setCustomValue(value, forKey: key)
    }
    
    static func record(error: Error) {
        let reporter: CrashReporter
        lock.lock()
        let enabled = _isEnabled
        reporter = _reporter
        lock.unlock()
        guard enabled else { return }
        reporter.record(error: error)
    }
    
    static func sanitizeForCrashlytics(_ message: String) -> String {
        var result = message
        
        let patterns: [(String, String)] = [
            ("\\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\\b", "<uuid>"),
            ("\\b\\d{6,}\\b", "<redacted>")
        ]
        
        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
            }
        }
        
        let maxLength = 1024
        if result.count > maxLength {
            result = String(result.prefix(maxLength))
        }
        
        return result
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
