import Foundation
import SwiftData
import Testing
@testable import millio

/// Закрытие release-блокера ModelTypeRegistry (progress/accounts-core-rebuild-handoff.md):
/// Account/AccountEvent/AccountGroup/AccountDailySnapshot/HistoricalAssetPrice теперь переживают
/// полный CloudKit backup/restore (export→clear→import).
@Suite(.serialized)
@MainActor
struct AccountsCoreBackupTests {

    private func withRegistry(_ body: () throws -> Void) throws {
        let state = ModelTypeRegistry.shared.captureState()
        FinanceFeatureRegistration.register()
        CardFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        CurrencyFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()
        do { try body() } catch { ModelTypeRegistry.shared.restoreState(state); throw error }
        ModelTypeRegistry.shared.restoreState(state)
    }

    @Test("Round-trip: все 8 kind Account + событие + группа + снапшот + HistoricalAssetPrice переживают export→clear→import")
    func testFullRoundTripAllAccountKinds() throws {
        try withRegistry {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let context = container.mainContext

            let group = AccountGroup(name: "Основные", colorHex: "#FFAA00", displayCurrency: "USD", order: 1)
            context.insert(group)

            var accounts: [Account] = []
            let kinds: [AccountKind] = [.cash, .debitCard, .bankAccount, .deposit, .loan, .debt, .marketInvestment, .manualAsset]
            for (index, kind) in kinds.enumerated() {
                let account = Account(name: "Счёт \(kind.rawValue)", kind: kind, currency: "RUB", order: index)
                account.group = group
                account.note = "заметка \(index)"
                switch kind {
                case .debitCard:
                    account.cardMeta = CardMeta(bank: "Т-Банк", last4: "1234", creditLimit: 150_000.55,
                                                 statementDay: 5, dueDay: 25, minPayment: 5_000.10,
                                                 graceDays: 55, overdraftLimit: 10_000)
                case .deposit:
                    account.depositMeta = DepositMeta(rate: 12.75, capitalization: .monthly,
                                                       termEnd: Date(timeIntervalSince1970: 2_000_000_000),
                                                       payoutDay: 1, allowsTopUp: true, allowsEarlyClose: true,
                                                       earlyClosePenalty: 0.5, remindEnd: true, autoRollover: false)
                case .loan:
                    account.loanMeta = LoanMeta(principal: 500_000.33, rate: 15.5, monthlyPayment: 12_345.67,
                                                 paymentDay: 10, termEnd: Date(timeIntervalSince1970: 2_100_000_000),
                                                 scheduleType: .annuity, insurance: 999.99)
                case .debt:
                    account.debtMeta = DebtMeta(direction: .owedByMe, counterparty: "Сосед",
                                                 dueDate: Date(timeIntervalSince1970: 1_900_000_000), rate: 0)
                case .marketInvestment:
                    account.marketMeta = MarketMeta(symbol: "AAPL", assetClass: .stock)
                case .manualAsset:
                    account.manualAssetMeta = ManualAssetMeta(revalReminderMonths: 12,
                                                               depreciationRatePerYear: 3.25,
                                                               linkedLoanID: UUID())
                default:
                    break
                }
                context.insert(account)
                accounts.append(account)
            }
            try context.save()

            let marketAccount = accounts[6]
            let event = AccountEvent(
                account: marketAccount, date: Date(timeIntervalSince1970: 1_750_000_000),
                type: .buy, quantity: 10.5, unitPrice: 199.99, fxRateToBase: 95.4321,
                categoryID: "invest", note: "покупка акций", sourceTransactionID: "tx-1",
                originalAmount: 2_099.9, originalCurrency: "USD"
            )
            // dayKey фиксируем НЕ сегодняшним числом — проверяем, что импорт не пересчитывает его
            // из date по текущей таймзоне (риск Т5), а восстанавливает как есть из бэкапа.
            event.dayKey = "2025-06-01"
            context.insert(event)

            let snapshot = AccountDailySnapshot(account: marketAccount, dayKey: "2025-06-01",
                                                 balance: 2_099.90, quantity: 10.5, isClosed: false)
            context.insert(snapshot)

            let price = HistoricalAssetPrice(symbol: "aapl", assetClass: .stock, dayKey: "2025-06-01",
                                              price: 199.99, source: "market-backend")
            context.insert(price)
            try context.save()

            let backupData = try DataRepository.exportAllData(from: context)
            let repository = DataRepository(modelContext: context, modelContainer: container)
            try repository.clearAllData()
            #expect(try context.fetch(FetchDescriptor<Account>()).isEmpty)

            try repository.importAllData(backupData)

            let restoredGroups = try context.fetch(FetchDescriptor<AccountGroup>())
            #expect(restoredGroups.count == 1)
            #expect(restoredGroups.first?.name == "Основные")
            #expect(restoredGroups.first?.displayCurrency == "USD")

            let restoredAccounts = try context.fetch(FetchDescriptor<Account>())
            #expect(restoredAccounts.count == kinds.count)
            #expect(Set(restoredAccounts.map(\.kindRaw)) == Set(kinds.map(\.rawValue)))
            for account in restoredAccounts {
                #expect(account.group?.name == "Основные")
            }

            let restoredCard = restoredAccounts.first { $0.kind == .debitCard }
            #expect(restoredCard?.cardMeta?.bank == "Т-Банк")
            #expect(restoredCard?.cardMeta?.creditLimit == 150_000.55)
            #expect(restoredCard?.cardMeta?.overdraftLimit == 10_000)

            let restoredDeposit = restoredAccounts.first { $0.kind == .deposit }
            #expect(restoredDeposit?.depositMeta?.rate == 12.75)
            #expect(restoredDeposit?.depositMeta?.earlyClosePenalty == 0.5)
            #expect(restoredDeposit?.depositMeta?.capitalization == .monthly)

            let restoredLoan = restoredAccounts.first { $0.kind == .loan }
            #expect(restoredLoan?.loanMeta?.principal == 500_000.33)
            #expect(restoredLoan?.loanMeta?.scheduleType == .annuity)

            let restoredDebt = restoredAccounts.first { $0.kind == .debt }
            #expect(restoredDebt?.debtMeta?.direction == .owedByMe)
            #expect(restoredDebt?.debtMeta?.counterparty == "Сосед")

            let restoredMarket = restoredAccounts.first { $0.kind == .marketInvestment }
            #expect(restoredMarket?.marketMeta?.symbol == "AAPL")

            let restoredManual = restoredAccounts.first { $0.kind == .manualAsset }
            #expect(restoredManual?.manualAssetMeta?.depreciationRatePerYear == 3.25)

            let restoredEvents = try context.fetch(FetchDescriptor<AccountEvent>())
            #expect(restoredEvents.count == 1)
            let restoredEvent = try #require(restoredEvents.first)
            #expect(restoredEvent.dayKey == "2025-06-01",
                     "dayKey должен восстановиться из бэкапа, а не пересчитаться из date (риск Т5)")
            #expect(restoredEvent.quantity == 10.5)
            #expect(restoredEvent.unitPrice == 199.99)
            #expect(restoredEvent.fxRateToBase == 95.4321)
            #expect(restoredEvent.account?.kind == .marketInvestment)

            let restoredSnapshots = try context.fetch(FetchDescriptor<AccountDailySnapshot>())
            #expect(restoredSnapshots.count == 1)
            #expect(restoredSnapshots.first?.balance == 2_099.90)
            #expect(restoredSnapshots.first?.account?.kind == .marketInvestment)

            let restoredPrices = try context.fetch(FetchDescriptor<HistoricalAssetPrice>())
            #expect(restoredPrices.count == 1)
            #expect(restoredPrices.first?.symbol == "AAPL")
            #expect(restoredPrices.first?.price == 199.99)
        }
    }

    @Test("Старый бэкап без ядра (core-типы не были зарегистрированы на момент export) восстанавливается без ошибок")
    func testRestoringOldBackupWithoutCoreEntitiesSucceeds() throws {
        // Строим бэкап БЕЗ AccountsCoreFeatureRegistration — имитация бэкапа со старой версии
        // приложения, где ядро счетов ещё не было зарегистрировано в ModelTypeRegistry.
        let stateBeforeExport = ModelTypeRegistry.shared.captureState()
        FinanceFeatureRegistration.register()
        CardFeatureRegistration.register()

        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let group = FinanceGroup(name: "Легаси", colorHex: "#FFFFFF", order: 0)
        context.insert(group)
        try context.save()

        let oldBackupData: Data
        do {
            oldBackupData = try DataRepository.exportAllData(from: context)
        } catch {
            ModelTypeRegistry.shared.restoreState(stateBeforeExport)
            throw error
        }
        ModelTypeRegistry.shared.restoreState(stateBeforeExport)

        // Импортируем этот "старый" бэкап уже на текущей версии — с зарегистрированным ядром.
        let stateForImport = ModelTypeRegistry.shared.captureState()
        FinanceFeatureRegistration.register()
        CardFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()
        defer { ModelTypeRegistry.shared.restoreState(stateForImport) }

        let repository = DataRepository(modelContext: context, modelContainer: container)
        try repository.clearAllData()
        try repository.importAllData(oldBackupData) // не должен бросить исключение

        let accounts = try context.fetch(FetchDescriptor<Account>())
        #expect(accounts.isEmpty, "В старом бэкапе ядра не было — новых записей ядра появиться не должно")
        let groups = try context.fetch(FetchDescriptor<FinanceGroup>())
        #expect(groups.count == 1, "Легаси-данные из старого бэкапа должны восстановиться как обычно")
    }
}
