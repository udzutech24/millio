import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5c.7 Gate B (2026-07-11) — CHARACTERIZATION-замок на `FinanceViewModel.updateAccountAmount`
/// (270 строк, `FinanceViewModel.swift:1600-1868`) ДО будущего контрактного флипа на
/// `AccountsCoreService.adjustBalance`. 0 продакшн-правок — только фиксация фактического поведения
/// конкретными числами + карта расхождений семантики legacy↔core (комментарий ниже), чтобы флип
/// был доказуем тестом, а не предположением.
///
/// ## Карта конвенций (legacy `updateAccountAmount` vs core `adjustBalance`)
///
/// | Тип | legacy: что означает `newAmount` | legacy: знак аудит-транзакции | core: что означает `to newValue` | core: знак `AccountEvent` |
/// |---|---|---|---|---|
/// | Card (дебет) | новый БАЛАНС (как есть) | `+difference` (рост баланса → `+`) | новый ЗНАКОВЫЙ баланс (cashLike, `AccountBalanceEngine`) | `newValue - current` (без инверсии) |
/// | Card (кредитка) | новый ДОЛГ (положительное число, `limit - balance`) | `-difference` (рост долга → `-`, т.к. баланс карты падает) | тот же принцип, что `.loan`, если кредитка мигрирует туда | `newValue - current`, БЕЗ инверсии по kind |
/// | Credit (продукт) | новый ОСТАТОК ДОЛГА (положительное число) | `-difference` (рост долга → `-`) | `.loan`: `newValue` — уже ЗНАКОВЫЙ баланс (обычно ≤0 для долга) | `newValue - current`, БЕЗ инверсии |
/// | Investment (manual) | новая СТОИМОСТЬ (как есть) | `+difference` | `.manualAsset`/cashLike-подобный: `newValue` как есть | `newValue - current` |
/// | Investment (market) | новое КОЛИЧЕСТВО (не сумма!), `amount` пересчитывается через unit price | `+difference` (разница в ПЕРЕСЧИТАННОЙ стоимости, не в quantity) | `.marketInvestment`: `adjustBalance` НЕ трогает quantity — это отдельный путь (`buy`/`sell`), `adjustBalance` создаёт `.adjustment`-событие поверх market-реплея (риск двойного смысла, не покрыто) | `newValue - current` |
///
/// **Главное расхождение для флипа:** core `adjustBalance` НИКОГДА не инвертирует знак дельты по
/// `kind` — сырой `delta = newValue - current` идёт в `AccountEvent`, интерпретацию (что означает
/// «долг растёт») берёт на себя `AccountBalanceEngine`-signMap ПРИ РЕПЛЕЕ. Legacy `updateAccountAmount`,
/// наоборот, ИНВЕРТИРУЕТ знак вручную для credit/кредитки на этапе СОЗДАНИЯ аудит-транзакции. Флип
/// обязан решить: (а) `newValue` для `.loan`/`.debt` передаётся UI в ЗНАКОВОЙ (net-worth) конвенции,
/// как уже делает `AccountAdjustBalanceSheet` (`AccountDetailView.swift:734-736`, `currentBalance:
/// balanceToday` — уже знаковый), а не в конвенции «положительный долг», как legacy quick-edit
/// формы — это UX-разница, не просто rename.
///
/// **Edge (дельта ≈0, как есть сейчас):** модель ВСЁ РАВНО обновляется (`updatedAt`, `save()`,
/// `loadAccounts()`, `calculateTotalAmount()`, `publishAccountChangedEvent`), но
/// `CashflowTransaction` НЕ создаётся и `EventBus.transactionsUpdated` НЕ публикуется — тихий
/// no-audit апдейт. Не баг (это намеренный guard `abs(difference) > 0.01`), но флип обязан
/// сохранить это же поведение или явно решить иначе — не предполагать.
@Suite("FinanceViewModel.updateAccountAmount — characterization-замок (Ф5c.7 Gate B)")
@MainActor
struct FinanceViewModelUpdateAccountAmountCharacterizationTests {

