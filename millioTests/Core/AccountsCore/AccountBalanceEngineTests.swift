import Foundation
import Testing
@testable import millio

/// Реплей всех 6 движков (AC5), детерминизм (S5), редоминация (AC11/AC15), отрицательные балансы (AC9).
@Suite("AccountBalanceEngine")
struct AccountBalanceEngineTests {

    private let day1 = Date(timeIntervalSince1970: 1_700_000_000)       // t0
    private let day2 = Date(timeIntervalSince1970: 1_700_000_000 + 86_400)
    private let day3 = Date(timeIntervalSince1970: 1_700_000_000 + 2 * 86_400)

    private func event(
        date: Date,
        type: AccountEventType,
        amount: Decimal? = nil,
        quantity: Decimal? = nil,
        unitPrice: Decimal? = nil,
        redenomRate: Decimal? = nil,
        redenomFromCurrency: String? = nil,
        createdAt: Date? = nil,
        id: UUID = UUID()
    ) -> AccountEvent {
        AccountEvent(
            id: id,
            date: date,
            createdAt: createdAt ?? date,
            type: type,
            amount: amount,
            quantity: quantity,
            unitPrice: unitPrice,
            redenomRate: redenomRate,
            redenomFromCurrency: redenomFromCurrency
        )
    }

    // MARK: - A: cash/debitCard/bankAccount

    @Test
    func engineA_openingIncomeExpense() {
        let events = [
            event(date: day1, type: .openingBalance, amount: 1000),
            event(date: day2, type: .income, amount: 500),
            event(date: day3, type: .expense, amount: 300),
        ]
        let balance = AccountBalanceEngine.balanceAt(events: events, kind: .bankAccount, on: day3)
        #expect(balance == 1200)
    }

    /// Расход больше баланса даёт отрицательный баланс — НЕ обрезается нулём (AC9).
    @Test
    func engineA_expenseExceedingBalanceGoesNegative() {
        let events = [
            event(date: day1, type: .openingBalance, amount: 100),
            event(date: day2, type: .expense, amount: 500),
        ]
        let balance = AccountBalanceEngine.balanceAt(events: events, kind: .cash, on: day2)
        #expect(balance == -400)
    }

    // MARK: - B: deposit (= A + interest)

    @Test
    func engineB_depositWithInterest() {
        let events = [
            event(date: day1, type: .openingBalance, amount: 100_000),
            event(date: day2, type: .interest, amount: 500),
        ]
        let balance = AccountBalanceEngine.balanceAt(events: events, kind: .deposit, on: day2)
        #expect(balance == 100_500)
    }

    // MARK: - C: loan — обязательство, отрицательный итог не обрезаем

    @Test
    func engineC_loanDrawAndPayment() {
        let events = [
            event(date: day1, type: .openingBalance, amount: 100_000), // выдача кредита
            event(date: day2, type: .income, amount: 20_000),          // платёж
        ]
        let balance = AccountBalanceEngine.balanceAt(events: events, kind: .loan, on: day2)
        #expect(balance == -80_000)
    }

    @Test
    func engineC_extraPaymentReducesDebtFurther() {
        let events = [
            event(date: day1, type: .openingBalance, amount: 100_000),
            event(date: day2, type: .extraPayment, amount: 100_000),
        ]
        let balance = AccountBalanceEngine.balanceAt(events: events, kind: .loan, on: day2)
        #expect(balance == 0)
    }

    // MARK: - D: debt — знак направления задаёт создатель событий

    @Test
    func engineD_owedByMeIsNegativeAndPaymentReducesTowardZero() {
        // owedByMe: открытие долга отрицательным opening, платёж — income (положительный)
        let events = [
            event(date: day1, type: .openingBalance, amount: -3000),
            event(date: day2, type: .income, amount: 1000),
        ]
        let balance = AccountBalanceEngine.balanceAt(events: events, kind: .debt, on: day2)
        #expect(balance == -2000)
    }

    @Test
    func engineD_owedToMeIsPositive() {
        let events = [
            event(date: day1, type: .openingBalance, amount: 3000),
        ]
        let balance = AccountBalanceEngine.balanceAt(events: events, kind: .debt, on: day1)
        #expect(balance == 3000)
    }

    // MARK: - E: marketInvestment — buy/sell × цена, mock-провайдер и fallback

    private struct MockPriceProvider: MarketPriceProviding {
        let price: Decimal?
        func price(symbol: String, assetClass: MarketAssetClass, on date: Date) -> Decimal? { price }
    }

    @Test
    func engineE_buySellWithProvidedPrice() {
        let events = [
            event(date: day1, type: .buy, quantity: 10, unitPrice: 100),
            event(date: day2, type: .sell, quantity: 3, unitPrice: 110),
        ]
        let meta = MarketMeta(symbol: "AAPL", assetClass: .stock)
        let balance = AccountBalanceEngine.balanceAt(
            events: events,
            kind: .marketInvestment,
            on: day2,
            priceProvider: MockPriceProvider(price: 150),
            marketMeta: meta
        )
        // quantity = 10 - 3 = 7; provider цена 150 → 1050
        #expect(balance == 1050)
    }

    @Test
    func engineE_fallsBackToLastKnownPriceWhenProviderReturnsNil() {
        let events = [
            event(date: day1, type: .buy, quantity: 10, unitPrice: 100),
            event(date: day2, type: .buy, quantity: 5, unitPrice: 120),
        ]
        let meta = MarketMeta(symbol: "AAPL", assetClass: .stock)
        let balance = AccountBalanceEngine.balanceAt(
            events: events,
            kind: .marketInvestment,
            on: day2,
            priceProvider: MockPriceProvider(price: nil),
            marketMeta: meta
        )
        // quantity = 15; provider недоступен → последняя известная цена 120 → 1800
        #expect(balance == 1800)
    }

