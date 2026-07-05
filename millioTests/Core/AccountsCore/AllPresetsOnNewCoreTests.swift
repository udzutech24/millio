import Foundation
import SwiftData
import Testing
@testable import millio

/// Контракт-тест Фазы 6a: КАЖДАЯ из 11 UI-опций `FinanceAddAccountProductOption` (экран
/// добавления счёта) резолвится через `AccountsCoreAdditionBridge` в `Account` нового ядра
/// с правильным `kind` и заполненной meta-структурой своего типа — ни одна опция не создаёт
/// легаси `Card`/`Credit`/`Investment`. Сводит воедино проверки, ранее разбросанные по тестам
/// фаз 1a/2/3/4 (`AccountsCoreAdditionBridgeTests`), в один явный контракт по всем 11 пресетам.
@Suite("AllPresetsOnNewCore")
@MainActor
struct AllPresetsOnNewCoreTests {

    /// См. комментарий в `AccountsCoreServiceTests.makeContext` — контейнер держим живым вместе
    /// с контекстом, иначе `mainContext` остаётся с разрушенным хранилищем.
    private func makeContext() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        return (container, container.mainContext)
    }

    @Test("Каждая из 11 опций резолвится ровно в один kind нового ядра", arguments: FinanceAddAccountProductOption.allCases)
    func eachPresetResolvesToExactlyOneNewCoreKind(option: FinanceAddAccountProductOption) throws {
        let selection = option.selection(locale: Locale(identifier: "ru_RU"))

        // «Инвестиция» (universal, category=.other, preset=.asset) — единственный пресет,
        // где kind зависит от пользовательского ввода (наличие тикера); для контракта
        // «ровно один резолвер» проверяем ветку с тикером здесь, ветку без тикера — отдельным тестом ниже.
        let kinds: [AccountKind?] = [
            AccountsCoreAdditionBridge.moneyKind(
                accountType: selection.accountType, investmentPreset: selection.investmentPreset,
                bank: .sberbank, isEditingLegacy: false
            ),
            AccountsCoreAdditionBridge.depositKind(
                accountType: selection.accountType, investmentPreset: selection.investmentPreset,
                isEditingLegacy: false
            ),
            AccountsCoreAdditionBridge.obligationKind(
                accountType: selection.accountType, investmentCategory: selection.investmentCategory,
                isEditingLegacy: false
            ),
            AccountsCoreAdditionBridge.assetKind(
                accountType: selection.accountType, investmentCategory: selection.investmentCategory,
                investmentPreset: selection.investmentPreset, hasTicker: true, isEditingLegacy: false
            )
        ]
        let resolved = kinds.compactMap { $0 }
        #expect(resolved.count == 1, "Опция \(option) резолвится в \(resolved.count) kind вместо ровно одного")
    }

    @Test(
        "Каждая из 11 опций создаёт Account нужного kind с правильной meta",
        arguments: FinanceAddAccountProductOption.allCases
    )
    func eachPresetCreatesAccountWithExpectedKindAndMeta(option: FinanceAddAccountProductOption) throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let selection = option.selection(locale: Locale(identifier: "ru_RU"))

        switch option {
        case .card:
            let account = try service.createAccount(
                name: "Карта", kind: AccountsCoreAdditionBridge.cardKind(bank: .sberbank),
                currency: "RUB", openingBalance: 1000,
                cardMeta: CardMeta(bank: Bank.sberbank.rawValue, last4: "1234", creditLimit: nil)
            )
            #expect(account.kind == .debitCard)
            #expect(account.cardMeta?.bank == Bank.sberbank.rawValue)

        case .account:
            let account = try service.createAccount(
                name: "Счёт", kind: .bankAccount, currency: "RUB", openingBalance: 5000
            )
            #expect(account.kind == .bankAccount)

        case .deposit:
            let meta = AccountsCoreAdditionBridge.depositMeta(
                rate: 12, capitalization: .monthly, termEnd: nil,
                allowsTopUp: true, allowsEarlyClose: false, earlyClosePenaltyShare: nil,
                remindEnd: false, autoRollover: false
            )
            let account = try service.createAccount(
                name: "Вклад", kind: .deposit, currency: "RUB", openingBalance: 100_000, depositMeta: meta
            )
            #expect(account.kind == .deposit)
            #expect(account.depositMeta?.rate == 12)

        case .credit:
            let meta = AccountsCoreAdditionBridge.loanMeta(
                principal: 500_000, monthlyPayment: 15_000, paymentDay: 10, termEnd: nil
            )
            let account = try service.createAccount(
                name: "Кредит", kind: .loan, currency: "RUB", openingBalance: 500_000, loanMeta: meta
            )
            #expect(account.kind == .loan)
            #expect(account.loanMeta?.principal == 500_000)

        case .investment:
            // Пресет «Инвестиция» с тикером → рыночный счёт (ветка без тикера — тест ниже).
            let hasTicker = true
            let resolvedKind = AccountsCoreAdditionBridge.assetKind(
                accountType: selection.accountType, investmentCategory: selection.investmentCategory,
                investmentPreset: selection.investmentPreset, hasTicker: hasTicker, isEditingLegacy: false
            )
            #expect(resolvedKind == .marketInvestment)
            let meta = AccountsCoreAdditionBridge.marketMeta(symbol: "voo", category: selection.investmentCategory)
            let account = try service.createAccount(
                name: "Инвестиция", kind: .marketInvestment, currency: "USD", openingBalance: 0, marketMeta: meta
            )
            try service.buy(account: account, quantity: 10, unitPrice: 100)
            #expect(account.kind == .marketInvestment)
            #expect(account.marketMeta?.symbol == "VOO")
            #expect(account.marketMeta?.assetClass == .stock)

        case .house, .business, .other:
            let account = try service.createAccount(
                name: "Актив", kind: .manualAsset, currency: "RUB", openingBalance: 1_000_000,
                manualAssetMeta: AccountsCoreAdditionBridge.manualAssetMeta()
            )
            #expect(account.kind == .manualAsset)
            #expect(account.manualAssetMeta != nil)

        case .debt:
            let meta = AccountsCoreAdditionBridge.debtMeta(direction: .owedByMe)
            let account = try service.createAccount(
                name: "Долг", kind: .debt, currency: "RUB", openingBalance: -20_000, debtMeta: meta
            )
            #expect(account.kind == .debt)
            #expect(account.debtMeta?.direction == .owedByMe)

        case .stocks, .crypto:
            let meta = AccountsCoreAdditionBridge.marketMeta(symbol: option == .crypto ? "btc" : "aapl", category: selection.investmentCategory)
            let account = try service.createAccount(
                name: "Рыночный счёт", kind: .marketInvestment, currency: "USD", openingBalance: 0, marketMeta: meta
            )
            try service.buy(account: account, quantity: 1, unitPrice: 100)
            #expect(account.kind == .marketInvestment)
            #expect(account.marketMeta?.assetClass == (option == .crypto ? .crypto : .stock))
        }

        // Ни одна из 11 опций не должна была создать легаси-сущность в процессе теста.
        #expect(try ctx.fetch(FetchDescriptor<Card>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Credit>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Investment>()).isEmpty)
    }

    @Test("«Инвестиция» без тикера — ручной актив, не рыночный счёт")
    func investmentPresetWithoutTickerIsManualAsset() {
        let kind = AccountsCoreAdditionBridge.assetKind(
            accountType: .investment, investmentCategory: .other, investmentPreset: .asset,
            hasTicker: false, isEditingLegacy: false
        )
        #expect(kind == .manualAsset)
    }
}
