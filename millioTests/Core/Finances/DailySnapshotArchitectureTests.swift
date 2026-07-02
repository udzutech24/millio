import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct DailySnapshotArchitectureTests {
    private let migrationKey = "daily_snapshot_migration_v1_completed"

    @Test("Мигратор переносит JSON и UserDefaults в fallbackClosed snapshots")
    func migratesLegacyStoresIntoSwiftDataSnapshots() throws {
        try cleanupLegacyStores()
        defer { try? cleanupLegacyStores() }

        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext

        let accountRecord = AccountBalanceHistoryStore.Record(
            dateKey: "2026-06-20",
            amount: 1250,
            currency: "RUB"
        )
        try writeLegacyAccountHistory(["card-1": [accountRecord]])

        let portfolioRecord = DashboardBalanceHistoryStore.Record(
            dateKey: "2026-06-20",
            amount: 1250,
            currency: "RUB"
        )
        let portfolioData = try JSONEncoder().encode([portfolioRecord])
        UserDefaults.standard.set(portfolioData, forKey: "dashboard.balance.history.v1")

        try DailySnapshotMigrator.migrateIfNeeded(
            context: context,
            today: date(year: 2026, month: 6, day: 21)
        )

        let accountSnapshots = try context.fetch(FetchDescriptor<AccountDailySnapshot>())
        let portfolioSnapshots = try context.fetch(FetchDescriptor<PortfolioDailySnapshot>())

        #expect(accountSnapshots.count == 1)
        #expect(accountSnapshots.first?.snapshotState == DailySnapshotState.fallbackClosed.rawValue)
        #expect(accountSnapshots.first?.accountBalance == 1250)
        #expect(portfolioSnapshots.count == 1)
        #expect(portfolioSnapshots.first?.snapshotState == DailySnapshotState.fallbackClosed.rawValue)
        #expect(UserDefaults.standard.bool(forKey: migrationKey))
        #expect(FileManager.default.fileExists(atPath: legacyMigratedURL.path))
        #expect(!FileManager.default.fileExists(atPath: legacyAccountURL.path))
    }

    @Test("Мигратор идемпотентен при частично созданных snapshots")
    func migratorIsIdempotentWithPartiallyImportedSnapshots() throws {
        try cleanupLegacyStores()
        defer { try? cleanupLegacyStores() }

        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext

        let accountRecord = AccountBalanceHistoryStore.Record(
            dateKey: "2026-06-20",
            amount: 1250,
            currency: "RUB"
        )
        try writeLegacyAccountHistory(["card-1": [accountRecord]])

        context.insert(AccountDailySnapshot(
            accountID: "card-1",
            dateKey: "2026-06-20",
            accountBalance: 1250,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 1250,
            rateProvider: "fallback",
            snapshotState: .fallbackClosed,
            closedAt: date(year: 2026, month: 6, day: 20)
        ))
        try context.save()

        try DailySnapshotMigrator.migrateIfNeeded(
            context: context,
            today: date(year: 2026, month: 6, day: 21)
        )

        let snapshots = try context.fetch(FetchDescriptor<AccountDailySnapshot>())
        #expect(snapshots.count == 1)
        #expect(snapshots.first?.accountBalance == 1250)
        #expect(UserDefaults.standard.bool(forKey: migrationKey))
        #expect(FileManager.default.fileExists(atPath: legacyMigratedURL.path))
        #expect(!FileManager.default.fileExists(atPath: legacyAccountURL.path))
    }

    @Test("pendingFx дозаполняет только FX-поля и не меняет баланс")
    func pendingFxCompletionDoesNotMutateAccountBalance() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let snapshot = AccountDailySnapshot(
            accountID: "card-1",
            dateKey: "2026-06-20",
            accountBalance: 200,
            accountCurrency: "USD",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 200,
            rateProvider: "pending",
            snapshotState: .pendingFx,
            closedAt: nil
        )
        context.insert(snapshot)
        try context.save()

        let totals = FinanceTotalsService(
            currencyService: MockSnapshotCurrencyService(rate: 90),
            groupsProvider: { [] },
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [:] },
            creditByIDProvider: { [:] },
            investmentByIDProvider: { [:] }
        )
        let service = DailySnapshotClosingService(
            modelContext: context,
            totalsService: totals,
            currencyService: MockSnapshotCurrencyService(rate: 90),
            baseCurrencyProvider: { "RUB" }
        )

        try await service.fillPendingFxSnapshots()

        let snapshots = try context.fetch(FetchDescriptor<AccountDailySnapshot>())
        #expect(snapshots.count == 1)
        #expect(snapshots[0].accountBalance == 200)
        #expect(snapshots[0].fxRateToBase == 90)
        #expect(snapshots[0].balanceInBaseCurrency == 18_000)
        #expect(snapshots[0].snapshotState == DailySnapshotState.closed.rawValue)
    }

    @Test("pendingFx account completion пересобирает portfolio snapshot")
    func pendingFxCompletionRecomputesPortfolioSnapshot() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(AccountDailySnapshot(
            accountID: "card-1",
            dateKey: "2026-06-20",
            accountBalance: 200,
            accountCurrency: "USD",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 200,
            rateProvider: "pending",
            snapshotState: .pendingFx,
            closedAt: nil
        ))
        context.insert(PortfolioDailySnapshot(
            dateKey: "2026-06-20",
            totalBalanceInBaseCurrency: 200,
            baseCurrency: "RUB",
            snapshotState: .pendingFx,
            closedAt: nil
        ))
        try context.save()

        let totals = FinanceTotalsService(
            currencyService: MockSnapshotCurrencyService(rate: 90),
            groupsProvider: { [] },
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [:] },
            creditByIDProvider: { [:] },
            investmentByIDProvider: { [:] }
        )
        let service = DailySnapshotClosingService(
            modelContext: context,
            totalsService: totals,
            currencyService: MockSnapshotCurrencyService(rate: 90),
            baseCurrencyProvider: { "RUB" }
        )

        try await service.fillPendingFxSnapshots()

        let portfolio = try #require(try context.fetch(FetchDescriptor<PortfolioDailySnapshot>()).first)
        #expect(portfolio.totalBalanceInBaseCurrency == 18_000)
        #expect(portfolio.snapshotState == DailySnapshotState.closed.rawValue)
    }

    @Test("Closing service догоняет счета из snapshot history даже вне активных групп")
    func closingServiceCatchesUpHistoricalSnapshotAccountsOutsideActiveGroups() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        UserDefaults.standard.set(true, forKey: migrationKey)
        defer { UserDefaults.standard.removeObject(forKey: migrationKey) }

        context.insert(AccountDailySnapshot(
            accountID: "archived-card",
            dateKey: "2026-06-18",
            accountBalance: 100,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 100,
            rateProvider: "identity",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 18)
        ))
        context.insert(CashflowTransaction(
            transactionType: .income,
            amount: 50,
            currency: "RUB",
            transactionDate: date(year: 2026, month: 6, day: 19),
            cardID: "archived-card"
        ))
        try context.save()

        let totals = FinanceTotalsService(
            currencyService: MockSnapshotCurrencyService(rate: 1),
            groupsProvider: { [] },
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [:] },
            creditByIDProvider: { [:] },
            investmentByIDProvider: { [:] }
        )
        let service = DailySnapshotClosingService(
            modelContext: context,
            totalsService: totals,
            currencyService: MockSnapshotCurrencyService(rate: 1),
            baseCurrencyProvider: { "RUB" }
        )

        try await service.closeAllPendingDaysThrowing(now: date(year: 2026, month: 6, day: 21))

        let snapshots = try context.fetch(FetchDescriptor<AccountDailySnapshot>(
            sortBy: [SortDescriptor(\.dateKey)]
        ))
        let byDate = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.dateKey, $0.accountBalance) })
        #expect(byDate["2026-06-18"] == 100)
        #expect(byDate["2026-06-19"] == 150)
        #expect(byDate["2026-06-20"] == 150)
    }

    @Test("Closing service догоняет несколько пропущенных дней через ledger delta")
    func closingServiceCatchesUpMissedDaysFromLedgerDelta() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        UserDefaults.standard.set(true, forKey: migrationKey)
        defer { UserDefaults.standard.removeObject(forKey: migrationKey) }

        let card = Card(
            name: "Main",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 130
        )
        card.uniqueID = "card-1"
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        let group = FinanceGroup(name: "Cards")
        group.accounts = [account]

        context.insert(card)
        context.insert(account)
        context.insert(group)
        context.insert(AccountDailySnapshot(
            accountID: card.cardUniqueID,
            dateKey: "2026-06-18",
            accountBalance: 100,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 100,
            rateProvider: "identity",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 18)
        ))
        context.insert(CashflowTransaction(
            transactionType: .income,
            amount: 50,
            currency: "RUB",
            transactionDate: date(year: 2026, month: 6, day: 19),
            cardID: card.cardUniqueID
        ))
        context.insert(CashflowTransaction(
            transactionType: .expense,
            amount: 20,
            currency: "RUB",
            transactionDate: date(year: 2026, month: 6, day: 20),
            cardID: card.cardUniqueID
        ))
        try context.save()

        let totals = FinanceTotalsService(
            currencyService: MockSnapshotCurrencyService(rate: 1),
            groupsProvider: { [group] },
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [card.cardUniqueID: card] },
            creditByIDProvider: { [:] },
            investmentByIDProvider: { [:] }
        )
        let service = DailySnapshotClosingService(
            modelContext: context,
            totalsService: totals,
            currencyService: MockSnapshotCurrencyService(rate: 1),
            baseCurrencyProvider: { "RUB" }
        )

        await service.closeAllPendingDays(now: date(year: 2026, month: 6, day: 21))

        let snapshots = try context.fetch(FetchDescriptor<AccountDailySnapshot>(
            sortBy: [SortDescriptor(\.dateKey)]
        ))
        let byDate = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.dateKey, $0.accountBalance) })
        #expect(byDate["2026-06-18"] == 100)
        #expect(byDate["2026-06-19"] == 150)
        #expect(byDate["2026-06-20"] == 130)

        let portfolio = try context.fetch(FetchDescriptor<PortfolioDailySnapshot>())
        #expect(Set(portfolio.map(\.dateKey)).isSuperset(of: ["2026-06-19", "2026-06-20"]))
    }

    @Test("Closing service при первом запуске создаёт snapshots за предыдущие дни из initial balance и ledger")
    func closingServiceBootstrapsPreviousDaysWhenNoSnapshotsExist() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        UserDefaults.standard.set(true, forKey: migrationKey)
        defer { UserDefaults.standard.removeObject(forKey: migrationKey) }

        let card = Card(
            name: "Main",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 130
        )
        card.uniqueID = "bootstrap-card"
        card.createdAt = date(year: 2026, month: 6, day: 18)
        card.initialBalance = 100
        card.hasInitialBalance = true

        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.createdAt = card.createdAt
        let group = FinanceGroup(name: "Cards")
        account.group = group
        group.accounts = [account]

        context.insert(card)
        context.insert(account)
        context.insert(group)
        context.insert(CashflowTransaction(
            transactionType: .income,
            amount: 50,
            currency: "RUB",
            transactionDate: date(year: 2026, month: 6, day: 19),
            cardID: card.cardUniqueID
        ))
        context.insert(CashflowTransaction(
            transactionType: .expense,
            amount: 20,
            currency: "RUB",
            transactionDate: date(year: 2026, month: 6, day: 20),
            cardID: card.cardUniqueID
        ))
        try context.save()

        let totals = FinanceTotalsService(
            currencyService: MockSnapshotCurrencyService(rate: 1),
            groupsProvider: { [group] },
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [card.cardUniqueID: card] },
            creditByIDProvider: { [:] },
            investmentByIDProvider: { [:] }
        )
        let service = DailySnapshotClosingService(
            modelContext: context,
            totalsService: totals,
            currencyService: MockSnapshotCurrencyService(rate: 1),
            baseCurrencyProvider: { "RUB" }
        )

        try await service.closeAllPendingDaysThrowing(now: date(year: 2026, month: 6, day: 22))

        let snapshots = try context.fetch(FetchDescriptor<AccountDailySnapshot>(
            sortBy: [SortDescriptor(\.dateKey)]
        ))
        let byDate = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.dateKey, $0.accountBalance) })
        #expect(byDate["2026-06-18"] == 100)
        #expect(byDate["2026-06-19"] == 150)
        #expect(byDate["2026-06-20"] == 130)
        #expect(byDate["2026-06-21"] == 130)

        let portfolio = try context.fetch(FetchDescriptor<PortfolioDailySnapshot>(
            sortBy: [SortDescriptor(\.dateKey)]
        ))
        let portfolioByDate = Dictionary(uniqueKeysWithValues: portfolio.map { ($0.dateKey, $0.totalBalanceInBaseCurrency) })
        #expect(portfolioByDate["2026-06-18"] == 100)
        #expect(portfolioByDate["2026-06-19"] == 150)
        #expect(portfolioByDate["2026-06-20"] == 130)
        #expect(portfolioByDate["2026-06-21"] == 130)
    }

    @Test("Closing service без initial balance создаёт только anchor, а не фейковую историю")
    func closingServiceCreatesOnlyAnchorWhenInitialBalanceIsUnknown() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        UserDefaults.standard.set(true, forKey: migrationKey)
        defer { UserDefaults.standard.removeObject(forKey: migrationKey) }

        let card = Card(
            name: "Legacy",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 130
        )
        card.uniqueID = "legacy-card"
        card.createdAt = date(year: 2026, month: 6, day: 18)
        card.hasInitialBalance = false

        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        let group = FinanceGroup(name: "Cards")
        account.group = group
        group.accounts = [account]

        context.insert(card)
        context.insert(account)
        context.insert(group)
        context.insert(CashflowTransaction(
            transactionType: .income,
            amount: 50,
            currency: "RUB",
            transactionDate: date(year: 2026, month: 6, day: 19),
            cardID: card.cardUniqueID
        ))
        try context.save()

        let totals = FinanceTotalsService(
            currencyService: MockSnapshotCurrencyService(rate: 1),
            groupsProvider: { [group] },
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [card.cardUniqueID: card] },
            creditByIDProvider: { [:] },
            investmentByIDProvider: { [:] }
        )
        let service = DailySnapshotClosingService(
            modelContext: context,
            totalsService: totals,
            currencyService: MockSnapshotCurrencyService(rate: 1),
            baseCurrencyProvider: { "RUB" }
        )

        try await service.closeAllPendingDaysThrowing(now: date(year: 2026, month: 6, day: 22))

        let snapshots = try context.fetch(FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { snapshot in
                snapshot.accountID == "legacy-card"
            },
            sortBy: [SortDescriptor(\.dateKey)]
        ))
        #expect(snapshots.map(\.dateKey) == ["2026-06-21"])
        #expect(snapshots.first?.accountBalance == 130)
    }

    @Test("Closing service помечает snapshot как fallbackClosed, если использован текущий FX вместо исторического")
    func closingServiceMarksCurrentFxFallbackAsFallbackClosed() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        UserDefaults.standard.set(true, forKey: migrationKey)
        defer { UserDefaults.standard.removeObject(forKey: migrationKey) }

        let card = Card(
            name: "USD",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "USD",
            balance: 100
        )
        card.uniqueID = "usd-anchor-card"
        card.createdAt = date(year: 2026, month: 6, day: 18)
        card.hasInitialBalance = false

        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        let group = FinanceGroup(name: "Cards")
        account.group = group
        group.accounts = [account]

        context.insert(card)
        context.insert(account)
        context.insert(group)
        try context.save()

        let currencyService = MockSnapshotCurrencyService(currentRate: 90, historicalRate: nil)
        let totals = FinanceTotalsService(
            currencyService: currencyService,
            groupsProvider: { [group] },
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [card.cardUniqueID: card] },
            creditByIDProvider: { [:] },
            investmentByIDProvider: { [:] }
        )
        let service = DailySnapshotClosingService(
            modelContext: context,
            totalsService: totals,
            currencyService: currencyService,
            baseCurrencyProvider: { "RUB" }
        )

        try await service.closeAllPendingDaysThrowing(now: date(year: 2026, month: 6, day: 22))

        let snapshot = try #require(try AccountDailySnapshotReader.fetchAccountSnapshot(
            context: context,
            accountID: "usd-anchor-card",
            dateKey: "2026-06-21",
            baseCurrency: "RUB"
        ))
        #expect(snapshot.accountBalance == 100)
        #expect(snapshot.fxRateToBase == 90)
        #expect(snapshot.balanceInBaseCurrency == 9_000)
        #expect(snapshot.rateProvider == "fallback")
        #expect(snapshot.snapshotState == DailySnapshotState.fallbackClosed.rawValue)
    }

    @Test("Closing service не подставляет raw amount при отсутствующем FX для ledger")
    func closingServiceFailsFastWhenLedgerFxRateIsMissing() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        UserDefaults.standard.set(true, forKey: migrationKey)
        defer { UserDefaults.standard.removeObject(forKey: migrationKey) }

        let card = Card(
            name: "USD",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "USD",
            balance: 100
        )
        card.uniqueID = "usd-card"
        card.createdAt = date(year: 2026, month: 6, day: 18)
        card.initialBalance = 100
        card.hasInitialBalance = true

        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = FinanceGroup(name: "Cards")
        account.group?.accounts = [account]

        context.insert(card)
        context.insert(account.group!)
        context.insert(account)
        context.insert(CashflowTransaction(
            transactionType: .income,
            amount: 50,
            currency: "EUR",
            transactionDate: date(year: 2026, month: 6, day: 19),
            cardID: card.cardUniqueID
        ))
        try context.save()

        let totals = FinanceTotalsService(
            currencyService: MockSnapshotCurrencyService(rate: nil),
            groupsProvider: { [account.group!] },
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [card.cardUniqueID: card] },
            creditByIDProvider: { [:] },
            investmentByIDProvider: { [:] }
        )
        let service = DailySnapshotClosingService(
            modelContext: context,
            totalsService: totals,
            currencyService: MockSnapshotCurrencyService(rate: nil),
            baseCurrencyProvider: { "RUB" }
        )

        await #expect(throws: DailySnapshotClosingError.self) {
            try await service.closeAllPendingDaysThrowing(now: date(year: 2026, month: 6, day: 21))
        }

        let june19 = try AccountDailySnapshotReader.fetchAccountSnapshot(
            context: context,
            accountID: card.cardUniqueID,
            dateKey: "2026-06-19",
            baseCurrency: "RUB"
        )
        #expect(june19 == nil)
    }

    @Test("Closing service корректно закрывает multi-currency transfer без изменения portfolio total")
    func closingServiceHandlesMultiCurrencyTransferLedgerDelta() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        UserDefaults.standard.set(true, forKey: migrationKey)
        defer { UserDefaults.standard.removeObject(forKey: migrationKey) }

        let rubCard = Card(
            name: "RUB",
            cardNumber: "1111",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 100
        )
        rubCard.uniqueID = "rub-card"
        rubCard.createdAt = date(year: 2026, month: 6, day: 18)
        rubCard.initialBalance = 1_000
        rubCard.hasInitialBalance = true

        let usdCard = Card(
            name: "USD",
            cardNumber: "2222",
            bank: .other,
            cardType: .debit,
            currency: "USD",
            balance: 9
        )
        usdCard.uniqueID = "usd-card"
        usdCard.createdAt = date(year: 2026, month: 6, day: 18)
        usdCard.initialBalance = 0
        usdCard.hasInitialBalance = true

        let group = FinanceGroup(name: "Cards")
        let rubAccount = FinanceAccount(accountType: .card, accountID: rubCard.cardUniqueID)
        let usdAccount = FinanceAccount(accountType: .card, accountID: usdCard.cardUniqueID)
        rubAccount.group = group
        usdAccount.group = group
        group.accounts = [rubAccount, usdAccount]

        context.insert(rubCard)
        context.insert(usdCard)
        context.insert(group)
        context.insert(rubAccount)
        context.insert(usdAccount)
        let transfer = CashflowTransaction(
            transactionType: .transfer,
            amount: 900,
            currency: "RUB",
            transactionDate: date(year: 2026, month: 6, day: 19),
            cardID: rubCard.cardUniqueID
        )
        transfer.toCardID = usdCard.cardUniqueID
        transfer.exchangeRate = 0.01
        context.insert(transfer)
        try context.save()

        let totals = FinanceTotalsService(
            currencyService: MockSnapshotCurrencyService(rate: 100),
            groupsProvider: { [group] },
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [rubCard.cardUniqueID: rubCard, usdCard.cardUniqueID: usdCard] },
            creditByIDProvider: { [:] },
            investmentByIDProvider: { [:] }
        )
        let service = DailySnapshotClosingService(
            modelContext: context,
            totalsService: totals,
            currencyService: MockSnapshotCurrencyService(rate: 100),
            baseCurrencyProvider: { "RUB" }
        )

        try await service.closeAllPendingDaysThrowing(now: date(year: 2026, month: 6, day: 21))

        let rubSnapshot = try #require(try AccountDailySnapshotReader.fetchAccountSnapshot(
            context: context,
            accountID: rubCard.cardUniqueID,
            dateKey: "2026-06-19",
            baseCurrency: "RUB"
        ))
        let usdSnapshot = try #require(try AccountDailySnapshotReader.fetchAccountSnapshot(
            context: context,
            accountID: usdCard.cardUniqueID,
            dateKey: "2026-06-19",
            baseCurrency: "RUB"
        ))
        let portfolio = try #require(try AccountDailySnapshotReader.fetchPortfolioSnapshot(
            context: context,
            dateKey: "2026-06-19",
            baseCurrency: "RUB"
        ))

        #expect(rubSnapshot.accountBalance == 100)
        #expect(usdSnapshot.accountBalance == 9)
        #expect(portfolio.totalBalanceInBaseCurrency == 1_000)
    }

    @Test("Closing service не делает initial historical backfill для non-card счетов")
    func closingServiceDoesNotInitialBackfillNonCardAccounts() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        UserDefaults.standard.set(true, forKey: migrationKey)
        defer { UserDefaults.standard.removeObject(forKey: migrationKey) }

        let credit = Credit(
            name: "Loan",
            amount: 100_000,
            interestRate: 0,
            monthlyPayment: 1_000,
            startDate: date(year: 2026, month: 6, day: 18),
            termMonths: 12,
            currency: "RUB",
            bank: .other,
            creditType: .consumer
        )
        credit.uniqueID = "credit-1"
        credit.remainingAmount = 80_000

        let group = FinanceGroup(name: "Credits")
        let account = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
        account.group = group
        group.accounts = [account]

        context.insert(credit)
        context.insert(group)
        context.insert(account)
        try context.save()

        let totals = FinanceTotalsService(
            currencyService: MockSnapshotCurrencyService(rate: 1),
            groupsProvider: { [group] },
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [:] },
            creditByIDProvider: { [credit.creditUniqueID: credit] },
            investmentByIDProvider: { [:] }
        )
        let service = DailySnapshotClosingService(
            modelContext: context,
            totalsService: totals,
            currencyService: MockSnapshotCurrencyService(rate: 1),
            baseCurrencyProvider: { "RUB" }
        )

        try await service.closeAllPendingDaysThrowing(now: date(year: 2026, month: 6, day: 22))

        let snapshots = try context.fetch(FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { snapshot in
                snapshot.accountID == "credit-1"
            },
            sortBy: [SortDescriptor(\.dateKey)]
        ))

        #expect(snapshots.map(\.dateKey) == ["2026-06-21"])
        #expect(snapshots.first?.accountBalance == -80_000)
    }

    @Test("FinanceFeatureRegistration добавляет daily snapshots в backup registry")
    func financeRegistrationIncludesDailySnapshots() {
        let state = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(state) }

        FinanceFeatureRegistration.register()

        let types = ModelTypeRegistry.shared.getExportableTypes()
        #expect(types["AccountDailySnapshot"] != nil)
        #expect(types["PortfolioDailySnapshot"] != nil)
        #expect(ModelTypeRegistry.shared.getImporter(for: "AccountDailySnapshot") != nil)
        #expect(ModelTypeRegistry.shared.getImporter(for: "PortfolioDailySnapshot") != nil)
    }

    @Test("DailySnapshotMigrator использует scope-aware migration key")
    func migratorUsesScopedMigrationKeys() {
        #expect(DailySnapshotMigrator.migrationKey(for: "default") == migrationKey)
        #expect(DailySnapshotMigrator.migrationKey(for: "millio_guest") == "\(migrationKey).millio_guest")
        #expect(DailySnapshotMigrator.migrationKey(for: " millio_user_hash ") == "\(migrationKey).millio_user_hash")
    }

    @Test("Snapshot reader не падает на duplicate dateKey и берёт последний updatedAt")
    func snapshotReaderHandlesDuplicateDateKeys() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(PortfolioDailySnapshot(
            dateKey: "2026-06-20",
            totalBalanceInBaseCurrency: 100,
            baseCurrency: "RUB",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 20),
            updatedAt: date(year: 2026, month: 6, day: 20)
        ))
        context.insert(PortfolioDailySnapshot(
            dateKey: "2026-06-20",
            totalBalanceInBaseCurrency: 150,
            baseCurrency: "RUB",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 20),
            updatedAt: date(year: 2026, month: 6, day: 21)
        ))
        try context.save()

        let points = AccountDailySnapshotReader.portfolioDailyPoints(
            context: context,
            currency: "RUB",
            startDate: date(year: 2026, month: 6, day: 20),
            endDate: date(year: 2026, month: 6, day: 20)
        )

        #expect(points.map(\.amount) == [150])
    }

    @Test("Snapshot reader точечный fetch тоже берёт последний updatedAt")
    func snapshotReaderFetchUsesLatestDuplicate() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(AccountDailySnapshot(
            accountID: "card-1",
            dateKey: "2026-06-20",
            accountBalance: 100,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 100,
            rateProvider: "identity",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 20),
            updatedAt: date(year: 2026, month: 6, day: 20)
        ))
        context.insert(AccountDailySnapshot(
            accountID: "card-1",
            dateKey: "2026-06-20",
            accountBalance: 150,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 150,
            rateProvider: "identity",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 20),
            updatedAt: date(year: 2026, month: 6, day: 21)
        ))
        try context.save()

        let snapshot = try #require(try AccountDailySnapshotReader.fetchAccountSnapshot(
            context: context,
            accountID: "card-1",
            dateKey: "2026-06-20",
            baseCurrency: "RUB"
        ))

        #expect(snapshot.accountBalance == 150)
    }

    @Test("Snapshot reader агрегирует account snapshots и берёт latest updatedAt")
    func snapshotReaderAggregatesAccountSnapshotsWithLatestDuplicate() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(AccountDailySnapshot(
            accountID: "card-1",
            dateKey: "2026-06-20",
            accountBalance: 100,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 100,
            rateProvider: "identity",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 20),
            updatedAt: date(year: 2026, month: 6, day: 20)
        ))
        context.insert(AccountDailySnapshot(
            accountID: "card-1",
            dateKey: "2026-06-20",
            accountBalance: 150,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 150,
            rateProvider: "identity",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 20),
            updatedAt: date(year: 2026, month: 6, day: 21)
        ))
        context.insert(AccountDailySnapshot(
            accountID: "card-2",
            dateKey: "2026-06-20",
            accountBalance: 50,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 50,
            rateProvider: "identity",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 20),
            updatedAt: date(year: 2026, month: 6, day: 20)
        ))
        try context.save()

        let points = AccountDailySnapshotReader.accountPortfolioDailyPoints(
            context: context,
            accountIDs: ["card-1", "card-2"],
            baseCurrency: "RUB",
            startDate: date(year: 2026, month: 6, day: 20),
            endDate: date(year: 2026, month: 6, day: 20)
        )

        #expect(points.map(\.amount) == [200])
    }

    @Test("Snapshot reader считает pendingFx gap, а не суммой")
    func snapshotReaderTreatsPendingFxAsGap() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(AccountDailySnapshot(
            accountID: "card-1",
            dateKey: "2026-06-20",
            accountBalance: 100,
            accountCurrency: "USD",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 100,
            rateProvider: "pending",
            snapshotState: .pendingFx,
            closedAt: nil
        ))
        try context.save()

        let points = AccountDailySnapshotReader.accountPortfolioDailyPoints(
            context: context,
            accountIDs: ["card-1"],
            baseCurrency: "RUB",
            startDate: date(year: 2026, month: 6, day: 20),
            endDate: date(year: 2026, month: 6, day: 20)
        )

        #expect(points.isEmpty)
    }

    @Test("Snapshot reader не требует snapshot до known window счёта")
    func snapshotReaderDoesNotRequireAccountBeforeKnownWindow() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext

        context.insert(AccountDailySnapshot(
            accountID: "card-1",
            dateKey: "2026-06-20",
            accountBalance: 100,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 100,
            rateProvider: "identity",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 20)
        ))
        context.insert(AccountDailySnapshot(
            accountID: "card-1",
            dateKey: "2026-06-21",
            accountBalance: 110,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 110,
            rateProvider: "identity",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 21)
        ))
        context.insert(AccountDailySnapshot(
            accountID: "card-2",
            dateKey: "2026-06-21",
            accountBalance: 20,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 20,
            rateProvider: "identity",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 21)
        ))
        try context.save()

        let points = AccountDailySnapshotReader.accountPortfolioDailyPoints(
            context: context,
            accountIDs: ["card-1", "card-2"],
            baseCurrency: "RUB",
            startDate: date(year: 2026, month: 6, day: 20),
            endDate: date(year: 2026, month: 6, day: 21),
            requiredAccountIDsByDateKey: { key, _ in
                key == "2026-06-20" ? ["card-1"] : ["card-1", "card-2"]
            }
        )

        #expect(points.map(\.amount) == [100, 130])
    }

    @Test("Portfolio checksum пересобирается из latest closed account snapshots")
    func portfolioChecksumUsesLatestAccountSnapshotPerAccount() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(AccountDailySnapshot(
            accountID: "card-1",
            dateKey: "2026-06-20",
            accountBalance: 100,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 100,
            rateProvider: "identity",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 20),
            updatedAt: date(year: 2026, month: 6, day: 20)
        ))
        context.insert(AccountDailySnapshot(
            accountID: "card-1",
            dateKey: "2026-06-20",
            accountBalance: 150,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 150,
            rateProvider: "pending",
            snapshotState: .pendingFx,
            closedAt: nil,
            updatedAt: date(year: 2026, month: 6, day: 21)
        ))
        context.insert(AccountDailySnapshot(
            accountID: "card-2",
            dateKey: "2026-06-20",
            accountBalance: 50,
            accountCurrency: "RUB",
            baseCurrency: "RUB",
            fxRateToBase: 1,
            balanceInBaseCurrency: 50,
            rateProvider: "identity",
            snapshotState: .closed,
            closedAt: date(year: 2026, month: 6, day: 20)
        ))
        context.insert(PortfolioDailySnapshot(
            dateKey: "2026-06-20",
            totalBalanceInBaseCurrency: 999,
            baseCurrency: "RUB",
            snapshotState: .pendingFx,
            closedAt: nil
        ))
        try context.save()

        let totals = FinanceTotalsService(
            currencyService: MockSnapshotCurrencyService(rate: 1),
            groupsProvider: { [] },
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [:] },
            creditByIDProvider: { [:] },
            investmentByIDProvider: { [:] }
        )
        let service = DailySnapshotClosingService(
            modelContext: context,
            totalsService: totals,
            currencyService: MockSnapshotCurrencyService(rate: 1),
            baseCurrencyProvider: { "RUB" }
        )

        try await service.fillPendingFxSnapshots()

        let portfolio = try #require(try AccountDailySnapshotReader.fetchPortfolioSnapshot(
            context: context,
            dateKey: "2026-06-20",
            baseCurrency: "RUB"
        ))
        #expect(portfolio.totalBalanceInBaseCurrency == 200)
        #expect(portfolio.snapshotState == DailySnapshotState.closed.rawValue)
    }

    @Test("Snapshot reader не сжимает внутренние gaps")
    func snapshotReaderContiguousAmountsDoNotCompactInternalGaps() {
        #expect(AccountDailySnapshotReader.contiguousKnownAmounts(from: [nil, 100, 120, nil]) == [100, 120])
        #expect(AccountDailySnapshotReader.contiguousKnownAmounts(from: [nil, 100, nil, 120, nil]).isEmpty)
    }

    private func writeLegacyAccountHistory(_ storage: AccountBalanceHistoryStore.Storage) throws {
        try FileManager.default.createDirectory(
            at: legacyAccountURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(storage)
        try data.write(to: legacyAccountURL, options: .atomic)
    }

    private func cleanupLegacyStores() throws {
        UserDefaults.standard.removeObject(forKey: migrationKey)
        UserDefaults.standard.removeObject(forKey: "dashboard.balance.history.v1")
        try? FileManager.default.removeItem(at: legacyAccountURL)
        try? FileManager.default.removeItem(at: legacyMigratedURL)
    }

    private var legacyAccountURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("account_balance_history_v1.json")
    }

    private var legacyMigratedURL: URL {
        legacyAccountURL.deletingPathExtension().appendingPathExtension("migrated")
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

@MainActor
private final class MockSnapshotCurrencyService: CurrencyRateServiceProtocol {
    let currentRate: Double?
    let historicalRate: Double?

    init(rate: Double?) {
        self.currentRate = rate
        self.historicalRate = rate
    }

    init(currentRate: Double?, historicalRate: Double?) {
        self.currentRate = currentRate
        self.historicalRate = historicalRate
    }

    func getRate(from: String, to: String) async -> Double? {
        from == to ? 1 : currentRate
    }

    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? {
        from == to ? 1 : historicalRate
    }

    func convert(amount: Double, from: String, to: String) async -> Double? {
        guard let rate = await getRate(from: from, to: to) else { return nil }
        return amount * rate
    }

    func forceRefreshRates() async {}
}
