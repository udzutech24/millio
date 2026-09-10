import Foundation
import XCTest

/// Обзор портфеля раскатывается на ru/en/zh-Hans — raw-литералов в UI быть не должно.
final class AIPortfolioDigestLocalizationTests: XCTestCase {
    private static let requiredKeys = [
        "ai.portfolio.change.caption",
        "ai.portfolio.change.month",
        "ai.portfolio.change.quarter",
        "ai.portfolio.change.year",
        "ai.portfolio.disclaimer",
        "ai.portfolio.empty_format",
        "ai.portfolio.entry.subtitle",
        "ai.portfolio.excluded_format",
        "ai.portfolio.loading",
        "ai.portfolio.open_position",
        "ai.portfolio.positions.title",
        "ai.portfolio.share_format",
        "ai.portfolio.title",
        "ai.portfolio.value_format",
        "ai.portfolio.window.month",
        "ai.portfolio.window.quarter",
        "ai.portfolio.window.year",
        "ai.summary.numbers_only"
    ]

    private static let formatKeys = [
        "ai.portfolio.empty_format",
        "ai.portfolio.excluded_format",
        "ai.portfolio.share_format",
        "ai.portfolio.value_format"
    ]

    func testPortfolioKeysExistForRuEnAndZhHans() throws {
        let strings = try Self.strings()
        for key in Self.requiredKeys {
            for language in ["ru", "en", "zh-Hans"] {
                let value = try Self.value(strings, key: key, language: language)
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "Пустой `\(language)` для `\(key)`")
            }
        }
    }

    /// Потеря `%@` в любом языке даст строку без валюты или доли.
    func testFormatKeysKeepPlaceholderInEveryLanguage() throws {
        let strings = try Self.strings()
        for key in Self.formatKeys {
            for language in ["ru", "en", "zh-Hans"] {
                XCTAssertTrue(try Self.value(strings, key: key, language: language).contains("%@"), "`\(key)` [\(language)] без %@")
            }
        }
    }

    // MARK: - Helpers

    private static func strings() throws -> [String: Any] {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            let candidate = directory.appendingPathComponent("millio/Localizable.xcstrings")
            if FileManager.default.fileExists(atPath: candidate.path) {
                let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: candidate)) as? [String: Any])
                return try XCTUnwrap(root["strings"] as? [String: Any])
            }
            directory = directory.deletingLastPathComponent()
        }
        throw XCTSkip("millio/Localizable.xcstrings не найден от \(#filePath)")
    }

    private static func value(_ strings: [String: Any], key: String, language: String) throws -> String {
        let entry = try XCTUnwrap(strings[key] as? [String: Any], "Нет ключа `\(key)`")
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let unit = try XCTUnwrap((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any], "Нет `\(language)` для `\(key)`")
        return try XCTUnwrap(unit["value"] as? String)
    }
}
