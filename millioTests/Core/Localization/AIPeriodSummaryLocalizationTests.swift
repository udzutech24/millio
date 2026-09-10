import Foundation
import XCTest

/// Экран итогов раскатывается на ru/en/zh-Hans — raw-литералов в UI быть не должно.
final class AIPeriodSummaryLocalizationTests: XCTestCase {
    private static let requiredKeys = [
        "ai.summary.screen.title",
        "ai.summary.period.month",
        "ai.summary.period.quarter",
        "ai.summary.period.quarter_format",
        "ai.summary.net",
        "ai.summary.balance_end",
        "ai.summary.numbers_only",
        "ai.summary.loading",
        "dashboard.ai_summary.title"
    ]

    func testAISummaryKeysExistForRuEnAndZhHans() throws {
        let strings = try Self.strings()

        for key in Self.requiredKeys {
            guard
                let entry = strings[key] as? [String: Any],
                let localizations = entry["localizations"] as? [String: Any]
            else {
                XCTFail("Нет ключа `\(key)` в millio/Localizable.xcstrings")
                continue
            }

            for language in ["ru", "en", "zh-Hans"] {
                guard
                    let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any],
                    let value = unit["value"] as? String
                else {
                    XCTFail("Нет перевода `\(language)` для `\(key)`")
                    continue
                }
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "Пустой `\(language)` для `\(key)`")
            }
        }
    }

    /// Формат заголовка квартала подставляет номер и год позиционно — потеря `%1$@`/`%2$@`
    /// в любом языке даст «кв.» без цифр.
    func testQuarterFormatKeepsBothPositionalArgumentsInEveryLanguage() throws {
        let strings = try Self.strings()
        let entry = try XCTUnwrap(strings["ai.summary.period.quarter_format"] as? [String: Any])
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])

        for language in ["ru", "en", "zh-Hans"] {
            let unit = try XCTUnwrap((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any])
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertTrue(value.contains("%1$@"), "`\(language)` потерял номер квартала")
            XCTAssertTrue(value.contains("%2$@"), "`\(language)` потерял год")
        }
    }

    // MARK: - Helpers

    private static func strings() throws -> [String: Any] {
        let data = try Data(contentsOf: try localizableXcstringsURL())
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["strings"] as? [String: Any])
    }

    private static func localizableXcstringsURL() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        for _ in 0..<12 {
            let candidate = directory
                .appendingPathComponent("millio", isDirectory: true)
                .appendingPathComponent("Localizable.xcstrings", isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) { return candidate }
            directory = directory.deletingLastPathComponent()
        }

        throw XCTSkip("millio/Localizable.xcstrings не найден от \(#filePath)")
    }
}
