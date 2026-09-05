import Foundation
import Testing
@testable import millio

/// Регрессия: ключи шапки категорий и режимов сортировки отсутствовали в Localizable.xcstrings,
/// поэтому `L(_:defaultValue:)` отдавал английский `defaultValue` во ВСЕХ языках — в русском
/// интерфейсе на экране ввода висели «Quick select» и «Activity».
struct CashflowCategorySortLocalizationTests {
    private let requiredKeys = [
        "cashflow.category.quick_select",
        "cashflow.category.reorder.sort",
        "cashflow.category.sort.activity",
        "cashflow.category.sort.amount",
        "cashflow.category.sort.manual",
        "cashflow.category.sort.name"
    ]

    @Test("Ключи сортировки категорий переведены на ru / en / zh-Hans")
    func categorySortKeysAreLocalizedForThreeLanguages() throws {
        let strings = try loadStrings()

        for key in requiredKeys {
            let entry = try #require(strings[key] as? [String: Any], "Ключ отсутствует в каталоге: \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any], "Нет localizations: \(key)")

            for language in ["ru", "en", "zh-Hans"] {
                let localization = try #require(
                    localizations[language] as? [String: Any],
                    "Нет локализации \(language): \(key)"
                )
                let stringUnit = try #require(localization["stringUnit"] as? [String: Any], "Нет stringUnit \(language): \(key)")
                let value = try #require(stringUnit["value"] as? String, "Нет value \(language): \(key)")
                #expect(
                    !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Пустое значение \(language): \(key)"
                )
            }
        }
    }

    @Test("Русское значение не равно английскому — иначе это непереведённый фолбэк")
    func russianValuesDifferFromEnglish() throws {
        let strings = try loadStrings()

        for key in requiredKeys {
            let entry = try #require(strings[key] as? [String: Any], "Ключ отсутствует в каталоге: \(key)")
            let localizations = try #require(entry["localizations"] as? [String: Any], "Нет localizations: \(key)")
            let russian = value(in: localizations, language: "ru")
            let english = value(in: localizations, language: "en")

            #expect(russian != english, "Русское значение совпадает с английским (непереведено): \(key) = \(russian ?? "nil")")
        }
    }

    @Test("Режимы сортировки резолвятся на русском и китайском")
    func sortModeTitlesResolveForRussianAndChinese() {
        let russian = Locale(identifier: "ru")
        let chinese = Locale(identifier: "zh-Hans")

        #expect(AppLocalization.string("cashflow.category.quick_select", locale: russian) == "Быстрый выбор")
        #expect(AppLocalization.string("cashflow.category.sort.activity", locale: russian) == "По активности")
        #expect(AppLocalization.string("cashflow.category.sort.amount", locale: russian) == "По сумме")
        #expect(AppLocalization.string("cashflow.category.sort.manual", locale: russian) == "Вручную")
        #expect(AppLocalization.string("cashflow.category.sort.name", locale: russian) == "По названию")
        #expect(AppLocalization.string("cashflow.category.reorder.sort", locale: russian) == "Сортировка")

        #expect(AppLocalization.string("cashflow.category.quick_select", locale: chinese) == "快速选择")
        #expect(AppLocalization.string("cashflow.category.sort.activity", locale: chinese) == "按活跃度")
    }

    @Test("Каждый CashflowCategorySortMode имеет ключ в каталоге")
    func everySortModeHasCatalogKey() throws {
        let strings = try loadStrings()

        for mode in CashflowCategorySortMode.allCases {
            let key = "cashflow.category.sort.\(mode.rawValue)"
            #expect(strings[key] != nil, "Для режима \(mode.rawValue) нет ключа \(key)")
        }
    }

    // MARK: - Helpers

    private func value(in localizations: [String: Any], language: String) -> String? {
        (localizations[language] as? [String: Any])
            .flatMap { $0["stringUnit"] as? [String: Any] }
            .flatMap { $0["value"] as? String }
    }

    private func loadStrings() throws -> [String: Any] {
        let data = try Data(contentsOf: sourceURL("millio/Localizable.xcstrings"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["strings"] as? [String: Any])
    }

    private func sourceURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Cashflow
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // UI
            .deletingLastPathComponent() // millioTests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent(relativePath)
    }
}
