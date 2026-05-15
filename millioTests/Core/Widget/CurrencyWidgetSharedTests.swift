import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct CurrencyWidgetSharedTests {
    @Test("ConverterSnapshot загружает и нормализует данные для виджета")
    func testConverterSnapshotLoad() {
        let suiteName = "CurrencyWidgetSharedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(" rub , usd , eur , usd", forKey: CurrencyWidgetShared.Keys.selectedCodes)
        defaults.set("usd", forKey: CurrencyWidgetShared.Keys.activeCode)
        defaults.set("99,5", forKey: CurrencyWidgetShared.Keys.inputText)
        defaults.set("erapi", forKey: CurrencyWidgetShared.Keys.rateSource)
        defaults.set("eur", forKey: CurrencyWidgetShared.Keys.primaryCurrencyCode)
        defaults.set(["RUB": 90.0, "EUR": 0.92], forKey: CurrencyWidgetShared.Keys.cachedRates(for: "erapi"))
        defaults.set(3_600.0, forKey: CurrencyWidgetShared.Keys.lastRatesTimestamp(for: "erapi"))

        let snapshot = CurrencyWidgetShared.ConverterSnapshot.load(from: defaults)

        #expect(snapshot.selectedCodes == ["RUB", "USD", "EUR"])
        #expect(snapshot.activeCode == "USD")
        #expect(snapshot.primaryCode == "EUR")
        #expect(snapshot.inputText == "99,5")
        #expect(snapshot.rateSourceRaw == "erapi")
        #expect(snapshot.rates["USD"] == 1.0)
        #expect(snapshot.rates["RUB"] == 90.0)
        #expect(snapshot.lastUpdatedAt == Date(timeIntervalSince1970: 3_600.0))
    }

    @Test("ConverterSnapshot использует безопасные дефолты без настроек")
    func testConverterSnapshotLoadUsesDefaults() {
        let suiteName = "CurrencyWidgetSharedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let snapshot = CurrencyWidgetShared.ConverterSnapshot.load(from: defaults)

        #expect(snapshot.selectedCodes == ["RUB", "USD", "EUR", "TRY", "GBP", "KZT"])
        #expect(snapshot.activeCode == "RUB")
        #expect(snapshot.primaryCode == "RUB")
        #expect(snapshot.inputText == "1200")
        #expect(snapshot.rateSourceRaw == "millio")
        #expect(snapshot.rates == ["USD": 1.0])
        #expect(snapshot.lastUpdatedAt == nil)
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

    @Test("Deep-link URL для виджета создается и парсится")
    func testWidgetDeepLinkBuildAndParse() {
        let url = CurrencyWidgetShared.deepLinkURL(for: .addExpense)
        #expect(url != nil)
        if let url {
            #expect(CurrencyWidgetShared.deepLinkAction(from: url) == .addExpense)
        }
    }

    @Test("Deep-link parser игнорирует URL c чужой схемой")
    func testWidgetDeepLinkRejectsUnknownScheme() {
        let url = URL(string: "https://example.com/action?type=add_income")!
        #expect(CurrencyWidgetShared.deepLinkAction(from: url) == nil)
    }
}
