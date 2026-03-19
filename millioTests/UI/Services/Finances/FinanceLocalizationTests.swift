//
//  FinanceLocalizationTests.swift
//  millioTests
//

import Testing
import Foundation
@testable import millio

struct FinanceLocalizationTests {
    @Test("Ключи локализации финансового модуля резолвятся в строки, а не остаются ключами")
    func financeLocalizationKeysResolve() {
        let keys = [
            "finances.main.title",
            "finances.dynamics.title",
            "finances.main.refresh_quotes",
            "finances.main.refresh_stocks",
            "finances.group.menu.priority",
            "finances.warning.rate_unavailable",
            "finances.investment.position_subtitle",
            "finances.dynamics.warning.estimated_rate",
            "finances.add_account.nav.new",
            "finances.add_account.section.balance",
            "finances.add_account.total_impact.include",
            "finances.common.add",
            "finances.common.save",
            "finances.common.reset",
            "finances.card.type.debit",
            "finances.investment.category.stocks",
            "finances.credit.payment_mode.next_date",
            "finances.editor.card.new_title",
            "finances.quick_edit.title.amount",
            "finances.display_currency.title.primary",
            "finances.savings_goal.title",
            "finances.dynamics.filter.title",
            "finances.group_editor.nav.new",
            "finances.transaction.note.credit_remaining_edit",
            "finances.settings.title",
            "finances.audit.nav.title",
            "finances.audit.search.placeholder",
            "finances.audit.date_picker.title",
            "finances.chart.axis.total",
            "finances.dynamics.delete_account",
            "finances.dynamics.delete_account.confirm.message",
            "finances.dynamics.delete_account.confirm.title",
            "finances.dynamics.delete_investment",
            "finances.dynamics.delete_investment.confirm.message",
            "finances.dynamics.delete_investment.confirm.title",
            "finances.main.empty_intro.title",
            "finances.main.empty_intro.description",
            "finances.main.empty_intro.add_product",
            "finances.main.empty_intro.open_dynamics",
            "finances.main.empty_intro.dismiss",
        ]

        for key in keys {
            #expect(FinancesL10n.tr(key) != key)
        }
    }

    @Test("Форматируемые строки финансов подставляют динамические значения")
    func financeLocalizationFormatsDynamicValues() {
        let warning = FinancesL10n.format("finances.warning.rate_unavailable", "USD", "RUB")
        #expect(warning.contains("USD"))
        #expect(warning.contains("RUB"))

        let subtitle = FinancesL10n.format(
            "finances.investment.position_subtitle",
            "1.5",
            FinancesL10n.tr("finances.investment.unit.coins"),
            "100",
            "$"
        )
        #expect(subtitle.contains("1.5"))
        #expect(subtitle.contains("100"))
        #expect(subtitle.contains("$"))
    }

    @Test("Финансовая fallback-локализация переключает ru/en по выбранной локали")
    func fallbackLocalizationRespectsLocale() {
        #expect(
            FinancesL10n.text(locale: Locale(identifier: "ru"), ru: "Подсказки", en: "Hints") == "Подсказки"
        )
        #expect(
            FinancesL10n.text(locale: Locale(identifier: "en"), ru: "Подсказки", en: "Hints") == "Hints"
        )
    }

    @Test("DisplayName enum-ов в создании продукта приходят из локализации")
    func addAccountDisplayNamesAreLocalized() {
        #expect(CardType.debit.displayName != "finances.card.type.debit")
        #expect(CardType.credit.displayName != "finances.card.type.credit")
        #expect(InvestmentType.positive.displayName != "finances.investment.type.positive")
        #expect(InvestmentCategory.crypto.displayName != "finances.investment.category.crypto")
        #expect(CreditType.consumer.displayName != "finances.credit.type.consumer")
        #expect(CreditPaymentMode.nextDate.displayName != "finances.credit.payment_mode.next_date")
    }

    @Test("Все ключи finances.* имеют переводы ru/en в Localizable.xcstrings")
    func allFinanceKeysHaveRuAndEnTranslations() throws {
        let strings = try loadFinanceStrings()

        for (key, rawValue) in strings where key.hasPrefix("finances.") {
            let value = try #require(rawValue as? [String: Any], "Invalid entry for key: \(key)")
            let localizations = try #require(value["localizations"] as? [String: Any], "Missing localizations for key: \(key)")
            let en = try #require(localizations["en"] as? [String: Any], "Missing en localization: \(key)")
            let ru = try #require(localizations["ru"] as? [String: Any], "Missing ru localization: \(key)")
            let enUnit = try #require(en["stringUnit"] as? [String: Any], "Missing en stringUnit: \(key)")
            let ruUnit = try #require(ru["stringUnit"] as? [String: Any], "Missing ru stringUnit: \(key)")
            let enValue = try #require(enUnit["value"] as? String, "Missing en value: \(key)")
            let ruValue = try #require(ruUnit["value"] as? String, "Missing ru value: \(key)")
            #expect(!enValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty en value: \(key)")
            #expect(!ruValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty ru value: \(key)")
        }
    }

    @Test("Индустриальные формулировки в финансах зафиксированы для ru/en")
    func industrialFinanceCopyMatchesExpectedValues() throws {
        let strings = try loadFinanceStrings()

        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.title",
            locale: "ru",
            equals: "Контур финансового контроля"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.title",
            locale: "en",
            equals: "Finance Control Center"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.description",
            locale: "ru",
            equals: "Сведите карты, кредитные обязательства и инвестиционные позиции в единый контур контроля. Откройте «Динамику», чтобы анализировать движение баланса, прирост капитала и источники потерь во времени."
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.description",
            locale: "en",
            equals: "Consolidate cards, loan obligations, and investment positions in a single control area. Open Dynamics to analyze balance movement, capital growth, and loss sources over time."
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.title",
            locale: "ru",
            equals: "Параметры финансов"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.title",
            locale: "en",
            equals: "Finance Controls"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.pro.title",
            locale: "ru",
            equals: "Расширенная графическая аналитика доступна в PRO"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.pro.title",
            locale: "en",
            equals: "Advanced charting is available in PRO"
        )
    }

    private func loadFinanceStrings() throws -> [String: Any] {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let xcstringsURL = repoRootURL
            .appendingPathComponent("millio")
            .appendingPathComponent("Localizable.xcstrings")

        let data = try Data(contentsOf: xcstringsURL)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["strings"] as? [String: Any])
    }

    private func assertLocalizedValue(
        strings: [String: Any],
        key: String,
        locale: String,
        equals expectedValue: String
    ) throws {
        let rawValue = try #require(strings[key] as? [String: Any], "Missing key: \(key)")
        let localizations = try #require(rawValue["localizations"] as? [String: Any], "Missing localizations: \(key)")
        let localeValue = try #require(localizations[locale] as? [String: Any], "Missing locale \(locale): \(key)")
        let stringUnit = try #require(localeValue["stringUnit"] as? [String: Any], "Missing stringUnit: \(key)")
        let value = try #require(stringUnit["value"] as? String, "Missing value: \(key)")
        #expect(value == expectedValue, "Unexpected \(locale) copy for \(key)")
    }
}
