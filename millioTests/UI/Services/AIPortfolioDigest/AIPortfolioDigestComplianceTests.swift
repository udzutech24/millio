import Foundation
import XCTest

/// Комплаенс дайджеста на клиенте: инвестсоветы физлицам в РФ требуют лицензии ЦБ, поэтому на экране
/// нет действий со сделкой, тексты не содержат директив, дисклеймер совпадает с серверным.
final class AIPortfolioDigestComplianceTests: XCTestCase {
    private static let viewFile = "millio/UI/Services/AIPortfolioDigest/AIPortfolioDigestView.swift"
    private static let uiFiles = [
        viewFile,
        "millio/UI/Services/AIPortfolioDigest/AIPortfolioDigestEntryRow.swift",
        "millio/UI/Services/AIPortfolioDigest/AIPortfolioDigestViewModel.swift"
    ]

    /// Ни одного пути к сделке: ни листов покупки/продажи, ни записи событий счёта, ни «купить»-текстов.
    func testDigestUIHasNoTradeActions() throws {
        let forbidden = [
            ".buy", ".sell", "action.buy", "action.sell", "AccountsCoreService", "recordEvent",
            "Купить", "Продать", "Докупить", "Buy", "Sell"
        ]
        for file in Self.uiFiles {
            let source = try Self.source(file)
            for token in forbidden {
                XCTAssertFalse(source.contains(token), "\(file) содержит «\(token)»")
            }
        }
    }

    /// Каждая кнопка экрана — выбор окна или переход к позиции; третьего вида действий нет.
    func testEveryDigestButtonIsWindowSelectionOrNavigation() throws {
        let lines = try Self.source(Self.viewFile).components(separatedBy: .newlines)
        let buttonLines = lines.indices.filter { lines[$0].contains("Button") }
        XCTAssertFalse(buttonLines.isEmpty)
        for index in buttonLines {
            let action = lines[index..<min(index + 4, lines.count)].joined(separator: "\n")
            XCTAssertTrue(
                action.contains("viewModel.select(") || action.contains("openedAccountID ="),
                "Кнопка без разрешённого действия: \(lines[index].trimmingCharacters(in: .whitespaces))"
            )
        }
    }

    /// Дисклеймер рисуется вне веток состояния — в том числе при пустом портфеле и без текста модели.
    func testDisclaimerIsRenderedUnconditionally() throws {
        let source = try Self.source(Self.viewFile)
        XCTAssertEqual(source.components(separatedBy: "Text(viewModel.disclaimer)").count - 1, 1)
        let disclaimer = try XCTUnwrap(source.range(of: "Text(viewModel.disclaimer)"))
        let elseBranch = try XCTUnwrap(source.range(of: "ai.portfolio.empty_format"))
        XCTAssertLessThan(elseBranch.lowerBound, disclaimer.lowerBound, "дисклеймер должен идти после ветки пустого портфеля")
    }

    /// Тексты дайджеста не подталкивают к сделке ни на одном языке. Дисклеймер — исключение:
    /// в нём «рекомендация» стоит с отрицанием.
    func testPortfolioCopyHasNoDirectiveWords() throws {
        let stopWords = [
            "купи", "докуп", "покупа", "продай", "продава", "продаж", "рекоменд", "совет", "стоит ",
            "buy", "sell", "purchase", "advice", "recommend", "should",
            "买", "卖", "建议", "推荐", "应该"
        ]
        let strings = try Self.catalog()
        let keys = strings.keys.filter { $0.hasPrefix("ai.portfolio.") && $0 != "ai.portfolio.disclaimer" }
        XCTAssertFalse(keys.isEmpty)
        for key in keys {
            for language in ["ru", "en", "zh-Hans"] {
                let value = try Self.value(strings, key: key, language: language).lowercased()
                for word in stopWords {
                    XCTAssertFalse(value.contains(word), "`\(key)` [\(language)] содержит «\(word)»: \(value)")
                }
            }
        }
    }

    /// Офлайн-дисклеймер обязан совпадать с серверной константой (`DIGEST_DISCLAIMERS` в millio-back).
    func testLocalDisclaimerMatchesServerConstant() throws {
        let strings = try Self.catalog()
        XCTAssertEqual(try Self.value(strings, key: "ai.portfolio.disclaimer", language: "ru"), "Информация, не инвестиционная рекомендация.")
        XCTAssertEqual(try Self.value(strings, key: "ai.portfolio.disclaimer", language: "en"), "Information only, not investment advice.")
        XCTAssertEqual(try Self.value(strings, key: "ai.portfolio.disclaimer", language: "zh-Hans"), "仅供参考，不构成投资建议。")
    }

    // MARK: - Helpers

    private static func source(_ relativePath: String) throws -> String {
        try String(contentsOf: try repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func catalog() throws -> [String: Any] {
        let url = try repositoryRoot().appendingPathComponent("millio/Localizable.xcstrings")
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(root["strings"] as? [String: Any])
    }

    private static func value(_ strings: [String: Any], key: String, language: String) throws -> String {
        let entry = try XCTUnwrap(strings[key] as? [String: Any], "нет ключа \(key)")
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
        let unit = try XCTUnwrap((localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any])
        return try XCTUnwrap(unit["value"] as? String)
    }

    private static func repositoryRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        for _ in 0..<12 {
            if fileManager.fileExists(atPath: directory.appendingPathComponent("millio/Localizable.xcstrings").path) {
                return directory
            }
            directory = directory.deletingLastPathComponent()
        }
        throw XCTSkip("корень репозитория не найден от \(#filePath)")
    }
}
