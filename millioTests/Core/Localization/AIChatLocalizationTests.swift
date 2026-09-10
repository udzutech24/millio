import Foundation
import XCTest

/// Экран чата раскатывается на ru/en/zh-Hans — raw-литералов в UI быть не должно.
final class AIChatLocalizationTests: XCTestCase {
    private static let requiredKeys = [
        "ai.chat.clear",
        "ai.chat.clear.confirm",
        "ai.chat.context.title",
        "ai.chat.dashboard.ask",
        "ai.chat.disclaimer",
        "ai.chat.empty.subtitle",
        "ai.chat.empty.title",
        "ai.chat.entry.subtitle",
        "ai.chat.entry.title",
        "ai.chat.error.network",
        "ai.chat.error.rate_limited",
        "ai.chat.error.unavailable",
        "ai.chat.followup.next",
        "ai.chat.followup.shorter",
        "ai.chat.followup.why",
        "ai.chat.input.placeholder",
        "ai.chat.retry",
        "ai.chat.send",
        "ai.chat.stop",
        "ai.chat.suggestion.categories",
        "ai.chat.suggestion.cut",
        "ai.chat.suggestion.savings",
        "ai.chat.suggestion.top_expense",
        "ai.chat.thinking",
        "common.cancel"
    ]

    func testAIChatKeysExistForRuEnAndZhHans() throws {
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

    /// Имя агента — «millio» строчными во всех языках: переводчик не должен его капитализировать.
    func testAgentNameStaysLowercaseInEveryLanguage() throws {
        let strings = try Self.strings()
        for key in ["ai.chat.entry.title", "ai.chat.dashboard.ask", "ai.chat.clear.confirm", "ai.chat.disclaimer"] {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for language in ["ru", "en", "zh-Hans"] {
                let unit = try XCTUnwrap((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any])
                let value = try XCTUnwrap(unit["value"] as? String)
                XCTAssertTrue(value.contains("millio"), "`\(language)`/`\(key)` потерял «millio» строчными")
                XCTAssertFalse(value.contains("Millio"), "`\(language)`/`\(key)` капитализировал имя агента")
            }
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
