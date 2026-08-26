import Foundation
import Testing
@testable import millio

/// Кросс-курс из USD-базированного снимка — общая арифметика синхронного (offline) пути:
/// им пользуются и `CurrencyRateService.getCachedRate`, и сортировка счетов по сумме.
@Suite
struct RateSnapshotCrossRateTests {

    private func snapshot(_ rates: [String: Double]) -> RateSnapshot {
        RateSnapshot(source: .millio, rates: rates, updatedAt: 0, fetchedAt: 0)
    }

    @Test("Одинаковые валюты дают 1 даже при пустой таблице")
    func sameCurrencyIsIdentity() {
        #expect(snapshot([:]).rate(from: "RUB", to: "rub") == 1.0)
    }

    @Test("Кросс-курс через USD: 1 USD = 90 RUB")
    func crossRateThroughUSD() {
        let rate = snapshot(["RUB": 90, "EUR": 0.9]).rate(from: "USD", to: "RUB")
        #expect(rate == 90)
    }

    @Test("Кросс-курс между двумя не-USD валютами")
    func crossRateBetweenNonUSD() throws {
        let rate = try #require(snapshot(["RUB": 90, "EUR": 0.9]).rate(from: "EUR", to: "RUB"))
        #expect(abs(rate - 100) < 0.0001)
    }

    @Test("Неизвестная валюта и нулевой курс дают nil, а не 0")
    func unknownOrZeroRateIsNil() {
        #expect(snapshot(["RUB": 90]).rate(from: "XYZ", to: "RUB") == nil)
        #expect(snapshot(["RUB": 0]).rate(from: "USD", to: "RUB") == nil)
    }
}
