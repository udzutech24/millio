import Foundation
import SwiftData

#if DEBUG
/// Полигон тестовых данных нового ядра event-sourcing (план `2026-07-04__accounts-core-rebuild-plan.md`,
/// риск П4) — 11 реальных счетов владельца с настройками из плана (10 из Фазы 0/1 + 1 `.debt` Фазы 2),
/// без риска для данных на устройстве.
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

        let transactionContext = ModelContext(context.container)
        transactionContext.autosaveEnabled = false
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()

        func monthsAgo(_ n: Int) -> Date {
            calendar.date(byAdding: .month, value: -n, to: now) ?? now
        }

        // MARK: Группа «Вклады» — 2 вклада, суммарно ~45 000 000 ₽ + начисление % за 6 мес.
        let depositsGroup = AccountGroup(name: "Вклады")
        transactionContext.insert(depositsGroup)

        // Фаза 3: вклады переведены на `DepositInterestScheduler` — расписание генерируется от даты
        // создания счёта до срока/горизонта, ручных interest-событий больше не вставляем (генератор
        // сам компаундит через реплей, см. `AccountBalanceEngineDepositTests`).
        let deposit1Meta = DepositMeta(
            rate: 12, capitalization: .monthly,
            termEnd: calendar.date(byAdding: .year, value: 1, to: now),
            payoutDay: 1, allowsTopUp: false, allowsEarlyClose: true,
            // Доля УДЕРЖАНИЯ 0…1 (не процент, см. докстринг `DepositMeta.earlyClosePenalty`).
            earlyClosePenalty: 0.5, remindEnd: true, autoRollover: false
        )
        _ = try AccountProductGraphBuilder.build(CreateProductCommand(
            productType: .deposit, name: "Вклад «Надёжный»", currency: "RUB",
            openingBalance: 30_000_000, groupID: depositsGroup.id,
            metadata: .init(deposit: deposit1Meta), date: monthsAgo(6), calendar: calendar
        ), in: transactionContext)

        let deposit2Meta = DepositMeta(
            rate: 10, capitalization: .quarterly,
            termEnd: calendar.date(byAdding: .month, value: 9, to: now),
            payoutDay: 1, allowsTopUp: true, allowsEarlyClose: false,
            earlyClosePenalty: nil, remindEnd: true, autoRollover: true
        )
        _ = try AccountProductGraphBuilder.build(CreateProductCommand(
            productType: .deposit, name: "Вклад «Пополняемый»", currency: "RUB",
            openingBalance: 15_000_000, groupID: depositsGroup.id,
            metadata: .init(deposit: deposit2Meta), date: monthsAgo(6), calendar: calendar
        ), in: transactionContext)

        // MARK: Группа «Иностранные» — валютные счета (~10 400 $ + немного €, 2 счёта до общих 10)
        let foreignGroup = AccountGroup(name: "Иностранные")
        transactionContext.insert(foreignGroup)
        _ = try AccountProductGraphBuilder.build(CreateProductCommand(
            productType: .bankAccount, name: "USD счёт", currency: "USD",
            openingBalance: 10_400, groupID: foreignGroup.id, date: monthsAgo(6)
        ), in: transactionContext)
        _ = try AccountProductGraphBuilder.build(CreateProductCommand(
            productType: .bankAccount, name: "EUR счёт", currency: "EUR",
            openingBalance: 1_800, groupID: foreignGroup.id, date: monthsAgo(6)
        ), in: transactionContext)

        // MARK: Группа «Акции» — 2 позиции, суммарно ~45 000 $
        let stocksGroup = AccountGroup(name: "Акции")
        transactionContext.insert(stocksGroup)
        _ = try AccountProductGraphBuilder.build(CreateProductCommand(
            productType: .marketStock, name: "AAPL", currency: "USD", openingBalance: 0,
            groupID: stocksGroup.id, metadata: .init(market: MarketMeta(symbol: "AAPL", assetClass: .stock)),
            date: monthsAgo(6), initialMarketPurchase: .init(quantity: 100, unitPrice: 180)
        ), in: transactionContext)
        _ = try AccountProductGraphBuilder.build(CreateProductCommand(
            productType: .marketStock, name: "NVDA", currency: "USD", openingBalance: 0,
            groupID: stocksGroup.id, metadata: .init(market: MarketMeta(symbol: "NVDA", assetClass: .stock)),
            date: monthsAgo(5), initialMarketPurchase: .init(quantity: 20, unitPrice: 900)
        ), in: transactionContext)

        // MARK: Группа «Кредиты» — −12 700 000 ₽
        let creditsGroup = AccountGroup(name: "Кредиты")
        transactionContext.insert(creditsGroup)
        // Регрессия найдена при разборе Фазы 2: openingBalance для .loan — МАГНИТУДА (движок C сам
        // применяет знак минус через loanSignMap, см. AccountBalanceEngineTests.engineC_loanDrawAndPayment).
        // Отрицательное число здесь давало ДВОЙНОЕ отрицание — «Ипотека» реплеилась в +12.7М вместо -12.7М.
        let loanMeta = LoanMeta(
            principal: 12_700_000, rate: 9.5, monthlyPayment: 120_000, paymentDay: 5,
            termEnd: calendar.date(byAdding: .year, value: 15, to: now), scheduleType: .annuity, insurance: nil
        )

        // Долг — owedToMe (мне должны) ~500 000 ₽, для полноты полигона обязательств (Фаза 2).
        _ = try AccountProductGraphBuilder.build(CreateProductCommand(
            productType: .loan, name: "Ипотека", currency: "RUB",
            openingBalance: 12_700_000, groupID: creditsGroup.id,
            metadata: .init(loan: loanMeta), date: monthsAgo(6)
        ), in: transactionContext)
        _ = try AccountProductGraphBuilder.build(CreateProductCommand(
            productType: .receivable, name: "Долг Игоря", currency: "RUB",
            openingBalance: 500_000, groupID: creditsGroup.id,
            metadata: .init(debt: DebtMeta(direction: .owedToMe, counterparty: "Игорь", dueDate: calendar.date(byAdding: .month, value: 3, to: now), rate: nil)),
            date: monthsAgo(3)
        ), in: transactionContext)

        // MARK: Карты RUB (3 шт.) — по 2-3 income/expense события
        let cardsGroup = AccountGroup(name: "Карты")
        transactionContext.insert(cardsGroup)
        let cardNames = ["Основная карта", "Карта для покупок", "Карта на чёрный день"]
        for (index, name) in cardNames.enumerated() {
            let graph = try AccountProductGraphBuilder.build(CreateProductCommand(
                productType: .debitCard, name: name, currency: "RUB",
                openingBalance: Decimal(150_000 + index * 50_000), groupID: cardsGroup.id,
                metadata: .init(card: CardMeta(bank: "sberbank", last4: String(format: "%04d", 1000 + index))),
                date: monthsAgo(6)
            ), in: transactionContext)
            transactionContext.insert(AccountEvent(account: graph.account, date: monthsAgo(1), type: .income, amount: 120_000))
            // amount — МАГНИТУДА (движок сам вычитает через cashLikeSignMap(.expense) == -1);
            // отрицательное число здесь давало бы двойное отрицание (тот же баг, что был в
            // AccountDetailView до фикса Фазы 2 — балансы карт молча завышались).
            transactionContext.insert(AccountEvent(account: graph.account, date: monthsAgo(1), type: .expense, amount: 45_000))
            if index == 0 {
                transactionContext.insert(AccountEvent(account: graph.account, date: now, type: .expense, amount: 12_000))
            }
        }

        // MARK: Группа «Недвижимость» — ручной актив (Фаза 4): 2 переоценки, 20М ₽ на сегодня.
        let realEstateGroup = AccountGroup(name: "Недвижимость")
        transactionContext.insert(realEstateGroup)
        let apartment = try AccountProductGraphBuilder.build(CreateProductCommand(
            productType: .realEstate, name: "Квартира", currency: "RUB",
            openingBalance: 17_000_000, groupID: realEstateGroup.id,
            metadata: .init(manualAsset: ManualAssetMeta(revalReminderMonths: 12, depreciationRatePerYear: nil, linkedLoanID: nil)),
            date: monthsAgo(6)
        ), in: transactionContext)
        transactionContext.insert(AccountEvent(account: apartment.account, date: monthsAgo(1), type: .revaluation, amount: 20_000_000))

        // Маркер идемпотентности — служебный счёт вне тоталов (includeInTotal = false).
        _ = try AccountProductGraphBuilder.build(CreateProductCommand(
            productType: .cash, name: markerName, currency: "RUB", openingBalance: 0,
            includeInTotal: false
        ), in: transactionContext)

        do {
            try transactionContext.save()
        } catch {
            transactionContext.rollback()
            throw error
        }
        return true
    }
}
#endif
