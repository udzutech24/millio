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
    static private(set) var isEnabled: Bool = false
    
    static func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        reporter.setEnabled(enabled)
    }
    
    static func log(_ message: String) {
        guard isEnabled else { return }
        reporter.log(sanitizeForCrashlytics(message))
    }
    
    static func setCustomValue(_ value: Any, forKey key: String) {
        reporter.setCustomValue(value, forKey: key)
    }
    
    static func record(error: Error) {
        guard isEnabled else { return }
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
