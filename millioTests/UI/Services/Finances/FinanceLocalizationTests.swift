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
        let strings = try #require(json["strings"] as? [String: Any])

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
}
