import Foundation
import XCTest

final class LocalizableXcstringsTests: XCTestCase {
    func testSupportContactFeedbackMessageIsLocalizedInENAndRU() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any],
            let entry = strings["profile.contact.feedback_message"] as? [String: Any],
            let localizations = entry["localizations"] as? [String: Any]
        else {
            return XCTFail("Missing `profile.contact.feedback_message` in `millio/Localizable.xcstrings`.")
        }

        XCTAssertNotNil(localizations["en"], "Missing English localization for `profile.contact.feedback_message`.")
        XCTAssertNotNil(localizations["ru"], "Missing Russian localization for `profile.contact.feedback_message`.")

        let localizedValues = try localizedStringValues(for: localizations, key: "profile.contact.feedback_message")
        XCTAssertFalse(localizedValues["en", default: ""].hasSuffix("."), "English `profile.contact.feedback_message` should not end with a period.")
        XCTAssertFalse(localizedValues["ru", default: ""].hasSuffix("."), "Russian `profile.contact.feedback_message` should not end with a period.")
    }

    func testRateAppStringsAreLocalizedInENAndRU() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        try assertLocalized(strings: strings, key: "profile.rate_app")
        try assertLocalized(strings: strings, key: "profile.rate_app.block.eyebrow")
        try assertLocalized(strings: strings, key: "profile.rate_app.block.title")
        try assertLocalized(strings: strings, key: "profile.rate_app.block.subtitle")
        try assertLocalized(strings: strings, key: "profile.rate_app.star")
        try assertLocalized(strings: strings, key: "profile.rate_app.star_hint")
        try assertLocalized(strings: strings, key: "profile.rate_app.not_now")
        try assertLocalized(strings: strings, key: "profile.rate_app.summary.idle")
        try assertLocalized(strings: strings, key: "profile.rate_app.summary.feedback")
        try assertLocalized(strings: strings, key: "profile.rate_app.summary.good")
        try assertLocalized(strings: strings, key: "profile.rate_app.summary.excellent")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.rate.title")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.rate.gratitude")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.rate.message.app_store")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.rate.message.in_app")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.rate.action.app_store")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.rate.action.in_app")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.feedback.title")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.feedback.gratitude")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.feedback.message")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.feedback.action")

        try assertLocalized(strings: strings, key: "profile.contact.header.title")
        try assertLocalized(strings: strings, key: "finances.market.search.contact_action")
        try assertLocalized(strings: strings, key: "finances.market.search.instructions_stocks")
        try assertLocalized(strings: strings, key: "finances.market.search.instructions_crypto")
        try assertLocalized(strings: strings, key: "finances.market.search.support_hint")
        try assertLocalized(strings: strings, key: "converter.settings.section_widget")
        try assertLocalized(strings: strings, key: "converter.settings.widget.preview_title")
        try assertLocalized(strings: strings, key: "converter.settings.widget.preview_subtitle")
        try assertLocalized(strings: strings, key: "converter.settings.widget.how_to_title")
        try assertLocalized(strings: strings, key: "converter.settings.widget.step_open_jiggle")
        try assertLocalized(strings: strings, key: "converter.settings.widget.step_find_millio")
        try assertLocalized(strings: strings, key: "converter.settings.widget.step_add_widget")
    }

    func testProfileRateAppAndDebugStringsAreLocalizedInENRUAndZhHans() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "profile.rate_app.block.eyebrow",
            "profile.rate_app.block.title",
            "profile.rate_app.block.subtitle",
            "profile.rate_app.dialog.feedback.action",
            "profile.rate_app.dialog.feedback.gratitude",
            "profile.rate_app.dialog.feedback.message",
            "profile.rate_app.dialog.feedback.title",
            "profile.rate_app.dialog.rate.action.app_store",
            "profile.rate_app.dialog.rate.action.in_app",
            "profile.rate_app.dialog.rate.gratitude",
            "profile.rate_app.dialog.rate.message.app_store",
            "profile.rate_app.dialog.rate.message.in_app",
            "profile.rate_app.dialog.rate.title",
            "profile.rate_app.not_now",
            "profile.rate_app.star",
            "profile.rate_app.star_hint",
            "profile.rate_app.summary.excellent",
            "profile.rate_app.summary.feedback",
            "profile.rate_app.summary.good",
            "profile.rate_app.summary.idle",
            "profile.section.debug",
            "profile.premium_access",
            "profile.premium.diagnostics.title",
            "profile.trial_disabled",
            "profile.show_onboarding",
            "profile.admin_stats"
        ]

        for key in keys {
            try assertLocalized(strings: strings, key: key, locales: ["en", "ru", "zh-Hans"])
        }
    }

    func testCriticalProfileCopyMatchesExpectedValues() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let launchModes = try localizedStringValues(
            for: try localizations(for: "profile.launch_splash.mode.always", in: strings),
            key: "profile.launch_splash.mode.always"
        )
        XCTAssertEqual(launchModes["zh-Hans"], "始终显示")

        let thanks = try localizedStringValues(
            for: try localizations(for: "profile.rate_app.dialog.rate.title", in: strings),
            key: "profile.rate_app.dialog.rate.title"
        )
        XCTAssertEqual(thanks["en"], "Thank you!")

        let smartReset = try localizedStringValues(
            for: try localizations(for: "profile.smart_data_reset", in: strings),
            key: "profile.smart_data_reset"
        )
        XCTAssertEqual(smartReset["ru"], "Пошаговый сброс данных")
    }

    func testDailyReminderSummarySubjectStringsAreLocalizedInENRUAndZhHans() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "profile.daily_reminders.summary.kind.expense",
            "profile.daily_reminders.summary.kind.income",
            "profile.daily_reminders.summary.kind.custom",
            "profile.daily_reminders.summary.kind.selected"
        ]

        for key in keys {
            try assertLocalized(strings: strings, key: key, locales: ["en", "ru", "zh-Hans"])
        }
    }

    func testConverterCriticalStringsAreLocalizedInENRUAndZhHans() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "converter.common.cancel",
            "converter.common.close",
            "converter.common.delete",
            "converter.common.done",
            "converter.currency.search_placeholder",
            "converter.rate_source.erapi.title",
            "converter.rate_source.erapi.subtitle",
            "converter.rate_source.frankfurter.title",
            "converter.rate_source.frankfurter.subtitle",
            "converter.settings.title",
            "converter.settings.section_rate",
            "converter.settings.section_precision",
            "converter.settings.section_feel",
            "converter.settings.section_widget",
            "converter.settings.rate_source",
            "converter.settings.last_update",
            "converter.settings.refresh_rates",
            "converter.settings.refreshing_rates",
            "converter.settings.fraction_digits",
            "converter.settings.haptics",
            "converter.settings.widget.preview_title",
            "converter.settings.widget.preview_subtitle",
            "converter.settings.widget.how_to_title",
            "converter.settings.widget.step_open_jiggle",
            "converter.settings.widget.step_find_millio",
            "converter.settings.widget.step_add_widget",
            "converter.share.history_title",
            "converter.share.history_empty",
            "converter.share.preview_title",
            "converter.share.message_placeholder",
            "converter.share.send"
        ]

        for key in keys {
            try assertLocalized(strings: strings, key: key, locales: ["en", "ru", "zh-Hans"])
        }
    }

    func testCashflowStringsAreLocalizedInENAndRU() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let cashflowKeys = strings.keys.filter { $0.hasPrefix("cashflow.") }
        XCTAssertFalse(cashflowKeys.isEmpty, "Expected at least one `cashflow.*` key in `Localizable.xcstrings`.")

        for key in cashflowKeys {
            guard
                let entry = strings[key] as? [String: Any],
                let localizations = entry["localizations"] as? [String: Any]
            else {
                XCTFail("Missing `localizations` for `\(key)`.")
                continue
            }

            XCTAssertNotNil(localizations["en"], "Missing English localization for `\(key)`.")
            XCTAssertNotNil(localizations["ru"], "Missing Russian localization for `\(key)`.")
        }
    }

    func testCashflowBulkExpenseScreenshotStringsAreTranslatedAndWithoutTrailingPeriods() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "cashflow.bulk_expense.mode.manual",
            "cashflow.bulk_expense.mode.screenshot",
            "cashflow.bulk_expense.save",
            "cashflow.bulk_expense.screenshot.hint",
            "cashflow.bulk_expense.screenshot.pick",
            "cashflow.bulk_expense.screenshot.processing",
            "cashflow.bulk_expense.help.crop.title",
            "cashflow.bulk_expense.help.crop.subtitle",
            "cashflow.bulk_expense.help.crop.do",
            "cashflow.bulk_expense.help.crop.do_second",
            "cashflow.bulk_expense.help.crop.dont",
            "cashflow.bulk_expense.help.crop.warning",
            "cashflow.bulk_expense.help.step.balance.body",
            "cashflow.bulk_expense.help.step.save.body"
        ]

        for key in keys {
            guard
                let entry = strings[key] as? [String: Any],
                let localizations = entry["localizations"] as? [String: Any]
            else {
                XCTFail("Missing `\(key)` in `millio/Localizable.xcstrings`.")
                continue
            }

            let values = try localizedStringValues(for: localizations, key: key)
            let ruValue = values["ru", default: ""]

            XCTAssertFalse(values["en", default: ""].hasSuffix("."), "English `\(key)` should not end with a period.")
            XCTAssertFalse(ruValue.hasSuffix("."), "Russian `\(key)` should not end with a period.")
            XCTAssertNotEqual(ruValue, values["en", default: ""], "Russian `\(key)` should not fall back to English.")
        }
    }

    func testCashflowBulkExpenseControlsStringsAreTranslatedAndWithoutTrailingPeriods() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "cashflow.bulk_expense.controls.title",
            "cashflow.bulk_expense.controls.subtitle",
            "cashflow.bulk_expense.card_title",
            "cashflow.bulk_expense.affect_balance",
            "cashflow.bulk_expense.affect_balance.short",
            "cashflow.bulk_expense.affect_balance.hint",
            "cashflow.bulk_expense.affect_balance.subtitle"
        ]

        for key in keys {
            guard
                let entry = strings[key] as? [String: Any],
                let localizations = entry["localizations"] as? [String: Any]
            else {
                XCTFail("Missing `\(key)` in `millio/Localizable.xcstrings`.")
                continue
            }

            let values = try localizedStringValues(for: localizations, key: key)
            let english = values["en", default: ""]
            let russian = values["ru", default: ""]

            XCTAssertFalse(english.hasSuffix("."), "English `\(key)` should not end with a period.")
            XCTAssertFalse(russian.hasSuffix("."), "Russian `\(key)` should not end with a period.")
            XCTAssertNotEqual(russian, english, "Russian `\(key)` should not fall back to English.")
        }
    }

    func testCriticalThreeLanguageKeysExistForRUENAndZhHans() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "cashflow.accessibility.back",
            "cashflow.accessibility.hide_details",
            "cashflow.accessibility.quick_navigation",
            "cashflow.accessibility.select_period",
            "cashflow.accessibility.show_details",
            "cashflow.accessibility.transaction_history",
            "cashflow.chart.expand",
            "cashflow.common.close",
            "cashflow.common.done",
            "cashflow.common.ok",
            "cashflow.common.reset",
            "cashflow.common.save",
            "cashflow.common.settings",
            "cashflow.category.actions.operations",
            "cashflow.category.settings.title",
            "cashflow.category.undo.archive.title",
            "cashflow.category.undo.delete.title",
            "cashflow.editor.category_icon",
            "cashflow.editor.category_name",
            "cashflow.editor.edit_category",
            "cashflow.editor.enter_name",
            "cashflow.editor.icon_search_hint",
            "cashflow.editor.icon_suggestions",
            "cashflow.editor.icon_tab.emoji",
            "cashflow.editor.icon_tab.symbols",
            "cashflow.editor.icon_type",
            "cashflow.editor.new_category",
            "cashflow.history.detail.from_account",
            "cashflow.history.detail.to_account",
            "cashflow.editor.new_transaction",
            "cashflow.editor.section.additional",
            "cashflow.history.detail.changes",
            "cashflow.history.asset_change.price",
            "cashflow.history.asset_change.quantity",
            "cashflow.history.asset_change.value",
            "cashflow.history.cards",
            "cashflow.history.cards.all",
            "cashflow.history.empty.default",
            "cashflow.history.empty.title",
            "cashflow.history.filter.all",
            "cashflow.history.title",
            "cashflow.operation.total_expense_for_month",
            "cashflow.operation.total_income_for_month",
            "cashflow.period.range_format",
            "cashflow.quick_action.transfer",
            "cashflow.recurrence.weekly",
            "cashflow.recurrence.weekly.days_hint",
            "cashflow.recurrence.weekly.days_title",
            "cashflow.recurrence.weekly.none_selected",
            "cashflow.scheduled.day_agenda.empty.add_here",
            "cashflow.scheduled.delete_transaction.message",
            "cashflow.scheduled.delete_transaction.title",
            "cashflow.scheduled.display.calendar",
            "cashflow.scheduled.display.list",
            "cashflow.scheduled.empty.planner_expenses",
            "cashflow.scheduled.empty.planner_income",
            "cashflow.scheduled.overview.empty",
            "cashflow.scheduled.overview.next",
            "cashflow.scheduled.overview.one_time_prefix",
            "cashflow.scheduled.overview.title.expense",
            "cashflow.scheduled.overview.title.income",
            "cashflow.scheduled.planner_expenses",
            "cashflow.scheduled.planner_income",
            "cashflow.scheduled.search_transaction",
            "cashflow.scheduled.section.one_time",
            "cashflow.scheduled.section.recurring",
            "cashflow.stats.asset_value_change",
            "cashflow.stats.assets_end",
            "cashflow.stats.assets_start",
            "cashflow.stats.expenses",
            "cashflow.stats.result",
            "cashflow.budget.plan_button.add_limits",
            "cashflow.budget.plan_button.limits",
            "cashflow.budget.plan_button.income",
            "cashflow.budget.setup.title.expense",
            "cashflow.budget.setup.title.income",
            "cashflow.budget.status.exceeded",
            "cashflow.budget.badge.near",
            "cashflow.budget.badge.over",
            "converter.error.update_failed",
            "finances.dynamics.pro.cta",
            "finances.dynamics.warning.estimated_rate",
            "finances.dynamics.warning.estimated_rate.as_of",
            "finances.account.type.investment",
            "language.option.chinese_simplified",
            "profile.reminders"
        ]

        for key in keys {
            try assertLocalized(strings: strings, key: key, locales: ["en", "ru", "zh-Hans"])
        }
    }

    func testCashflowAssetChangeCopyIsLocalizedAndWithoutTrailingPeriods() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "cashflow.asset_change.balance_check",
            "cashflow.asset_change.change_format",
            "cashflow.asset_change.end_total_format",
            "cashflow.asset_change.explanation",
            "cashflow.asset_change.expenses_format",
            "cashflow.asset_change.formula",
            "cashflow.asset_change.formula_title",
            "cashflow.asset_change.income_format",
            "cashflow.asset_change.matches",
            "cashflow.asset_change.matches_detail",
            "cashflow.asset_change.mismatch",
            "cashflow.asset_change.mismatch_detail",
            "cashflow.asset_change.start_total_format",
            "cashflow.asset_change.subtitle",
            "cashflow.asset_change.substitution",
            "cashflow.chart.pro.subtitle",
            "cashflow.chart.pro.title",
            "cashflow.chart.title",
            "cashflow.stats.income"
        ]

        for key in keys {
            guard
                let entry = strings[key] as? [String: Any],
                let localizations = entry["localizations"] as? [String: Any]
            else {
                XCTFail("Missing `\(key)` in `millio/Localizable.xcstrings`.")
                continue
            }

            XCTAssertNotNil(localizations["zh-Hans"], "Missing zh-Hans localization for `\(key)`.")

            let values = try localizedStringValues(for: localizations, key: key)
            let english = values["en", default: ""]
            let russian = values["ru", default: ""]
            let simplifiedChinese = values["zh-Hans", default: ""]

            XCTAssertFalse(english.hasSuffix("."), "English `\(key)` should not end with a period.")
            XCTAssertFalse(russian.hasSuffix("."), "Russian `\(key)` should not end with a period.")
            XCTAssertFalse(simplifiedChinese.hasSuffix("."), "Simplified Chinese `\(key)` should not end with a period.")
            XCTAssertNotEqual(russian, english, "Russian `\(key)` should not fall back to English.")
            XCTAssertNotEqual(simplifiedChinese, english, "Simplified Chinese `\(key)` should not fall back to English.")
        }
    }

    func testCashflowNoCardsBreakdownCopyIsLocalizedInENRUAndZhHans() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "cashflow.breakdown.empty.no_cards.title",
            "cashflow.breakdown.empty.no_cards.subtitle",
            "cashflow.breakdown.empty.no_cards.cta"
        ]

        for key in keys {
            try assertLocalized(strings: strings, key: key, locales: ["en", "ru", "zh-Hans"])
        }
    }

    func testCashflowBulkExpenseCriticalStringsAreLocalizedInENRUAndZhHans() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "cashflow.bulk_expense.affect_balance",
            "cashflow.bulk_expense.affect_balance.compact",
            "cashflow.bulk_expense.affect_balance.toast.disabled",
            "cashflow.bulk_expense.affect_balance.toast.enabled",
            "cashflow.bulk_expense.card_title",
            "cashflow.bulk_expense.category.breakdown",
            "cashflow.bulk_expense.confidence.high",
            "cashflow.bulk_expense.confidence.low",
            "cashflow.bulk_expense.confidence.medium",
            "cashflow.bulk_expense.help.crop.do",
            "cashflow.bulk_expense.help.crop.do_second",
            "cashflow.bulk_expense.help.crop.dont",
            "cashflow.bulk_expense.help.crop.example.history",
            "cashflow.bulk_expense.help.crop.example.zone.balance",
            "cashflow.bulk_expense.help.open",
            "cashflow.bulk_expense.help.sheet_title",
            "cashflow.bulk_expense.help.step.screenshot.body",
            "cashflow.bulk_expense.manual.empty_parse",
            "cashflow.bulk_expense.mode.manual",
            "cashflow.bulk_expense.mode.screenshot",
            "cashflow.bulk_expense.pick_card",
            "cashflow.bulk_expense.review.apply",
            "cashflow.bulk_expense.review.subtitle",
            "cashflow.bulk_expense.review.title",
            "cashflow.bulk_expense.row.attention",
            "cashflow.bulk_expense.row.suggestion",
            "cashflow.bulk_expense.row.title_placeholder",
            "cashflow.bulk_expense.row.use_category",
            "cashflow.bulk_expense.save",
            "cashflow.bulk_expense.saved",
            "cashflow.bulk_expense.screenshot.hint",
            "cashflow.bulk_expense.screenshot.merge.completed",
            "cashflow.bulk_expense.screenshot.merge.partial",
            "cashflow.bulk_expense.screenshot.merge.review_required",
            "cashflow.bulk_expense.screenshot.pick",
            "cashflow.bulk_expense.screenshot.processing",
            "cashflow.bulk_expense.screenshot.recognized",
            "cashflow.bulk_expense.search.placeholder",
            "cashflow.bulk_expense.summary.balance_warning",
            "cashflow.bulk_expense.summary.rows",
            "cashflow.bulk_expense.summary.total",
            "cashflow.bulk_expense.title",
            "cashflow.bulk_expense.toggle.off",
            "cashflow.bulk_expense.toggle.on"
        ]

        for key in keys {
            guard
                let entry = strings[key] as? [String: Any],
                let localizations = entry["localizations"] as? [String: Any]
            else {
                XCTFail("Missing `\(key)` in `millio/Localizable.xcstrings`.")
                continue
            }

            let values = try localizedStringValues(for: localizations, key: key)
            let english = values["en", default: ""]
            let russian = values["ru", default: ""]
            let simplifiedChinese = values["zh-Hans", default: ""]

            XCTAssertFalse(english.isEmpty, "English `\(key)` should not be empty.")
            XCTAssertFalse(russian.isEmpty, "Russian `\(key)` should not be empty.")
            XCTAssertFalse(simplifiedChinese.isEmpty, "Simplified Chinese `\(key)` should not be empty.")
            XCTAssertNotEqual(russian, english, "Russian `\(key)` should not fall back to English.")
            XCTAssertNotEqual(simplifiedChinese, english, "Simplified Chinese `\(key)` should not fall back to English.")
        }
    }

    func testCashbackCriticalStringsAreLocalizedInENRUAndZhHans() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "cashback.category.supermarket",
            "cashback.category.taxi",
            "cashback.common.done",
            "cashback.common.dismiss",
            "cashback.common.save",
            "cashback.empty.title",
            "cashback.empty.subtitle",
            "cashback.empty.cta",
            "cashback.search.placeholder",
            "cashback.search.empty.title",
            "cashback.search.empty.subtitle",
            "cashback.editor.title.new",
            "cashback.editor.title.edit",
            "cashback.editor.section.card",
            "cashback.editor.section.categories",
            "cashback.editor.section.selected_categories",
            "cashback.card.select",
            "cashback.card.select.hint",
            "cashback.card.none_linked",
            "cashback.card.detail.balance",
            "cashback.card.detail.limit",
            "cashback.card.unnamed",
            "cashback.import.screenshot.title",
            "cashback.import.screenshot.cta",
            "cashback.import.screenshot.loading",
            "cashback.import.screenshot.pro_only",
            "cashback.import.screenshot.read_failed",
            "cashback.import.screenshot.parse_failed",
            "cashback.import.screenshot.recognized_format",
            "cashback.category.create",
            "cashback.category.show_more",
            "cashback.category.collapse",
            "cashback.category.delete.title",
            "cashback.category.delete.message",
            "cashback.category_editor.title.new",
            "cashback.category_editor.name.placeholder",
            "cashback.category_editor.icon.search.placeholder",
            "cashback.card_picker.title",
            "cashback.card_picker.header",
            "cashback.card_picker.empty.title",
            "cashback.card_picker.empty.subtitle",
            "cashback.card_recommendation.title",
            "cashback.card_recommendation.subtitle_format",
            "cashback.card_recommendation.add_card",
            "cashback.paywall.free_plan.title",
            "subscription.button.subscribe"
        ]

        for key in keys {
            try assertLocalized(strings: strings, key: key, locales: ["en", "ru", "zh-Hans"])
        }
    }

    func testProfileAuthStringsAreLocalizedInENAndRU() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "profile.auth.account_details",
            "profile.auth.connected",
            "profile.auth.connected.subtitle",
            "profile.auth.details",
            "profile.auth.email",
            "profile.auth.email_missing",
            "profile.auth.exit_guest",
            "profile.auth.guest.subtitle",
            "profile.auth.guest.title",
            "profile.auth.last_login",
            "profile.auth.logout",
            "profile.auth.name",
            "profile.auth.not_signed_in",
            "profile.auth.not_signed_in.subtitle"
        ]

        for key in keys {
            try assertLocalized(strings: strings, key: key)
        }
    }

    func testBackupRestoreConfirmationStringsAreLocalizedInENAndRU() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        try assertLocalized(strings: strings, key: "backup.restore.confirm.title")
        try assertLocalized(strings: strings, key: "backup.restore.confirm.message")
        try assertLocalized(strings: strings, key: "backup.restore.confirm.action")
        try assertLocalized(strings: strings, key: "common.cancel")
    }

    /// Регрессия БАГ 7: у auth.error.* (экран входа) и common.delete ru-слот содержал английский
    /// текст со статусом "new", а en-записи не было вообще. Чинить нужно ОБА языка сразу — если
    /// поправить только ru и забыть en, экран входа сломается наоборот для EN-пользователей.
    func testAuthErrorAndCommonDeleteAreTranslatedInENAndRU() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "auth.error.apple_credentials",
            "auth.error.forbidden",
            "auth.error.generic",
            "auth.error.invalid_response",
            "auth.error.network",
            "auth.error.offline",
            "auth.error.post_login_bootstrap",
            "auth.error.rate_limited",
            "auth.error.server",
            "auth.error.session_expired",
            "auth.error.tls",
            "auth.error.token_persistence",
            "auth.error.unavailable",
            "auth.error.wrong_session_namespace",
            "common.delete"
        ]

        for key in keys {
            try assertLocalized(strings: strings, key: key)
            let entryLocalizations = try localizations(for: key, in: strings)

            let en = try stringUnit(locale: "en", localizations: entryLocalizations, key: key)
            let ru = try stringUnit(locale: "ru", localizations: entryLocalizations, key: key)

            XCTAssertEqual(en.state, "translated", "`\(key)`: en должен быть в статусе translated.")
            XCTAssertEqual(ru.state, "translated", "`\(key)`: ru должен быть в статусе translated, не new.")
            XCTAssertFalse(ru.value.isEmpty, "`\(key)`: ru перевод не должен быть пустым.")
            XCTAssertNotEqual(ru.value, en.value, "`\(key)`: ru не должен дублировать английский текст.")
        }
    }

    /// Регрессия БАГ 7 (reorder) + БАГ 8 (новые ключи для кредитки и undo-баннера категорий):
    /// эти ключи либо были в статусе "new" с английским текстом в ru, либо отсутствовали в
    /// каталоге вообще (Picker/Undo-баннер показывали сырые Swift-литералы в RU-интерфейсе).
    func testReorderAndNewCreditCardUndoKeysAreLocalized() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        // Раньше здесь была только проверка присутствия языка (assertLocalized), которая
        // проходит и на "битом" каталоге, где ru-слот стоит в статусе "new" и дублирует
        // английский текст. Docs: регрессия БАГ 7 ловится только строгой проверкой
        // state == "translated" И ru != en — усиливаем по образцу testAuthErrorAndCommonDeleteAreTranslatedInENAndRU.
        let strictKeys = [
            "cashflow.category.reorder.reset",
            "cashflow.category.reorder.title.expense",
            "cashflow.category.reorder.title.income",
            "finances.editor.card.bank_label",
            "cashflow.category.undo.action"
        ]
        for key in strictKeys {
            try assertLocalized(strings: strings, key: key, locales: ["en", "ru", "zh-Hans"])
            let entryLocalizations = try localizations(for: key, in: strings)
            let en = try stringUnit(locale: "en", localizations: entryLocalizations, key: key)
            let ru = try stringUnit(locale: "ru", localizations: entryLocalizations, key: key)

            XCTAssertEqual(en.state, "translated", "`\(key)`: en должен быть в статусе translated.")
            XCTAssertEqual(ru.state, "translated", "`\(key)`: ru должен быть в статусе translated, не new.")
            XCTAssertFalse(ru.value.isEmpty, "`\(key)`: ru перевод не должен быть пустым.")
            XCTAssertNotEqual(ru.value, en.value, "`\(key)`: ru не должен дублировать английский текст.")
        }
    }

    /// Регрессия round 2 (N1): ключи, тронутые или добавленные веткой fix/release-2.0-blockers,
    /// получили en/ru/zh-Hans, но de и es пропустили — немецкий и испанский пользователь видел
    /// русский текст вместо перевода (String Catalog при отсутствии локали падает на sourceLanguage,
    /// а не на en). Проверяем весь набор из N1 сразу, чтобы не потерять его при следующей правке.
    func testKeysTouchedByFixReleaseBranchAreTranslatedInDEAndES() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "auth.error.apple_credentials",
            "auth.error.forbidden",
            "auth.error.generic",
            "auth.error.invalid_response",
            "auth.error.network",
            "auth.error.offline",
            "auth.error.post_login_bootstrap",
            "auth.error.rate_limited",
            "auth.error.server",
            "auth.error.session_expired",
            "auth.error.tls",
            "auth.error.token_persistence",
            "auth.error.unavailable",
            "auth.error.wrong_session_namespace",
            "common.delete",
            "cashflow.category.undo.action",
            "finances.editor.card.bank_label",
            "credit_card.edit.statement_day_format",
            "credit_card.edit.due_day_format",
            "credit_card.edit.grace_days_format"
        ]

        for key in keys {
            try assertLocalized(strings: strings, key: key, locales: ["de", "es"])
            let entryLocalizations = try localizations(for: key, in: strings)
            let en = try stringUnit(locale: "en", localizations: entryLocalizations, key: key)
            let ru = try stringUnit(locale: "ru", localizations: entryLocalizations, key: key)

            for locale in ["de", "es"] {
                let translation = try stringUnit(locale: locale, localizations: entryLocalizations, key: key)
                XCTAssertEqual(translation.state, "translated", "`\(key)`: \(locale) должен быть в статусе translated.")
                XCTAssertFalse(translation.value.isEmpty, "`\(key)`: \(locale) перевод не должен быть пустым.")
                XCTAssertNotEqual(translation.value, en.value, "`\(key)`: \(locale) не должен дублировать английский текст.")
                // Ревью round 2: != en не ловит скопированный ru-текст (source language каталога — ru,
                // и de/es-слот, по ошибке заполненный русским, прошёл бы предыдущую проверку).
                XCTAssertNotEqual(translation.value, ru.value, "`\(key)`: \(locale) не должен дублировать русский текст.")
            }
        }
    }

    /// Регрессия round 2 (N3): 14 auth.error.* и common.delete не имели zh-Hans вообще —
    /// китайский пользователь видел ru-фолбэк на экране входа.
    func testAuthErrorAndCommonDeleteAreTranslatedInZhHans() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "auth.error.apple_credentials",
            "auth.error.forbidden",
            "auth.error.generic",
            "auth.error.invalid_response",
            "auth.error.network",
            "auth.error.offline",
            "auth.error.post_login_bootstrap",
            "auth.error.rate_limited",
            "auth.error.server",
            "auth.error.session_expired",
            "auth.error.tls",
            "auth.error.token_persistence",
            "auth.error.unavailable",
            "auth.error.wrong_session_namespace",
            "common.delete"
        ]

        for key in keys {
            try assertLocalized(strings: strings, key: key, locales: ["zh-Hans"])
            let entryLocalizations = try localizations(for: key, in: strings)
            let en = try stringUnit(locale: "en", localizations: entryLocalizations, key: key)
            let zhHans = try stringUnit(locale: "zh-Hans", localizations: entryLocalizations, key: key)

            XCTAssertEqual(zhHans.state, "translated", "`\(key)`: zh-Hans должен быть в статусе translated.")
            XCTAssertFalse(zhHans.value.isEmpty, "`\(key)`: zh-Hans перевод не должен быть пустым.")
            XCTAssertNotEqual(zhHans.value, en.value, "`\(key)`: zh-Hans не должен дублировать английский текст.")
        }
    }

    /// Регрессия round 2 (N2): у 29 ключей extractionState стоял "extracted_with_value" при
    /// исходном языке каталога ru и английском defaultValue в коде — именно эта связка позволяет
    /// Xcode на следующей синхронизации затереть ru обратно английским текстом (БАГ 7 повторится).
    /// "manual" защищает от авто-синхронизации; см. сравнение с common.cancel/common.more, у которых
    /// extractionState всегда был "manual" и регрессии не было.
    func testExtractionStateIsManualForKeysPatchedThisBranch() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "auth.error.apple_credentials", "auth.error.forbidden", "auth.error.generic",
            "auth.error.invalid_response", "auth.error.network", "auth.error.offline",
            "auth.error.post_login_bootstrap", "auth.error.rate_limited", "auth.error.server",
            "auth.error.session_expired", "auth.error.tls", "auth.error.token_persistence",
            "auth.error.unavailable", "auth.error.wrong_session_namespace",
            "common.delete",
            "cashflow.bulk_expense.error.card_not_found", "cashflow.bulk_expense.error.insufficient_funds",
            "cashflow.bulk_expense.error.invalid_image", "cashflow.bulk_expense.error.no_rows",
            "cashflow.bulk_expense.error.no_rows_to_save", "cashflow.bulk_expense.error.no_text",
            "cashflow.editor.transfer.exchange_rate", "cashflow.editor.transfer.rate_custom_invalid",
            "cashflow.editor.transfer.rate_loading", "cashflow.editor.transfer.rate_mode.current",
            "cashflow.editor.transfer.rate_mode.custom", "cashflow.editor.transfer.rate_unavailable",
            "cashflow.editor.transfer.received_amount", "cashflow.editor.transfer.your_rate"
        ]
        XCTAssertEqual(keys.count, 29, "Ожидается ровно 29 ключей — состав списка не должен молча меняться.")

        for key in keys {
            guard
                let entry = strings[key] as? [String: Any],
                let extractionState = entry["extractionState"] as? String
            else {
                return XCTFail("Missing `\(key)` or its extractionState in `millio/Localizable.xcstrings`.")
            }
            XCTAssertEqual(
                extractionState,
                "manual",
                "`\(key)`: extractionState должен быть manual, иначе следующая Xcode-синхронизация может затереть ru английским текстом."
            )
        }
    }

    /// Регрессия round 2 (N5): экран перевода (Cashflow) и bulk-импорт расходов — эти 14 ключей
    /// не были покрыты НИ ОДНИМ тестом, хотя на `develop` их ru-слот был в статусе "new" и
    /// дублировал английский текст один в один (тот же паттерн БАГ 7, просто не задетектированный).
    func testCashflowTransferAndBulkExpenseErrorsAreTranslatedInENAndRU() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let keys = [
            "cashflow.editor.transfer.exchange_rate",
            "cashflow.editor.transfer.rate_custom_invalid",
            "cashflow.editor.transfer.rate_loading",
            "cashflow.editor.transfer.rate_mode.current",
            "cashflow.editor.transfer.rate_mode.custom",
            "cashflow.editor.transfer.rate_unavailable",
            "cashflow.editor.transfer.received_amount",
            "cashflow.editor.transfer.your_rate",
            "cashflow.bulk_expense.error.card_not_found",
            "cashflow.bulk_expense.error.insufficient_funds",
            "cashflow.bulk_expense.error.invalid_image",
            "cashflow.bulk_expense.error.no_rows",
            "cashflow.bulk_expense.error.no_rows_to_save",
            "cashflow.bulk_expense.error.no_text"
        ]

        for key in keys {
            try assertLocalized(strings: strings, key: key)
            let entryLocalizations = try localizations(for: key, in: strings)
            let en = try stringUnit(locale: "en", localizations: entryLocalizations, key: key)
            let ru = try stringUnit(locale: "ru", localizations: entryLocalizations, key: key)

            XCTAssertEqual(en.state, "translated", "`\(key)`: en должен быть в статусе translated.")
            XCTAssertEqual(ru.state, "translated", "`\(key)`: ru должен быть в статусе translated, не new.")
            XCTAssertFalse(ru.value.isEmpty, "`\(key)`: ru перевод не должен быть пустым.")
            XCTAssertNotEqual(ru.value, en.value, "`\(key)`: ru не должен дублировать английский текст.")
        }
    }

    /// Регрессия round 2 (N4): common.more был пустым стабом ("localizations": {}) в каталоге —
    /// VoiceOver на кнопке-многоточии (CashflowView) зачитывал сырой ключ "common.more" вместо
    /// текста, потому что ни для одного языка не было значения.
    func testCommonMoreIsLocalized() throws {
        let xcstringsURL = try Self.localizableXcstringsURL()
        let data = try Data(contentsOf: xcstringsURL)

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard
            let root = jsonObject as? [String: Any],
            let strings = root["strings"] as? [String: Any]
        else {
            return XCTFail("Invalid `millio/Localizable.xcstrings` JSON structure.")
        }

        let key = "common.more"
        try assertLocalized(strings: strings, key: key, locales: ["en", "ru", "zh-Hans", "de", "es"])
        let entryLocalizations = try localizations(for: key, in: strings)
        let en = try stringUnit(locale: "en", localizations: entryLocalizations, key: key)

        for locale in ["ru", "zh-Hans", "de", "es"] {
            let translation = try stringUnit(locale: locale, localizations: entryLocalizations, key: key)
            XCTAssertEqual(translation.state, "translated", "`\(key)`: \(locale) должен быть в статусе translated.")
            XCTAssertFalse(translation.value.isEmpty, "`\(key)`: \(locale) перевод не должен быть пустым.")
            XCTAssertNotEqual(translation.value, en.value, "`\(key)`: \(locale) не должен дублировать английский текст.")
        }
    }

    private static func localizableXcstringsURL() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        for _ in 0..<12 {
            let candidate = directory
                .appendingPathComponent("millio", isDirectory: true)
                .appendingPathComponent("Localizable.xcstrings", isDirectory: false)

            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }

        throw NSError(
            domain: "LocalizableXcstringsTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate `millio/Localizable.xcstrings` from `#filePath`."]
        )
    }

    private func assertLocalized(
        strings: [String: Any],
        key: String,
        locales: [String] = ["en", "ru"]
    ) throws {
        guard
            let entry = strings[key] as? [String: Any],
            let localizations = entry["localizations"] as? [String: Any]
        else {
            return XCTFail("Missing `\(key)` in `millio/Localizable.xcstrings`.")
        }

        for locale in locales {
            XCTAssertNotNil(localizations[locale], "Missing \(locale) localization for `\(key)`.")
        }
    }

    private func stringUnit(
        locale: String,
        localizations: [String: Any],
        key: String
    ) throws -> (state: String, value: String) {
        guard
            let localization = localizations[locale] as? [String: Any],
            let stringUnit = localization["stringUnit"] as? [String: Any],
            let state = stringUnit["state"] as? String,
            let value = stringUnit["value"] as? String
        else {
            throw NSError(
                domain: "LocalizableXcstringsTests",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Missing stringUnit for `\(key)` locale `\(locale)`."]
            )
        }

        return (state, value)
    }

    private func localizations(for key: String, in strings: [String: Any]) throws -> [String: Any] {
        guard
            let entry = strings[key] as? [String: Any],
            let localizations = entry["localizations"] as? [String: Any]
        else {
            throw NSError(domain: "LocalizableXcstringsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing `\(key)` in `millio/Localizable.xcstrings`."])
        }

        return localizations
    }

    private func localizedStringValues(
        for localizations: [String: Any],
        key: String
    ) throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: localizations.map { locale, value in
            guard
                let localization = value as? [String: Any],
                let stringUnit = localization["stringUnit"] as? [String: Any],
                let stringValue = stringUnit["value"] as? String
            else {
                throw NSError(
                    domain: "LocalizableXcstringsTests",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Missing string value for `\(key)` locale `\(locale)`."]
                )
            }

            return (locale, stringValue)
        })
    }
}
