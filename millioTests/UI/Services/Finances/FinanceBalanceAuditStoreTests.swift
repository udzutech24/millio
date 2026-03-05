import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct FinanceBalanceAuditStoreTests {

    @Test("Store: set/delete value is idempotent")
    func testSetDeleteValueIdempotent() {
        let defaults = UserDefaults(suiteName: "FinanceBalanceAuditStoreTests.setDelete")!
        defaults.removePersistentDomain(forName: "FinanceBalanceAuditStoreTests.setDelete")
        let store = FinanceBalanceAuditStore(defaults: defaults, storageKey: "test.key")
        let day = FinanceBalanceDayKey(date: Date(timeIntervalSince1970: 1_700_000_000))

        store.setValue(
            100,
            for: "card:1",
            day: day,
            defaultCurrency: "rub",
            defaultTitle: "Card",
            defaultGroupName: "Group",
            accountTypeRaw: "card",
            effectSign: 1,
            isUnknown: false
        )
        #expect(store.daySnapshot(for: day)["card:1"]?.value == 100)

        store.deleteValue(for: "card:1", day: day)
        store.deleteValue(for: "card:1", day: day)
        #expect(store.daySnapshot(for: day)["card:1"] == nil)
    }

    @Test("Store: set currency updates all days")
    func testCurrencySyncAcrossAllDays() {
        let defaults = UserDefaults(suiteName: "FinanceBalanceAuditStoreTests.currency")!
        defaults.removePersistentDomain(forName: "FinanceBalanceAuditStoreTests.currency")
        let store = FinanceBalanceAuditStore(defaults: defaults, storageKey: "test.key")

        let day1 = FinanceBalanceDayKey(date: Date(timeIntervalSince1970: 1_700_000_000))
        let day2 = FinanceBalanceDayKey(date: Date(timeIntervalSince1970: 1_700_086_400))

        store.setValue(1, for: "card:1", day: day1, defaultCurrency: "RUB", defaultTitle: "A", defaultGroupName: "G", accountTypeRaw: "card", effectSign: 1, isUnknown: false)
        store.setValue(2, for: "card:1", day: day2, defaultCurrency: "RUB", defaultTitle: "A", defaultGroupName: "G", accountTypeRaw: "card", effectSign: 1, isUnknown: false)

        store.setCurrency("usd", for: "card:1")

        #expect(store.daySnapshot(for: day1)["card:1"]?.currencyCode == "USD")
        #expect(store.daySnapshot(for: day2)["card:1"]?.currencyCode == "USD")
        #expect(store.currency(for: "card:1") == "USD")
    }

    @Test("Store: delete account everywhere removes values and currency mapping")
    func testDeleteAccountEverywhere() {
        let defaults = UserDefaults(suiteName: "FinanceBalanceAuditStoreTests.deleteAccount")!
        defaults.removePersistentDomain(forName: "FinanceBalanceAuditStoreTests.deleteAccount")
        let store = FinanceBalanceAuditStore(defaults: defaults, storageKey: "test.key")

        let day = FinanceBalanceDayKey(date: Date())
        store.setValue(1, for: "card:1", day: day, defaultCurrency: "RUB", defaultTitle: "A", defaultGroupName: "G", accountTypeRaw: "card", effectSign: 1, isUnknown: false)
        store.setCurrency("EUR", for: "card:1")

        store.deleteAccountEverywhere("card:1")
        store.deleteAccountEverywhere("card:1")

        #expect(store.daySnapshot(for: day)["card:1"] == nil)
        #expect(store.currency(for: "card:1") == nil)
    }

    @Test("Day key is date-only")
    func testDayKeyDateOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        let date1 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 1, minute: 15))!
        let date2 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 22, minute: 50))!

        let key1 = FinanceBalanceDayKey(date: date1, calendar: calendar)
        let key2 = FinanceBalanceDayKey(date: date2, calendar: calendar)

        #expect(key1.rawValue == "2026-03-05")
        #expect(key1.rawValue == key2.rawValue)
    }

    @Test("Row normalization applies credit and effect sign rules")
    func testNormalizedValueRules() {
        let credit = FinanceBalanceAuditRow(
            id: "credit:1",
            accountTypeRaw: "credit",
            accountID: "1",
            title: "Credit",
            groupName: "G",
            currencyCode: "RUB",
            value: 100,
            effectSign: 1,
            hasDateSnapshot: true,
            isUnknown: false,
            sourceOrder: 0
        )
        #expect(credit.normalizedValue == -100)

        let negativeEffect = FinanceBalanceAuditRow(
            id: "inv:1",
            accountTypeRaw: "investment",
            accountID: "1",
            title: "Inv",
            groupName: "G",
            currencyCode: "RUB",
            value: 30,
            effectSign: -1,
            hasDateSnapshot: true,
            isUnknown: false,
            sourceOrder: 0
        )
        #expect(negativeEffect.normalizedValue == -30)
    }
}
