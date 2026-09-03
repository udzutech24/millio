import Foundation
import SwiftData
import Testing
@testable import millio

/// Ручной ремонт «Альфа Кредитка»: старая LegacyAccountConversion записала кредитку дебетовой
/// картой без creditLimit — «Итого» получало долг со знаком плюс. `DebitToCreditCardRepair` чинит
/// ТОЛЬКО по явному действию владельца (никакой эвристики), одним append-only событием.
@Suite("Debit to credit card repair")
@MainActor
struct DebitToCreditCardRepairTests {

    private func account(_ id: UUID, in context: ModelContext) throws -> Account {
        try #require(try context.fetch(FetchDescriptor<Account>()).first { $0.id == id })
    }

    private func events(_ id: UUID, in context: ModelContext) throws -> [AccountEvent] {
        try context.fetch(FetchDescriptor<AccountEvent>()).filter { $0.account?.id == id }
    }

    // MARK: (1) Интеграционный: конвертация → save → refetch

    @Test("Repaired account survives save/refetch with correct productType, limit and signed value")
    func repairSurvivesRefetch() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let id = try AccountProductFactory(modelContext: context).create(.init(
            productType: .debitCard, name: "Debit", currency: "RUB",
            openingBalance: 50_000, metadata: .init(card: CardMeta())
        ))
        let acc = try account(id, in: context)
        let service = AccountsCoreService(modelContext: context)

        _ = try DebitToCreditCardRepair.apply(
            account: acc, creditLimit: 200_000, balanceToday: 50_000,
            service: service, context: context
        )

