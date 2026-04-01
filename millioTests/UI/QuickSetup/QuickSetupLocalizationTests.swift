import Foundation
import Testing
@testable import millio

struct QuickSetupLocalizationTests {
    private let dependentLocalizationKeys = [
        "finances.add_account.placeholder.card",
        "finances.add_account.placeholder.credit",
        "finances.add_account.placeholder.investment.debt",
        "finances.add_account.placeholder.investment.house",
        "finances.add_account.placeholder.market",
        "finances.group_editor.name_template.credits",
        "finances.group_editor.name_template.debit_cards",
        "finances.group_editor.name_template.deposits",
        "finances.group_editor.name_template.foreign_cards",
        "finances.group_editor.name_template.my_real_estate",
        "finances.group_editor.name_template.stocks"
    ]

    @Test("Quick setup catalog keys are localized for ru en zh-Hans")
    func quickSetupKeysExistForThreeLanguages() throws {
        let strings = try loadStrings()

        for (key, rawValue) in strings where key.hasPrefix("quick_setup.") {
            let value = try #require(rawValue as? [String: Any], "Invalid entry for key: \(key)")
            let localizations = try #require(value["localizations"] as? [String: Any], "Missing localizations for key: \(key)")

            for language in ["ru", "en", "zh-Hans"] {
                let localization = try #require(localizations[language] as? [String: Any], "Missing \(language) localization: \(key)")
                let stringUnit = try #require(localization["stringUnit"] as? [String: Any], "Missing stringUnit for \(language): \(key)")
                let localizedValue = try #require(stringUnit["value"] as? String, "Missing value for \(language): \(key)")
                #expect(!localizedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty \(language) value: \(key)")
            }
        }
    }

    @Test("Quick setup release copy resolves in Simplified Chinese")
    func quickSetupChineseCopyResolves() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(AppLocalization.string("quick_setup.step.locale_and_currencies.title", locale: locale) == "语言和货币")
        #expect(AppLocalization.string("quick_setup.common.favorite_currencies", locale: locale) == "常用货币")
        #expect(AppLocalization.string("quick_setup.product.amount.quantity", locale: locale) == "数量")
        #expect(AppLocalization.string("quick_setup.error.crypto_requires_pro", locale: locale) == "加密货币仅在 PRO 中可用")
        #expect(AppLocalization.string("finances.add_account.placeholder.card", locale: locale) == "例如，主卡")
        #expect(FinanceGroupNameTemplate.debitCards.title(locale: locale) == "卡")
        #expect(
            QuickSetupLocalization.format(
                "quick_setup.badge.favorites_count_format",
                locale: locale,
                2,
                4
            ) == "常用：2/4"
        )
        #expect(
            QuickSetupLocalization.format(
                "quick_setup.step_progress_format",
                locale: locale,
                1,
                4
            ) == "第 1 / 4 步"
        )
    }

    @Test("Quick setup formatter interpolates string and count placeholders safely")
    func quickSetupFormatterInterpolatesStringAndCountPlaceholders() {
        let english = Locale(identifier: "en")
        let russian = Locale(identifier: "ru")
        let chinese = Locale(identifier: "zh-Hans")

        #expect(
            QuickSetupLocalization.format(
                "quick_setup.badge.primary_currency_format",
                locale: english,
                "USD"
            ) == "Primary: USD"
        )
        #expect(
            QuickSetupLocalization.format(
                "quick_setup.selected_categories_count_format",
                locale: russian,
                7
            ) == "Выбрано: 7"
        )
        #expect(
            QuickSetupLocalization.format(
                "quick_setup.product_summary_format",
                locale: english,
                "Card",
                "1,250 USD"
            ) == "Card · 1,250 USD"
        )
        #expect(
            QuickSetupLocalization.format(
                "quick_setup.step_progress_format",
                locale: chinese,
                1,
                4
            ) == "第 1 / 4 步"
        )
        #expect(
            QuickSetupLocalization.format(
                "quick_setup.favorite_limit_format",
                locale: chinese,
                QuickSetupViewModel.maxFavoriteCurrencies
            ) == "最多可选择 4 种货币"
        )
    }

    @Test("Quick setup dependent finance keys are localized for release languages")
    func quickSetupDependentFinanceKeysExistForThreeLanguages() throws {
        let strings = try loadStrings()

        for key in dependentLocalizationKeys {
            let value = try #require(strings[key] as? [String: Any], "Missing dependent key: \(key)")
            let localizations = try #require(value["localizations"] as? [String: Any], "Missing localizations for dependent key: \(key)")

            for language in ["ru", "en", "zh-Hans"] {
                let localization = try #require(localizations[language] as? [String: Any], "Missing \(language) localization: \(key)")
                let stringUnit = try #require(localization["stringUnit"] as? [String: Any], "Missing stringUnit for \(language): \(key)")
                let localizedValue = try #require(stringUnit["value"] as? String, "Missing value for \(language): \(key)")
                #expect(!localizedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty \(language) value: \(key)")
            }
        }
    }

    @Test("Quick setup source avoids inline ru en branching helpers")
    func quickSetupSourceGuardsHold() throws {
        let localization = try String(contentsOf: sourceURL("millio/UI/QuickSetup/QuickSetupLocalization.swift"), encoding: .utf8)
        let models = try String(contentsOf: sourceURL("millio/UI/QuickSetup/QuickSetupModels.swift"), encoding: .utf8)
        let viewModel = try String(contentsOf: sourceURL("millio/UI/QuickSetup/QuickSetupViewModel.swift"), encoding: .utf8)
        let view = try String(contentsOf: sourceURL("millio/UI/QuickSetup/QuickSetupView.swift"), encoding: .utf8)
        let applier = try String(contentsOf: sourceURL("millio/UI/QuickSetup/QuickSetupApplier.swift"), encoding: .utf8)

        #expect(!localization.contains("static func text("))
        #expect(!models.contains("QuickSetupLocalization.text("))
        #expect(!viewModel.contains("QuickSetupLocalization.text("))
        #expect(!view.contains("QuickSetupLocalization.text("))
        #expect(!applier.contains("QuickSetupLocalization.text("))
        #expect(!view.contains("quickSetupText(ru:"))
        #expect(!viewModel.contains("String(localized: \"quick_setup."))
        #expect(!view.contains("String(localized: \"quick_setup."))
        #expect(view.contains("locale: locale,"))
    }

    private func loadStrings() throws -> [String: Any] {
        let data = try Data(contentsOf: sourceURL("millio/Localizable.xcstrings"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["strings"] as? [String: Any])
    }

    private func sourceURL(_ relativePath: String) -> URL {
        let testFileURL = URL(fileURLWithPath: #filePath)
        return testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}
