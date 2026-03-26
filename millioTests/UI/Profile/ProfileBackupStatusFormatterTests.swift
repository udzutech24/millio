import Foundation
import Testing
@testable import millio

@Suite("Profile backup status formatter")
struct ProfileBackupStatusFormatterTests {
    @Test("Russian trailing backup date stays compact")
    func russianTrailingDateText() {
        let date = Date(timeIntervalSince1970: 1774483200) // 2026-03-25 21:20:00 UTC
        let text = ProfileBackupStatusFormatter.trailingDateText(
            for: date,
            locale: Locale(identifier: "ru_RU")
        )

        #expect(text.contains("мар"))
        #expect(text.contains(":") == false)
        #expect(text.count <= 10)
    }

    @Test("English trailing backup date stays compact")
    func englishTrailingDateText() {
        let date = Date(timeIntervalSince1970: 1774483200)
        let text = ProfileBackupStatusFormatter.trailingDateText(
            for: date,
            locale: Locale(identifier: "en_US")
        )

        #expect(text.contains("Mar"))
        #expect(text.contains(":") == false)
        #expect(text.count <= 10)
    }
}