        let freshContext = ModelContext(container)
        let reloaded = try account(id, in: freshContext)
        #expect(reloaded.productTypeRaw == AccountProductType.creditCard.rawValue)
        #expect(reloaded.kindRaw == AccountKind.debitCard.rawValue)
        #expect(reloaded.cardMeta?.creditLimit == 200_000)
        let balance = AccountBalanceEngine.balanceAt(events: reloaded.events ?? [], kind: reloaded.kind, on: Date())
        let signed = AccountTotalsContribution.signedValue(rawBalance: balance, kind: reloaded.kind, creditLimit: reloaded.cardMeta?.creditLimit)
        // Долг 50 000 при лимите 200 000 → доступно 150 000 → вклад в «Итого» −50 000.
        #expect(signed == -50_000)
    }

    // MARK: (2) Реальный испорченный счёт: до ремонта +долг, после — −долг

    @Test("Persisted debitCard-that-should-be-creditCard: contribution flips from positive to negative debt")
    func persistedDebitCardRepairFlipsContributionSign() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        // Тот же паттерн, что у «Альфа Кредитка»: openingBalance −17 246 + adjustment +151 076 =
        // 133 830. Собираем счёт НАПРЯМУЮ (не через `AccountProductFactory` — тот отдельно валидирует
        // положительный opening для .debitCard при СОЗДАНИИ, а мы моделируем УЖЕ существующий,
        // испорченный старой миграцией счёт, а не создание нового сегодня).
        let acc = Account(name: "Alpha Card", kind: .debitCard, productType: .debitCard, currency: "RUB")
        acc.cardMeta = CardMeta()
        context.insert(acc)
        context.insert(AccountEvent(account: acc, date: Date(), type: .openingBalance, amount: -17_246))
        try context.save()
        let id = acc.id

        let service = AccountsCoreService(modelContext: context)
        _ = try service.adjustBalance(account: acc, to: 133_830)

        let balanceBefore = AccountBalanceEngine.balanceAt(events: acc.events ?? [], kind: acc.kind, on: Date())
        let signedBefore = AccountTotalsContribution.signedValue(rawBalance: balanceBefore, kind: acc.kind, creditLimit: acc.cardMeta?.creditLimit)
        // Баг: без лимита сырой баланс читается как есть — долг вкладывается в «Итого» ПЛЮСОМ.
        #expect(signedBefore == 133_830)

        _ = try DebitToCreditCardRepair.apply(
            account: acc, creditLimit: 1_500_000, balanceToday: balanceBefore,
            service: service, context: context
        )

        let freshContext = ModelContext(container)
        let repaired = try account(id, in: freshContext)
        let balanceAfter = AccountBalanceEngine.balanceAt(events: repaired.events ?? [], kind: repaired.kind, on: Date())
        let signedAfter = AccountTotalsContribution.signedValue(rawBalance: balanceAfter, kind: repaired.kind, creditLimit: repaired.cardMeta?.creditLimit)
        #expect(signedAfter == -133_830)
        #expect(signedAfter == -balanceBefore)

        // Ручные события — openingBalance и adjustment — целы, не удалены и не переписаны.
        let all = try events(id, in: freshContext)
        #expect(all.contains { $0.type == .openingBalance && $0.amount == -17_246 })
        #expect(all.contains { $0.type == .adjustment && $0.amount == 151_076 })
    }

    // MARK: (3) adjust() на кредитке с лимитом — запрет писать долг плюсом

    @Test("DebitCardOperationCoordinator.adjust refuses accounts with a credit limit")
    func adjustRefusesAccountsWithCreditLimit() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let id = try AccountProductFactory(modelContext: context).create(.init(
            productType: .debitCard, name: "Debit", currency: "RUB",
            openingBalance: 10_000, metadata: .init(card: CardMeta())
        ))
        let acc = try account(id, in: context)
        let service = AccountsCoreService(modelContext: context)
        _ = try DebitToCreditCardRepair.apply(
            account: acc, creditLimit: 100_000, balanceToday: 10_000,
            service: service, context: context
        )

        let coordinator = DebitCardOperationCoordinator(modelContext: context)
        #expect(throws: DebitCardOperationCoordinatorError.creditCardRequiresCreditSemantics) {
            try coordinator.adjust(
                account: acc, to: 50_000, operationID: "debit-detail:1",
                reason: "manual_balance_correction"
            )
        }
    }

    // MARK: (4) Числа владельца: лимит 1 500 000, долг 133 830

    @Test("Owner's exact numbers: limit 1,500,000 and debt 133,830 give balance 1,366,170 and −133,830 contribution")
    func ownerExactNumbers() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let acc = Account(name: "Alpha Card", kind: .debitCard, productType: .debitCard, currency: "RUB")
        acc.cardMeta = CardMeta()
        context.insert(acc)
        context.insert(AccountEvent(account: acc, date: Date(), type: .openingBalance, amount: -17_246))
        try context.save()
        let id = acc.id

        let service = AccountsCoreService(modelContext: context)
        _ = try service.adjustBalance(account: acc, to: 133_830)

        let preview = DebitToCreditCardRepair.preview(balanceToday: 133_830, creditLimit: 1_500_000)
        #expect(preview?.availableAfter == 1_366_170)
        #expect(preview?.contributionAfter == -133_830)

        _ = try DebitToCreditCardRepair.apply(
            account: acc, creditLimit: 1_500_000, balanceToday: 133_830,
            service: service, context: context
        )

        let freshContext = ModelContext(container)
        let repaired = try account(id, in: freshContext)
        let balance = AccountBalanceEngine.balanceAt(events: repaired.events ?? [], kind: repaired.kind, on: Date())
        #expect(balance == 1_366_170)
        let signed = AccountTotalsContribution.signedValue(rawBalance: balance, kind: repaired.kind, creditLimit: repaired.cardMeta?.creditLimit)
        #expect(signed == -133_830)
    }

    // MARK: Валидация лимита

    @Test("Zero or missing limit is rejected, account untouched")
    func zeroLimitIsRejected() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let id = try AccountProductFactory(modelContext: context).create(.init(
            productType: .debitCard, name: "Debit", currency: "RUB",
            openingBalance: 10_000, metadata: .init(card: CardMeta())
        ))
        let acc = try account(id, in: context)
        let service = AccountsCoreService(modelContext: context)

        #expect(DebitToCreditCardRepair.preview(balanceToday: 10_000, creditLimit: 0) == nil)
        #expect(throws: DebitToCreditCardRepair.RepairError.invalidLimit) {
            try DebitToCreditCardRepair.apply(
                account: acc, creditLimit: 0, balanceToday: 10_000,
                service: service, context: context
            )
        }
        #expect(acc.productType == .debitCard)
        #expect(acc.cardMeta?.creditLimit == nil)
    }
}
