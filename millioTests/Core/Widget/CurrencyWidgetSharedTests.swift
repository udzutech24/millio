import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct CurrencyWidgetSharedTests {
    @Test("Trial-статус дает доступ к Premium в виджете")
    func testTrialStatusHasPremiumAccess() {
        let suiteName = "CurrencyWidgetSharedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("trial", forKey: CurrencyWidgetShared.Keys.subscriptionStatus)

        let snapshot = CurrencyWidgetShared.SubscriptionSnapshot.load(from: defaults)
        #expect(snapshot.hasPremiumAccess(now: Date(timeIntervalSince1970: 1000)) == true)
    }

    @Test("Просроченная подписка и выключенный debug premium закрывают доступ")
    func testExpiredSubscriptionHasNoPremiumAccess() {
        let suiteName = "CurrencyWidgetSharedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 2_000)
        defaults.set("subscribed", forKey: CurrencyWidgetShared.Keys.subscriptionStatus)
        defaults.set(now.addingTimeInterval(-10), forKey: CurrencyWidgetShared.Keys.subscriptionExpiration)
        defaults.set(false, forKey: CurrencyWidgetShared.Keys.debugPremiumEnabled)

        let snapshot = CurrencyWidgetShared.SubscriptionSnapshot.load(from: defaults)
        #expect(snapshot.hasPremiumAccess(now: now) == false)
    }

    @Test("ConverterSnapshot загружает и нормализует данные для виджета")
    func testConverterSnapshotLoad() {
        let suiteName = "CurrencyWidgetSharedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(" rub , usd , eur , usd", forKey: CurrencyWidgetShared.Keys.selectedCodes)
        defaults.set("usd", forKey: CurrencyWidgetShared.Keys.activeCode)
        defaults.set("99,5", forKey: CurrencyWidgetShared.Keys.inputText)
        defaults.set("erapi", forKey: CurrencyWidgetShared.Keys.rateSource)
        defaults.set(["RUB": 90.0, "EUR": 0.92], forKey: CurrencyWidgetShared.Keys.cachedRates(for: "erapi"))
        defaults.set(3_600.0, forKey: CurrencyWidgetShared.Keys.lastRatesTimestamp(for: "erapi"))

        let snapshot = CurrencyWidgetShared.ConverterSnapshot.load(from: defaults)

        #expect(snapshot.selectedCodes == ["RUB", "USD", "EUR"])
        #expect(snapshot.activeCode == "USD")
        #expect(snapshot.inputText == "99,5")
        #expect(snapshot.rateSourceRaw == "erapi")
        #expect(snapshot.rates["USD"] == 1.0)
        #expect(snapshot.rates["RUB"] == 90.0)
        #expect(snapshot.lastUpdatedAt == Date(timeIntervalSince1970: 3_600.0))
    }

    @Test("Конвертация использует кросс-курс через USD")
    func testConvertViaUSDCrossRate() {
        let rates: [String: Double] = ["USD": 1.0, "RUB": 90.0, "EUR": 0.9]

        let converted = CurrencyWidgetShared.convert(amount: 100, from: "USD", to: "RUB", rates: rates)
        #expect(converted == 9_000)

        let eurToRub = CurrencyWidgetShared.convert(amount: 10, from: "EUR", to: "RUB", rates: rates)
        #expect(eurToRub != nil)
        #expect(abs((eurToRub ?? 0) - 1_000) < 0.0001)
    }
}
