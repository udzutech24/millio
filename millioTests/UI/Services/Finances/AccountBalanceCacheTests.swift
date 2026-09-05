//
//  AccountBalanceCacheTests.swift
//  millioTests
//
//  Ф1 плана 2026-09-05__scroll-navigation-performance: кэш баланса строки списка счетов.
//
//  Инвариант-теста НЕДОСТАТОЧНО — в проекте уже был случай (Ф7b-2, память «интеграционный тест
//  пути создания»), когда трансформация была зелёной, а путь создания давал расхождение.
//  Поэтому здесь оба уровня: чистый инвариант «кэш == реплей» и путь мутации целиком
//  (создание события, adjustBalance, правка меты кредитки).
//

import Foundation
import Testing
import SwiftData
@testable import millio

@Suite("Кэш баланса счёта (Ф1)", .serialized)
struct AccountBalanceCacheTests {

    private static let baseDate = Date(timeIntervalSince1970: 1_600_000_000)
    /// «Сегодня» фиксировано: реплей считает баланс на дату, плавающий `Date()` сделал бы тест
    /// зависимым от часа прогона.
    private static let today = baseDate.addingTimeInterval(86_400 * 400)

    @MainActor
    private func makeViewModel(context: ModelContext) -> FinanceViewModel {
        FinanceViewModel(
            modelContext: context,
            currencyService: MockCurrencyRateService(),
            now: { Self.today },
            skipInitialLoad: true
        )
    }

    /// Эталон, посчитанный в обход кэша — тем же движком, что и продакшн-путь.
    @MainActor
    private func directReplay(_ account: Account) -> Decimal {
        let raw = AccountBalanceEngine.balanceAt(
            events: DepositConfirmedBalanceResolver.confirmedEvents(
                account.events ?? [], accountID: account.id, kind: account.kind
            ),
            kind: account.kind,
            on: Self.today,
            marketMeta: account.marketMeta
        )
        return AccountTotalsContribution.signedValue(
            rawBalance: raw,
            kind: account.kind,
            creditLimit: account.cardMeta?.creditLimit
        )
    }

    @discardableResult
    @MainActor
    private func seedAccount(
        _ service: AccountsCoreService,
        context: ModelContext,
        name: String,
        kind: AccountKind,
        currency: String,
        eventCount: Int
    ) throws -> Account {
        let account = try service.createAccount(
            name: name,
            kind: kind,
            currency: currency,
            openingBalance: 100_000,
            date: Self.baseDate
        )
        for step in 0..<eventCount {
            context.insert(AccountEvent(
                account: account,
                date: Self.baseDate.addingTimeInterval(TimeInterval(86_400 * (step + 1))),
                createdAt: Self.baseDate,
                type: step % 2 == 0 ? .income : .expense,
                amount: Decimal(500 + step * 13)
            ))
        }
        try context.save()
        return account
    }

    // MARK: - Инвариант

