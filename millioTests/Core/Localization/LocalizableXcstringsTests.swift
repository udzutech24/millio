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
        try assertLocalized(strings: strings, key: "profile.rate_app.block.title")
        try assertLocalized(strings: strings, key: "profile.rate_app.block.subtitle")
        try assertLocalized(strings: strings, key: "profile.rate_app.star")
        try assertLocalized(strings: strings, key: "profile.rate_app.star_hint")
        try assertLocalized(strings: strings, key: "profile.rate_app.not_now")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.rate.title")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.rate.message.app_store")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.rate.message.in_app")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.rate.action.app_store")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.rate.action.in_app")
        try assertLocalized(strings: strings, key: "profile.rate_app.dialog.feedback.title")
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
}