    /// Долг Фазы 0 (закрыт в 1a-core): цена запрашивается на дату РЕПЛЕЯ `on:`, а не на дату
    /// последнего события — иначе balanceAt(вчера) и balanceAt(сегодня) совпадали бы молча при
    /// неизменном портфеле, хотя рыночная цена за это время могла измениться.
    private final class DateCapturingPriceProvider: MarketPriceProviding {
        private(set) var capturedDates: [Date] = []
        let price: Decimal
        init(price: Decimal) { self.price = price }
        func price(symbol: String, assetClass: MarketAssetClass, on date: Date) -> Decimal? {
            capturedDates.append(date)
            return price
        }
    }

    @Test
    func engineE_queriesPriceProviderWithReplayDateNotLastEventDate() {
        let events = [
            event(date: day1, type: .buy, quantity: 10, unitPrice: 100),
        ]
        let meta = MarketMeta(symbol: "AAPL", assetClass: .stock)
        let provider = DateCapturingPriceProvider(price: 150)

        // Последнее событие — day1, но реплеим на day3: провайдер должен получить day3.
        _ = AccountBalanceEngine.balanceAt(
            events: events, kind: .marketInvestment, on: day3, priceProvider: provider, marketMeta: meta
        )

        #expect(provider.capturedDates == [day3])
    }

    // MARK: - F: manualAsset — последняя revaluation ≤date

    @Test
    func engineF_lastRevaluationBeforeDateWins() {
        let events = [
            event(date: day1, type: .openingBalance, amount: 5_000_000),
            event(date: day2, type: .revaluation, amount: 5_500_000),
            event(date: day3, type: .revaluation, amount: 6_000_000),
        ]
        let balance = AccountBalanceEngine.balanceAt(events: events, kind: .manualAsset, on: day2)
        #expect(balance == 5_500_000)
    }

    @Test
    func engineF_fallsBackToOpeningBalanceWhenNoRevaluationYet() {
        let events = [
            event(date: day1, type: .openingBalance, amount: 5_000_000),
        ]
        let balance = AccountBalanceEngine.balanceAt(events: events, kind: .manualAsset, on: day1)
        #expect(balance == 5_000_000)
    }

    // MARK: - S5: детерминизм при разном порядке вставки

    @Test
    func determinism_sameEventsDifferentInsertionOrderGiveSameBalance() {
        let e1 = event(date: day1, type: .openingBalance, amount: 1000)
        let e2 = event(date: day2, type: .income, amount: 200)
        let e3 = event(date: day2, type: .expense, amount: 50, createdAt: day2.addingTimeInterval(1))

        let order1 = [e1, e2, e3]
        let order2 = [e3, e1, e2]
        let order3 = [e2, e3, e1]

        let b1 = AccountBalanceEngine.balanceAt(events: order1, kind: .bankAccount, on: day3)
        let b2 = AccountBalanceEngine.balanceAt(events: order2, kind: .bankAccount, on: day3)
        let b3 = AccountBalanceEngine.balanceAt(events: order3, kind: .bankAccount, on: day3)

        #expect(b1 == b2)
        #expect(b2 == b3)
        #expect(b1 == 1150)
    }

    // MARK: - Future date: реплей вперёд (прогноз)

    @Test
    func futureDate_includesScheduledFutureEvents() {
        let future = day1.addingTimeInterval(30 * 86_400)
        let events = [
            event(date: day1, type: .openingBalance, amount: 1000),
            event(date: future, type: .interest, amount: 50), // запланированное будущее событие
        ]
        let balanceToday = AccountBalanceEngine.balanceAt(events: events, kind: .deposit, on: day1)
        let balanceFuture = AccountBalanceEngine.balanceAt(events: events, kind: .deposit, on: future)
        #expect(balanceToday == 1000)
        #expect(balanceFuture == 1050)
    }

    // MARK: - AC11/AC15: redenomination — непрерывность и неизменность истории

    @Test
    func redenomination_eventsBeforeDateUnaffectedInRawStorage() {
        let redenomDate = day2
        let events = [
            event(date: day1, type: .openingBalance, amount: 1000), // в старой валюте (напр. до деноминации ₽→новый ₽ 1:1000)
            event(date: redenomDate, type: .redenomination, redenomRate: 0.001, redenomFromCurrency: "OLD"),
            event(date: day3, type: .income, amount: 5), // уже в новой валюте
        ]
        // Сырые данные события day1 не переписываются — проверяем что исходный amount остался 1000.
        #expect(events[0].amount == 1000)

        let balance = AccountBalanceEngine.balanceAt(events: events, kind: .bankAccount, on: day3)
        // 1000 * 0.001 (переоценено в новую валюту) + 5 = 6
        #expect(balance == 6)
    }

    @Test
    func redenomination_balanceContinuousThroughDate() {
        let redenomDate = day2
        let events = [
            event(date: day1, type: .openingBalance, amount: 1000),
            event(date: redenomDate, type: .redenomination, redenomRate: 0.001, redenomFromCurrency: "OLD"),
        ]
        // Значение непосредственно перед редоминацией (в старой валюте) * курс == значение сразу после (AC11/AC15).
        let beforeEpsilon = redenomDate.addingTimeInterval(-1)
        let balanceBeforeRaw = events
            .filter { $0.date <= beforeEpsilon }
            .reduce(Decimal(0)) { $0 + ($1.amount ?? 0) } // 1000, в старой валюте, до конвертации
        let balanceAtRedenomDate = AccountBalanceEngine.balanceAt(events: events, kind: .bankAccount, on: redenomDate)

        #expect(balanceAtRedenomDate == balanceBeforeRaw * 0.001)
    }
}
