import Foundation
import SwiftData
import XCTest
@testable import millio

/// Цифры дайджеста обязаны совпадать с экраном рыночной позиции: стоимость из hero и «Доля в портфеле».
/// Портфель: SBER (кэш цен есть), GAZP (куплен внутри окна), YNDX (кэша нет — цена последней сделки),
/// AAPL в USD (вне дайджеста), архивный LKOH (вне круга позиций).
@MainActor
final class MarketPortfolioValuationTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let now = Date()

    override func setUp() async throws {
        try await super.setUp()
        container = try AppMigrationPlan.makeInMemoryContainer()
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: now)!
    }

    @discardableResult
    private func position(
        _ symbol: String,
        currency: String = "RUB",
        quantity: Decimal,
        buyPrice: Decimal,
        boughtDaysAgo: Int
    ) throws -> Account {
        let service = AccountsCoreService(modelContext: context)
        let account = try service.createAccount(
            name: symbol,
            kind: .marketInvestment,
            currency: currency,
            openingBalance: 0,
            marketMeta: MarketMeta(symbol: symbol, assetClass: .stock),
            date: daysAgo(boughtDaysAgo + 1)
        )
        try service.buy(account: account, quantity: quantity, unitPrice: buyPrice, date: daysAgo(boughtDaysAgo))
        return account
    }

    private func cachePrice(_ symbol: String, _ price: Decimal, daysAgo days: Int) {
        context.insert(HistoricalAssetPrice(
            symbol: symbol,
            assetClass: .stock,
            dayKey: AccountEvent.dayKey(for: daysAgo(days)),
            price: price,
            source: "test"
        ))
    }

    private func seedPortfolio() throws -> [String: Account] {
        let sber = try position("SBER", quantity: 10, buyPrice: 250, boughtDaysAgo: 60)
        cachePrice("SBER", 280, daysAgo: 45)
        cachePrice("SBER", 300, daysAgo: 0)

        let gazp = try position("GAZP", quantity: 20, buyPrice: 120, boughtDaysAgo: 10)
        cachePrice("GAZP", 150, daysAgo: 0)

        let yndx = try position("YNDX", quantity: 2, buyPrice: 4_000, boughtDaysAgo: 40)

        try position("AAPL", currency: "USD", quantity: 5, buyPrice: 200, boughtDaysAgo: 20)
        cachePrice("AAPL", 210, daysAgo: 0)

        let archived = try position("LKOH", quantity: 1, buyPrice: 7_000, boughtDaysAgo: 50)
        try AccountsCoreService(modelContext: context).archiveAccount(archived)

        try context.save()
        return ["SBER": sber, "GAZP": gazp, "YNDX": yndx]
    }

    private func digest(_ window: AIPortfolioWindow = .month, currency: String = "RUB") -> AIPortfolioFigures? {
        AIPortfolioDigestFiguresSource(modelContext: context, currency: currency, now: { self.now })
            .figures(for: window)
    }

    // MARK: - Совпадение с экраном позиции

    func testDigestPositionsMatchInvestmentScreenValueAndShare() throws {
        let accounts = try seedPortfolio()
        let figures = try XCTUnwrap(digest())

        XCTAssertEqual(Set(figures.positions.map(\.symbol)), ["SBER", "GAZP", "YNDX"])
        for position in figures.positions {
            let account = try XCTUnwrap(accounts[position.symbol])
            let screen = AccountDetailView(account: account, modelContext: context)
            XCTAssertEqual(position.value, screen.balanceToday, "стоимость \(position.symbol)")
            XCTAssertEqual(position.sharePercent, try XCTUnwrap(screen.portfolioSharePercent), "доля \(position.symbol)")
        }
        XCTAssertEqual(figures.value, MarketPortfolioValuation(modelContext: context).portfolioTotal(currency: "RUB"))
    }

    /// Регресс выноса расчёта в Core: доля экрана = стоимость / Σ(FIFO-количество × цена) × 100.
    func testScreenShareKeepsItsFormulaAfterExtraction() throws {
        let accounts = try seedPortfolio()
        let sber = AccountDetailView(account: try XCTUnwrap(accounts["SBER"]), modelContext: context)
        let yndx = AccountDetailView(account: try XCTUnwrap(accounts["YNDX"]), modelContext: context)

        XCTAssertEqual(sber.balanceToday, 3_000)
        XCTAssertEqual(sber.portfolioSharePercent, Decimal(3_000) / 14_000 * 100)
        // Без кэша котировок — цена последней сделки и в стоимости, и в знаменателе.
        XCTAssertEqual(yndx.balanceToday, 8_000)
        XCTAssertEqual(yndx.portfolioSharePercent, Decimal(8_000) / 14_000 * 100)
    }

    /// Hero любого счёта теперь идёт через `positionValue` — у не-рыночных счетов цифра обязана
    /// остаться прежней формулой подтверждённого баланса (без провайдера цен).
    func testHeroBalanceOfNonMarketAccountsKeepsConfirmedBalanceFormula() throws {
        let service = AccountsCoreService(modelContext: context)
        let cash = try service.createAccount(
            name: "Наличные", kind: .cash, currency: "RUB", openingBalance: 12_345, date: daysAgo(30)
        )
        let deposit = try service.createAccount(
            name: "Вклад", kind: .deposit, currency: "RUB", openingBalance: 100_000,
            depositMeta: DepositMeta(
                rate: 12, capitalization: .monthly,
                termEnd: Calendar.current.date(byAdding: .month, value: 6, to: now),
                payoutDay: nil, allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
                remindEnd: false, autoRollover: false
            ),
            date: daysAgo(40)
        )
        try context.save()

        for account in [cash, deposit] {
            let preExtraction = AccountBalanceEngine.balanceAt(
                events: DepositConfirmedBalanceResolver.confirmedEvents(
                    account.events ?? [], accountID: account.id, kind: account.kind
                ),
                kind: account.kind,
                on: Date(),
                priceProvider: nil,
                marketMeta: account.marketMeta
            )
            XCTAssertEqual(
                AccountDetailView(account: account, modelContext: context).balanceToday,
                preExtraction,
                "\(account.kind)"
            )
        }
        XCTAssertEqual(AccountDetailView(account: cash, modelContext: context).balanceToday, 12_345)
    }

    // MARK: - Изменение за окно

    func testPriceChangeUsesCachedPriceAtWindowStartAndPurchasePriceInsideWindow() throws {
        _ = try seedPortfolio()
        let figures = try XCTUnwrap(digest(.month))
        let bySymbol = Dictionary(uniqueKeysWithValues: figures.positions.map { ($0.symbol, $0) })

        // SBER: на начало окна в кэше 280 (форвард-филл), сейчас 300.
        XCTAssertEqual(AIPortfolioDigestPayloadBuilder.rounded(try XCTUnwrap(bySymbol["SBER"]).changePercent), 7.14)
        // GAZP куплен внутри окна по 120 — меряется от цены покупки.
        XCTAssertEqual(AIPortfolioDigestPayloadBuilder.rounded(try XCTUnwrap(bySymbol["GAZP"]).changePercent), 25)
        // YNDX без котировок — цена не менялась.
        XCTAssertEqual(try XCTUnwrap(bySymbol["YNDX"]).changePercent, 0)
        XCTAssertEqual(figures.changeAmount, 800)
    }

    // MARK: - Границы

    func testOtherCurrencyPositionsAreListedAsExcluded() throws {
        _ = try seedPortfolio()
        XCTAssertEqual(try XCTUnwrap(digest()).excludedCurrencies, ["USD"])
        XCTAssertEqual(try XCTUnwrap(digest(currency: "USD")).excludedCurrencies, ["RUB"])
    }

    func testCurrencyWithoutOpenPositionsGivesNoFigures() throws {
        _ = try seedPortfolio()
        XCTAssertNil(digest(currency: "EUR"))
    }
}
