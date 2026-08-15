import Foundation
import Testing
@testable import millio

@Suite("Deposit tax presentation completeness")
struct DepositTaxPresentationTests {
    @Test func aggregatesOwnerWideAndUsesDirectAndInverseEventDateFX() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: .init(year: 2026, month: 2, day: 3))!
        let a = UUID(), b = UUID(), c = UUID()
        let result = DepositTaxPresentationBuilder.make(
            events: [
                .init(accountID: a, date: date, currency: "RUB", amount: 100),
                .init(accountID: b, date: date, currency: "USD", amount: 2),
                .init(accountID: c, date: date, currency: "EUR", amount: 4)
            ], year: 2026, settings: .init(ndflRatePercent: 13, keyRateForYear: 0),
            historicalFX: [
                .init(dayKey: "2026-02-03", base: "USD", quote: "RUB"): 90,
                .init(dayKey: "2026-02-03", base: "RUB", quote: "EUR"): 0.01
            ], calendar: calendar
        )
        #expect(result.isComplete)
        #expect(result.result?.totalGrossInterestRUB == 680)
        #expect(result.result?.perAccount.count == 3)
    }

    @Test func missingFXMakesWholeTaxPresentationIncomplete() {
        let result = DepositTaxPresentationBuilder.make(
            events: [.init(accountID: UUID(), date: Date(), currency: "USD", amount: 100)],
            year: Calendar.current.component(.year, from: Date()), settings: .default,
            historicalFX: [:], calendar: .current
        )
        #expect(result.result == nil)
        #expect(result.unresolved == [.missingHistoricalFX])
    }
}