    @Test("Кэш совпадает с прямым реплеем для каждого счёта (3 счёта × 50+ событий)")
    @MainActor
    func cacheMatchesDirectReplay() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)

        let specs: [(String, AccountKind, String, Int)] = [
            ("Рублёвый счёт", .bankAccount, "RUB", 50),
            ("Вклад", .deposit, "RUB", 60),
            ("Долларовая карта", .debitCard, "USD", 75),
        ]
        var accounts: [Account] = []
        for spec in specs {
            accounts.append(try seedAccount(
                service, context: context,
                name: spec.0, kind: spec.1, currency: spec.2, eventCount: spec.3
            ))
        }

        let viewModel = makeViewModel(context: context)
        viewModel.handle(.loadGroups)

        #expect(viewModel.balanceCache.count == accounts.count)
        for account in accounts {
            // Значение реально пришло из кэша, а не свалилось в аварийный реплей —
            // иначе тест был бы зелёным и при полностью нерабочем кэше.
            #expect(viewModel.balanceCache.value(for: account, today: Self.today) != nil)
            #expect(viewModel.newCoreBalanceToday(account) == directReplay(account))
        }
    }

    @Test("Отпечаток ревизий не совпал — значение считается заново, а не отдаётся протухшим")
    @MainActor
    func staleStampFallsBackToReplay() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)
        let account = try seedAccount(
            service, context: context,
            name: "Счёт", kind: .bankAccount, currency: "RUB", eventCount: 50
        )

        let viewModel = makeViewModel(context: context)
        viewModel.handle(.loadGroups)
        let before = viewModel.newCoreBalanceToday(account)

        // Пишем событие ЧЕРЕЗ сервис, но экрану не сообщаем (не публикуем FinanceEvent и не
        // зовём loadGroups) — ровно тот сценарий, в котором наивный кэш вернул бы старую цифру.
        _ = try service.recordEvent(account: account, type: .income, amount: 7_777, date: Self.baseDate)

        #expect(viewModel.balanceCache.value(for: account, today: Self.today) == nil)
        #expect(viewModel.newCoreBalanceToday(account) == before + 7_777)
        #expect(viewModel.newCoreBalanceToday(account) == directReplay(account))
    }

    @Test("Смена суток инвалидирует срез: баланс — величина «на сегодня»")
    @MainActor
    func dayRolloverInvalidatesCache() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)
        let account = try seedAccount(
            service, context: context,
            name: "Счёт", kind: .bankAccount, currency: "RUB", eventCount: 50
        )

        let viewModel = makeViewModel(context: context)
        viewModel.handle(.loadGroups)

        #expect(viewModel.balanceCache.value(for: account, today: Self.today) != nil)
        let tomorrow = Self.today.addingTimeInterval(86_400)
        #expect(viewModel.balanceCache.value(for: account, today: tomorrow) == nil)
    }

    // MARK: - Интеграция: путь создания/правки

    @Test("Путь создания события: после публикации мутации кэш пересчитан и совпал с реплеем")
    @MainActor
    func creationPathRefreshesCache() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)
        let account = try seedAccount(
            service, context: context,
            name: "Счёт", kind: .bankAccount, currency: "RUB", eventCount: 50
        )

        let viewModel = makeViewModel(context: context)
        viewModel.handle(.loadGroups)
        let before = viewModel.newCoreBalanceToday(account)

        _ = try service.recordEvent(account: account, type: .expense, amount: 12_345, date: Self.baseDate)
        // Продакшн-путь оповещения экрана о core-мутации.
        viewModel.handle(.loadGroups)

        #expect(viewModel.balanceCache.value(for: account, today: Self.today) == before - 12_345)
        #expect(viewModel.newCoreBalanceToday(account) == directReplay(account))
    }

    @Test("Путь adjustBalance: исторический рассинхрон не воспроизводится, кэш == реплей")
    @MainActor
    func adjustBalancePathRefreshesCache() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)
        let account = try seedAccount(
            service, context: context,
            name: "Счёт", kind: .bankAccount, currency: "RUB", eventCount: 50
        )

        let viewModel = makeViewModel(context: context)
        viewModel.handle(.loadGroups)

        // Корректировка датируется СЕГОДНЯ: правка задним числом задаёт баланс на ту дату, а
        // поверх неё лягут 50 более поздних событий — «ровно 42 000» тогда не ожидается.
        _ = try service.adjustBalance(account: account, to: 42_000, on: Self.today)
        viewModel.handle(.loadGroups)

        #expect(viewModel.balanceCache.value(for: account, today: Self.today) == 42_000)
        #expect(viewModel.newCoreBalanceToday(account) == directReplay(account))
        #expect(viewModel.newCoreBalanceToday(account) == 42_000)
    }

    @Test("Правка creditLimit меняет знаковый вклад строки — кэш обязан это увидеть")
    @MainActor
    func creditLimitChangeInvalidatesCache() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)

        let card = try service.createAccount(
            name: "Кредитка",
            kind: .debitCard,
            currency: "RUB",
            openingBalance: -30_000,
            cardMeta: CardMeta(bank: nil, last4: nil, creditLimit: 100_000, statementDay: nil,
                               dueDay: nil, minPayment: nil, graceDays: nil, overdraftLimit: nil),
            date: Self.baseDate
        )
        try context.save()

        let viewModel = makeViewModel(context: context)
        viewModel.handle(.loadGroups)
        #expect(viewModel.newCoreBalanceToday(card) == directReplay(card))

        // `.financial`-ревизия, а не `.events`: отпечаток обязан учитывать и её.
        card.cardMeta = CardMeta(bank: nil, last4: nil, creditLimit: 250_000, statementDay: nil,
                                 dueDay: nil, minPayment: nil, graceDays: nil, overdraftLimit: nil)
        HistoricalValuationRevisionTracker.bump([.financial], on: card)
        try context.save()

        #expect(viewModel.newCoreBalanceToday(card) == directReplay(card))
    }
}