    private static var retained: [AnyObject] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retained.append(container)
        return container.mainContext
    }

    private func makeViewModel(_ ctx: ModelContext) -> FinanceViewModel {
        let vm = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        Self.retained.append(vm)
        return vm
    }

    private func fetchTransactions(_ ctx: ModelContext) throws -> [CashflowTransaction] {
        try ctx.fetch(FetchDescriptor<CashflowTransaction>())
    }

    // MARK: - Card (дебет)

    @Test("card debit: рост 10000→15000 → tx +5000, cardBalanceAdjustment")
    func cardDebitIncrease() throws {
        let ctx = try makeContext()
        let card = Card(name: "Дебет", cardNumber: "1111", bank: .other, cardType: .debit, currency: "RUB", balance: 10_000)
        ctx.insert(card)
        let junction = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        junction.group = FinanceSystemGroups.ensureUngroupedGroup(in: ctx)
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)
        vm.handle(.updateAccountAmount(junction, 15_000))

        #expect(abs(card.balance - 15_000) < 0.01)
        let txs = try fetchTransactions(ctx)
        #expect(txs.count == 1)
        #expect(txs.first?.transactionType == .cardBalanceAdjustment)
        #expect(abs((txs.first?.amount ?? 0) - 5_000) < 0.01)
    }

    @Test("card debit: падение 10000→6000 → tx -4000")
    func cardDebitDecrease() throws {
        let ctx = try makeContext()
        let card = Card(name: "Дебет", cardNumber: "1111", bank: .other, cardType: .debit, currency: "RUB", balance: 10_000)
        ctx.insert(card)
        let junction = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        junction.group = FinanceSystemGroups.ensureUngroupedGroup(in: ctx)
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)
        vm.handle(.updateAccountAmount(junction, 6_000))

        #expect(abs(card.balance - 6_000) < 0.01)
        let txs = try fetchTransactions(ctx)
        #expect(abs((txs.first?.amount ?? 0) - (-4_000)) < 0.01)
    }

    @Test("card debit: дельта≈0 (10000→10000.005) не создаёт транзакцию, баланс всё равно пишется")
    func cardDebitZeroDeltaEdge() throws {
        let ctx = try makeContext()
        let card = Card(name: "Дебет", cardNumber: "1111", bank: .other, cardType: .debit, currency: "RUB", balance: 10_000)
        ctx.insert(card)
        let junction = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        junction.group = FinanceSystemGroups.ensureUngroupedGroup(in: ctx)
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)
        vm.handle(.updateAccountAmount(junction, 10_000.005))

        #expect(abs(card.balance - 10_000.005) < 0.001, "баланс пишется даже при дельте внутри эпсилон")
        let txs = try fetchTransactions(ctx)
        #expect(txs.isEmpty, "транзакция НЕ создаётся при |difference| <= 0.01 — тихий апдейт без аудита")
    }

    // MARK: - Card (кредитка)

    @Test("card credit: долг растёт 3000→8000 (лимит 20000) → tx -5000, creditDebtAdjustment")
    func cardCreditIncrease() throws {
        let ctx = try makeContext()
        let card = Card(name: "Кредитка", cardNumber: "2222", bank: .other, cardType: .credit, currency: "RUB", balance: 17_000)
        card.creditLimit = 20_000 // долг = 20000-17000 = 3000
        ctx.insert(card)
        let junction = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        junction.group = FinanceSystemGroups.ensureUngroupedGroup(in: ctx)
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)
        vm.handle(.updateAccountAmount(junction, 8_000)) // новый долг 8000

        #expect(abs(card.balance - 12_000) < 0.01, "balance = limit - newDebt = 20000-8000")
        let txs = try fetchTransactions(ctx)
        #expect(txs.first?.transactionType == .creditDebtAdjustment)
        #expect(abs((txs.first?.amount ?? 0) - (-5_000)) < 0.01, "рост долга на 5000 → tx -5000 (баланс карты падает)")
    }

    @Test("card credit: долг падает 8000→3000 (погашение) → tx +5000")
    func cardCreditDecrease() throws {
        let ctx = try makeContext()
        let card = Card(name: "Кредитка", cardNumber: "2222", bank: .other, cardType: .credit, currency: "RUB", balance: 12_000)
        card.creditLimit = 20_000 // долг = 8000
        ctx.insert(card)
        let junction = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        junction.group = FinanceSystemGroups.ensureUngroupedGroup(in: ctx)
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)
        vm.handle(.updateAccountAmount(junction, 3_000)) // погашение до 3000

        #expect(abs(card.balance - 17_000) < 0.01)
        let txs = try fetchTransactions(ctx)
        #expect(abs((txs.first?.amount ?? 0) - 5_000) < 0.01, "погашение долга на 5000 → tx +5000")
    }

    // MARK: - Credit (продукт)

    @Test("credit продукт: остаток растёт 50000→70000 → tx -20000, isClosed=false")
    func creditProductIncrease() throws {
        let ctx = try makeContext()
        let credit = Credit(name: "Потреб", amount: 100_000, interestRate: 10, monthlyPayment: 5_000, startDate: Date(), termMonths: 24, currency: "RUB")
        credit.remainingAmount = 50_000
        ctx.insert(credit)
        let junction = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
        junction.group = FinanceSystemGroups.ensureUngroupedGroup(in: ctx)
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)
        vm.handle(.updateAccountAmount(junction, 70_000))

        #expect(abs(credit.remainingAmount - 70_000) < 0.01)
        #expect(credit.isClosed == false)
        let txs = try fetchTransactions(ctx)
        #expect(txs.first?.transactionType == .creditDebtAdjustment)
        #expect(abs((txs.first?.amount ?? 0) - (-20_000)) < 0.01)
    }

    @Test("credit продукт: остаток падает до 0 → tx +50000, isClosed=true")
    func creditProductDecreaseToZeroClosesCredit() throws {
        let ctx = try makeContext()
        let credit = Credit(name: "Потреб", amount: 100_000, interestRate: 10, monthlyPayment: 5_000, startDate: Date(), termMonths: 24, currency: "RUB")
        credit.remainingAmount = 50_000
        ctx.insert(credit)
        let junction = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
        junction.group = FinanceSystemGroups.ensureUngroupedGroup(in: ctx)
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)
        vm.handle(.updateAccountAmount(junction, 0))

        #expect(abs(credit.remainingAmount - 0) < 0.01)
        #expect(credit.isClosed == true, "newAmount <= 0 закрывает кредит (as-is)")
        let txs = try fetchTransactions(ctx)
        #expect(abs((txs.first?.amount ?? 0) - 50_000) < 0.01)
    }

    // MARK: - Investment (manual)

    @Test("investment manual: стоимость растёт 40000→55000 → tx +15000, balanceAdjustment")
    func investmentManualIncrease() throws {
        let ctx = try makeContext()
        let investment = Investment(name: "Актив", category: .house, amount: 40_000, currency: "RUB")
        ctx.insert(investment)
        let junction = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        junction.group = FinanceSystemGroups.ensureUngroupedGroup(in: ctx)
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)
        vm.handle(.updateAccountAmount(junction, 55_000))

        #expect(abs(investment.amount - 55_000) < 0.01)
        let txs = try fetchTransactions(ctx)
        #expect(txs.first?.transactionType == .balanceAdjustment)
        #expect(abs((txs.first?.amount ?? 0) - 15_000) < 0.01)
    }

    @Test("investment manual: стоимость падает 40000→22000 → tx -18000")
    func investmentManualDecrease() throws {
        let ctx = try makeContext()
        let investment = Investment(name: "Актив", category: .house, amount: 40_000, currency: "RUB")
        ctx.insert(investment)
        let junction = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        junction.group = FinanceSystemGroups.ensureUngroupedGroup(in: ctx)
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)
        vm.handle(.updateAccountAmount(junction, 22_000))

        #expect(abs(investment.amount - 22_000) < 0.01)
        let txs = try fetchTransactions(ctx)
        #expect(abs((txs.first?.amount ?? 0) - (-18_000)) < 0.01)
    }

    // MARK: - Investment (market, isMarketPriced)

    @Test("investment market: количество растёт 10→15 при unitPrice=100 → amount 1000→1500, tx +500")
    func investmentMarketIncrease() throws {
        let ctx = try makeContext()
        let investment = Investment(name: "Акция", category: .stocks, amount: 1_000, currency: "RUB")
        investment.marketQuantity = 10
        investment.lastKnownUnitPrice = 100
        ctx.insert(investment)
        let junction = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        junction.group = FinanceSystemGroups.ensureUngroupedGroup(in: ctx)
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)
        vm.handle(.updateAccountAmount(junction, 15)) // newAmount = НОВОЕ КОЛИЧЕСТВО, не сумма

        #expect(investment.marketQuantity == 15)
        #expect(abs(investment.amount - 1_500) < 0.01, "amount = quantity * unitPrice = 15*100")
        let txs = try fetchTransactions(ctx)
        #expect(txs.first?.transactionType == .balanceAdjustment)
        #expect(abs((txs.first?.amount ?? 0) - 500) < 0.01, "разница СТОИМОСТИ (1500-1000), не количества (15-10)")
    }

    @Test("investment market: количество падает 10→4 при unitPrice=100 → amount 1000→400, tx -600")
    func investmentMarketDecrease() throws {
        let ctx = try makeContext()
        let investment = Investment(name: "Акция", category: .stocks, amount: 1_000, currency: "RUB")
        investment.marketQuantity = 10
        investment.lastKnownUnitPrice = 100
        ctx.insert(investment)
        let junction = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        junction.group = FinanceSystemGroups.ensureUngroupedGroup(in: ctx)
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)
        vm.handle(.updateAccountAmount(junction, 4))

        #expect(investment.marketQuantity == 4)
        #expect(abs(investment.amount - 400) < 0.01)
        let txs = try fetchTransactions(ctx)
        #expect(abs((txs.first?.amount ?? 0) - (-600)) < 0.01)
    }

    // MARK: - Core parity (adjustBalance) — НЕ утверждаем равенство, фиксируем ФАКТ

    @Test("parity cashLike: adjustBalance(0→5000) на .debitCard создаёт .adjustment с amount=+5000 (не инвертирован)")
    func parityCashLikeAdjustBalanceRawDelta() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        let account = try coreService.createAccount(name: "Core Card", kind: .debitCard, currency: "RUB", openingBalance: 0)

        let event = try coreService.adjustBalance(account: account, to: 5_000)

        #expect(event.type == .adjustment)
        #expect(abs(NSDecimalNumber(decimal: event.amount ?? 0).doubleValue - 5_000) < 0.01, "delta=newValue-current без инверсии по kind — как cardBalanceAdjustment (совпадает знаком)")
    }

    @Test("parity loan: adjustBalance(0→-8000) на .loan создаёт .adjustment с amount=-8000 (СЫРАЯ дельта, БЕЗ инверсии по kind)")
    func parityLoanAdjustBalanceDoesNotInvertSignByKind() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        // .loan хранит ЗНАКОВЫЙ баланс (долг как отрицательное число) — openingBalance=0, затем
        // «переводим долг в 8000» через ЗНАКОВЫЙ newValue = -8000 (net-worth-конвенция, как
        // AccountAdjustBalanceSheet: currentBalance=balanceToday уже знаковый).
        let account = try coreService.createAccount(name: "Core Loan", kind: .loan, currency: "RUB", openingBalance: 0)

        let event = try coreService.adjustBalance(account: account, to: -8_000)

        #expect(event.type == .adjustment)
        #expect(abs(NSDecimalNumber(decimal: event.amount ?? 0).doubleValue - (-8_000)) < 0.01, "сырая delta=-8000-0=-8000 — В ОТЛИЧИЕ от legacy cardCreditIncrease, где долг+8000 создаёт tx -8000 ТОЛЬКО потому что updateAccountAmount вручную инвертирует; core не инвертирует — просто пишет то, что передал вызывающий")
    }
}
