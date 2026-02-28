import Foundation
import Testing
@testable import millio

struct LoggingAndSecurityTests {
    @Test("CrashReporting sanitizer redacts UUID and long numbers")
    func testCrashReportingSanitizer() {
        let input = "user=2F5A6B90-1234-5678-9ABC-DEF012345678 amount=1234567890 ok"
        let output = CrashReporting.sanitizeForCrashlytics(input)
        #expect(output.contains("<uuid>"))
        #expect(output.contains("<redacted>"))
        #expect(!output.contains("2F5A6B90-1234-5678-9ABC-DEF012345678"))
        #expect(!output.contains("1234567890"))
    }
    
    @Test("Data.randomBytes returns empty data for zero count")
    func testRandomBytesZeroCount() throws {
        let data = try Data.randomBytes(count: 0)
        #expect(data.count == 0)
    }
}

