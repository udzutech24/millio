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
            "cashflow.asset_change.explanation",
            "cashflow.asset_change.formula",
            "cashflow.asset_change.formula_title",
            "cashflow.asset_change.matches",
            "cashflow.asset_change.matches_detail",
            "cashflow.asset_change.mismatch",
            "cashflow.asset_change.mismatch_detail",
            "cashflow.asset_change.subtitle",
            "cashflow.asset_change.substitution",
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

            let values = try localizedStringValues(for: localizations, key: key)
            let english = values["en", default: ""]
            let russian = values["ru", default: ""]

            XCTAssertFalse(english.hasSuffix("."), "English `\(key)` should not end with a period.")
            XCTAssertFalse(russian.hasSuffix("."), "Russian `\(key)` should not end with a period.")
            XCTAssertNotEqual(russian, english, "Russian `\(key)` should not fall back to English.")
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

    private func assertLocalized(strings: [String: Any], key: String) throws {
        guard
            let entry = strings[key] as? [String: Any],
            let localizations = entry["localizations"] as? [String: Any]
        else {
            return XCTFail("Missing `\(key)` in `millio/Localizable.xcstrings`.")
        }

        XCTAssertNotNil(localizations["en"], "Missing English localization for `\(key)`.")
        XCTAssertNotNil(localizations["ru"], "Missing Russian localization for `\(key)`.")
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
