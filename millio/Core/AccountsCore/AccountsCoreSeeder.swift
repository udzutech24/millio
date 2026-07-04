import Foundation
import SwiftData

#if DEBUG
/// Полигон тестовых данных нового ядра event-sourcing (план `2026-07-04__accounts-core-rebuild-plan.md`,
/// риск П4) — 10 реальных счетов владельца с настройками из плана, без риска для данных на устройстве.
/// DEBUG-only (недоступен в Release-сборке). Идемпотентно: повторный вызов не дублирует —
/// маркер-счёт `markerName` (не участвует в тоталах) фиксирует «сид уже прогнан».
enum AccountsCoreSeeder {

    static let markerAccountName = "__accounts_core_seed_v1__"

    /// Создаёт демо-портфель. Возвращает `false`, если сид уже был прогнан ранее (no-op).
    @discardableResult
    @MainActor
    static func seedDemoPortfolio(context: ModelContext) throws -> Bool {
        let markerName = markerAccountName
        let markerDescriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.name == markerName }
        )
        guard try context.fetch(markerDescriptor).isEmpty else { return false }

        let service = AccountsCoreService(modelContext: context)
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()

        func monthsAgo(_ n: Int) -> Date {
            calendar.date(byAdding: .month, value: -n, to: now) ?? now
        }

        // MARK: Группа «Вклады» — 2 вклада, суммарно ~45 000 000 ₽ + начисление % за 6 мес.
        let depositsGroup = AccountGroup(name: "Вклады")
        context.insert(depositsGroup)

        let deposit1 = try service.createAccount(
            name: "Вклад «Надёжный»", kind: .deposit, currency: "RUB",
            openingBalance: 30_000_000, group: depositsGroup, date: monthsAgo(6)
        )
        deposit1.depositMeta = DepositMeta(
            rate: 12, capitalization: .monthly,
            termEnd: calendar.date(byAdding: .year, value: 1, to: now),
            payoutDay: 1, allowsTopUp: false, allowsEarlyClose: true,
            earlyClosePenalty: 50, remindEnd: true, autoRollover: false
        )
        appendMonthlyInterest(to: deposit1, principal: 30_000_000, annualRate: 12, months: 6, context: context, calendar: calendar, now: now)

        let deposit2 = try service.createAccount(
            name: "Вклад «Пополняемый»", kind: .deposit, currency: "RUB",
            openingBalance: 15_000_000, group: depositsGroup, date: monthsAgo(6)
        )
        deposit2.depositMeta = DepositMeta(
            rate: 10, capitalization: .quarterly,
            termEnd: calendar.date(byAdding: .month, value: 9, to: now),
            payoutDay: 1, allowsTopUp: true, allowsEarlyClose: false,
            earlyClosePenalty: nil, remindEnd: true, autoRollover: true
        )
        appendMonthlyInterest(to: deposit2, principal: 15_000_000, annualRate: 10, months: 6, context: context, calendar: calendar, now: now)

        // MARK: Группа «Иностранные» — валютные счета (~10 400 $ + немного €, 2 счёта до общих 10)
        let foreignGroup = AccountGroup(name: "Иностранные")
        context.insert(foreignGroup)
        try service.createAccount(
            name: "USD счёт", kind: .bankAccount, currency: "USD",
            openingBalance: 10_400, group: foreignGroup, date: monthsAgo(6)
        )
        try service.createAccount(
            name: "EUR счёт", kind: .bankAccount, currency: "EUR",
            openingBalance: 1_800, group: foreignGroup, date: monthsAgo(6)
        )

        // MARK: Группа «Акции» — 2 позиции, суммарно ~45 000 $
        let stocksGroup = AccountGroup(name: "Акции")
        context.insert(stocksGroup)

        let stock1 = try service.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD",
            openingBalance: 0, group: stocksGroup, date: monthsAgo(6)
        )
        stock1.marketMeta = MarketMeta(symbol: "AAPL", assetClass: .stock)
        context.insert(AccountEvent(account: stock1, date: monthsAgo(6), type: .buy, quantity: 100, unitPrice: 180))

        let stock2 = try service.createAccount(
            name: "NVDA", kind: .marketInvestment, currency: "USD",
            openingBalance: 0, group: stocksGroup, date: monthsAgo(5)
        )
        stock2.marketMeta = MarketMeta(symbol: "NVDA", assetClass: .stock)
        context.insert(AccountEvent(account: stock2, date: monthsAgo(5), type: .buy, quantity: 20, unitPrice: 900))

        // MARK: Группа «Кредиты» — −12 700 000 ₽
        let creditsGroup = AccountGroup(name: "Кредиты")
        context.insert(creditsGroup)
        let loan = try service.createAccount(
            name: "Ипотека", kind: .loan, currency: "RUB",
            openingBalance: -12_700_000, group: creditsGroup, date: monthsAgo(6)
        )
        loan.loanMeta = LoanMeta(
            principal: 12_700_000, rate: 9.5, monthlyPayment: 120_000, paymentDay: 5,
            termEnd: calendar.date(byAdding: .year, value: 15, to: now), scheduleType: .annuity, insurance: nil
        )

        // MARK: Карты RUB (3 шт.) — по 2-3 income/expense события
        let cardsGroup = AccountGroup(name: "Карты")
        context.insert(cardsGroup)
        let cardNames = ["Основная карта", "Карта для покупок", "Карта на чёрный день"]
        for (index, name) in cardNames.enumerated() {
            let card = try service.createAccount(
                name: name, kind: .debitCard, currency: "RUB",
                openingBalance: Decimal(150_000 + index * 50_000), group: cardsGroup, date: monthsAgo(6)
            )
            card.cardMeta = CardMeta(bank: "sberbank", last4: String(format: "%04d", 1000 + index))
            try service.recordEvent(account: card, type: .income, amount: 120_000, date: monthsAgo(1))
            try service.recordEvent(account: card, type: .expense, amount: -45_000, date: monthsAgo(1))
            if index == 0 {
                try service.recordEvent(account: card, type: .expense, amount: -12_000, date: now)
            }
        }

        // Маркер идемпотентности — служебный счёт вне тоталов (includeInTotal = false).
        let marker = Account(name: markerName, kind: .cash, currency: "RUB")
        marker.includeInTotal = false
        context.insert(marker)

        try context.save()
        return true
    }

    /// Упрощённое ежемесячное начисление % (простой процент от principal/12) — полигон для UI,
    /// НЕ расчётный движок вклада (капитализация/сложный процент — предмет Фазы 3).
    private static func appendMonthlyInterest(
        to account: Account,
        principal: Decimal,
        annualRate: Decimal,
        months: Int,
        context: ModelContext,
        calendar: Calendar,
        now: Date
    ) {
        let monthlyInterest = principal * annualRate / 100 / 12
        for monthsBack in stride(from: months, through: 1, by: -1) {
            guard let date = calendar.date(byAdding: .month, value: -monthsBack, to: now) else { continue }
            context.insert(AccountEvent(account: account, date: date, type: .interest, amount: monthlyInterest))
        }
    }
}
#endif
