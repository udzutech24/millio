import Foundation
import SwiftData

enum DailySnapshotClosingError: Error {
    case missingLedgerFxRate(amount: Double, from: String, to: String, date: Date)
}

@MainActor
final class DailySnapshotClosingService {
    private static let maxInitialBackfillDays = 370

    private let modelContext: ModelContext
    private let totalsService: FinanceTotalsService
    private let currencyService: CurrencyRateServiceProtocol
    private let baseCurrencyProvider: () -> String

    init(
        modelContext: ModelContext,
        totalsService: FinanceTotalsService,
        currencyService: CurrencyRateServiceProtocol,
        baseCurrencyProvider: @escaping () -> String
    ) {
        self.modelContext = modelContext
        self.totalsService = totalsService
        self.currencyService = currencyService
        self.baseCurrencyProvider = baseCurrencyProvider
    }

    func closeAllPendingDays(now: Date = Date()) async {
        do {
            try await closeAllPendingDaysThrowing(now: now)
        } catch {
            AppLogger.log(.error, category: "Finance", "Daily snapshot closing failed: \(error.localizedDescription)")
        }
    }

    func closeAllPendingDaysThrowing(now: Date = Date()) async throws {
        try DailySnapshotMigrator.migrateIfNeeded(context: modelContext, today: now)
        try await fillPendingFxSnapshots()
        try await closePendingDays(now: now)
    }

    func fillPendingFxSnapshots() async throws {
        let pending = try modelContext.fetch(FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { snapshot in
                snapshot.snapshotState == "pendingFx"
            }
        ))

        var touchedPortfolioKeys = Set<PortfolioKey>()
        for snapshot in pending {
            try await completePendingFx(snapshot)
            touchedPortfolioKeys.insert(PortfolioKey(dateKey: snapshot.dateKey, baseCurrency: snapshot.baseCurrency))
        }
        for key in touchedPortfolioKeys {
            try upsertPortfolioSnapshot(dateKey: key.dateKey, baseCurrency: key.baseCurrency)
        }
        try modelContext.save()
    }

    private func closePendingDays(now: Date) async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return }

        let baseCurrency = normalizedCurrency(baseCurrencyProvider())
        let balances = await totalsService.calculateAllAccountBalances()
        let accountInputs = try closingAccountInputs(
            currentBalances: balances,
            baseCurrency: baseCurrency
        )
        var touchedDateKeys = Set<String>()

        for input in accountInputs {
            let startDay = try nextDayToClose(
                accountID: input.accountID,
                baseCurrency: baseCurrency,
                now: now,
                fallbackDay: yesterday
            )
            guard startDay <= yesterday else { continue }

            var day = startDay
            while day <= yesterday {
                let dateKey = AccountDailySnapshotReader.dateKey(for: day)
                try await closeAccountSnapshotIfNeeded(
                    accountID: input.accountID,
                    accountCurrency: input.accountCurrency,
                    baseCurrency: baseCurrency,
                    fallbackCurrentBalance: input.fallbackCurrentBalance,
                    day: day,
                    dateKey: dateKey
                )
                touchedDateKeys.insert(dateKey)

                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        for dateKey in touchedDateKeys.sorted() {
            try upsertPortfolioSnapshot(dateKey: dateKey, baseCurrency: baseCurrency)
        }

        try modelContext.save()
    }

    private struct ClosingAccountInput {
        let accountID: String
        let accountCurrency: String
        let fallbackCurrentBalance: Double
    }

    private struct PortfolioKey: Hashable {
        let dateKey: String
        let baseCurrency: String
    }

    private struct HistoricalRateResult {
        let rate: Double?
        let provider: String
        let rateDate: Date?
        let snapshotState: DailySnapshotState
    }

    private func closingAccountInputs(
        currentBalances: [String: (value: Double, currency: String)],
        baseCurrency: String
    ) throws -> [ClosingAccountInput] {
        var inputs = currentBalances.map { accountID, balance in
            ClosingAccountInput(
                accountID: accountID,
                accountCurrency: normalizedCurrency(balance.currency),
                fallbackCurrentBalance: balance.value
            )
        }
        var knownAccountIDs = Set(inputs.map(\.accountID))

        let historicalSnapshots = try modelContext.fetch(FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { snapshot in
                snapshot.baseCurrency == baseCurrency
            },
            sortBy: [SortDescriptor(\.dateKey, order: .reverse)]
        ))
        for snapshot in historicalSnapshots where !knownAccountIDs.contains(snapshot.accountID) {
            inputs.append(ClosingAccountInput(
                accountID: snapshot.accountID,
                accountCurrency: normalizedCurrency(snapshot.accountCurrency),
                fallbackCurrentBalance: snapshot.accountBalance
            ))
            knownAccountIDs.insert(snapshot.accountID)
        }

        return inputs.sorted { $0.accountID < $1.accountID }
    }

    private func closeAccountSnapshotIfNeeded(
        accountID: String,
        accountCurrency: String,
        baseCurrency: String,
        fallbackCurrentBalance: Double,
        day: Date,
        dateKey: String
    ) async throws {
        if let existing = try AccountDailySnapshotReader.fetchAccountSnapshot(
            context: modelContext,
            accountID: accountID,
            dateKey: dateKey,
            baseCurrency: baseCurrency
        ) {
            if DailySnapshotState(rawValue: existing.snapshotState)?.isFullyClosed == true {
                return
            }
            if existing.snapshotState == DailySnapshotState.pendingFx.rawValue {
                try await completePendingFx(existing)
                return
            }
        }

        let endBalance = try await endBalance(
            accountID: accountID,
            accountCurrency: accountCurrency,
            fallbackCurrentBalance: fallbackCurrentBalance,
            day: day
        )
        let rateResult = await historicalRate(on: day, from: accountCurrency, to: baseCurrency)
        let state = rateResult.snapshotState
        let fxRate = rateResult.rate ?? 1
        let createdAt = Date()

        modelContext.insert(AccountDailySnapshot(
            accountID: accountID,
            dateKey: dateKey,
            accountBalance: endBalance,
            accountCurrency: accountCurrency,
            baseCurrency: baseCurrency,
            fxRateToBase: fxRate,
            balanceInBaseCurrency: endBalance * fxRate,
            rateProvider: rateResult.provider,
            rateTimestamp: rateResult.rateDate ?? createdAt,
            snapshotState: state,
            timezoneIdentifier: TimeZone.current.identifier,
            closedAt: state.isFullyClosed ? createdAt : nil,
            createdAt: createdAt,
            updatedAt: createdAt
        ))
    }

    private func nextDayToClose(
        accountID: String,
        baseCurrency: String,
        now: Date,
        fallbackDay: Date
    ) throws -> Date {
        let descriptor = FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { snapshot in
                snapshot.accountID == accountID &&
                snapshot.baseCurrency == baseCurrency &&
                (snapshot.snapshotState == "closed" || snapshot.snapshotState == "fallbackClosed")
            },
            sortBy: [SortDescriptor(\.dateKey, order: .reverse)]
        )
        if let latest = try modelContext.fetch(descriptor).first,
           let latestDate = date(from: latest.dateKey),
           let next = Calendar.current.date(byAdding: .day, value: 1, to: latestDate) {
            return next
        }

        return initialBackfillStartDay(accountID: accountID, now: now, fallbackDay: fallbackDay)
    }

    private func upsertPortfolioSnapshot(dateKey: String, baseCurrency: String) throws {
        let existing = try AccountDailySnapshotReader.fetchPortfolioSnapshot(
            context: modelContext,
            dateKey: dateKey,
            baseCurrency: baseCurrency
        )
        if let existing, DailySnapshotState(rawValue: existing.snapshotState)?.isFullyClosed == true { return }

        let accountSnapshots = Array(try AccountDailySnapshotReader
            .latestClosedAccountSnapshotsByAccount(
                context: modelContext,
                dateKey: dateKey,
                baseCurrency: baseCurrency
            )
            .values)
        guard !accountSnapshots.isEmpty else { return }

        let total = accountSnapshots.reduce(0) { $0 + $1.balanceInBaseCurrency }
        let state = portfolioState(from: accountSnapshots)
        let now = Date()
        if let existing {
            existing.totalBalanceInBaseCurrency = total
            existing.snapshotState = state.rawValue
            existing.closedAt = state.isFullyClosed ? now : nil
            existing.updatedAt = now
        } else {
            modelContext.insert(PortfolioDailySnapshot(
                dateKey: dateKey,
                totalBalanceInBaseCurrency: total,
                baseCurrency: baseCurrency,
                snapshotState: state,
                timezoneIdentifier: TimeZone.current.identifier,
                closedAt: state.isFullyClosed ? now : nil,
                createdAt: now,
                updatedAt: now
            ))
        }
    }

    private func portfolioState(from accountSnapshots: [AccountDailySnapshot]) -> DailySnapshotState {
        if accountSnapshots.contains(where: { $0.snapshotState == DailySnapshotState.pendingFx.rawValue }) {
            return .pendingFx
        }
        if accountSnapshots.contains(where: { $0.snapshotState == DailySnapshotState.fallbackClosed.rawValue }) {
            return .fallbackClosed
        }
        return .closed
    }

    private func completePendingFx(_ snapshot: AccountDailySnapshot) async throws {
        guard snapshot.snapshotState == DailySnapshotState.pendingFx.rawValue else { return }
        let result = await historicalRate(on: date(from: snapshot.dateKey) ?? Date(), from: snapshot.accountCurrency, to: snapshot.baseCurrency)
        let now = Date()
        snapshot.fxRateToBase = result.rate ?? 1
        snapshot.balanceInBaseCurrency = snapshot.accountBalance * snapshot.fxRateToBase
        snapshot.rateProvider = result.rate == nil ? "fallback" : result.provider
        snapshot.rateTimestamp = result.rateDate ?? now
        snapshot.snapshotState = result.snapshotState == .pendingFx
            ? DailySnapshotState.fallbackClosed.rawValue
            : result.snapshotState.rawValue
        snapshot.closedAt = now
        snapshot.updatedAt = now
    }

    private func endBalance(
        accountID: String,
        accountCurrency: String,
        fallbackCurrentBalance: Double,
        day: Date
    ) async throws -> Double {
        guard let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: day)) else {
            return fallbackCurrentBalance
        }
        let previousKey = AccountDailySnapshotReader.dateKey(for: previousDay)
        let baseCurrency = normalizedCurrency(baseCurrencyProvider())
        guard let previous = try AccountDailySnapshotReader.fetchAccountSnapshot(
            context: modelContext,
            accountID: accountID,
            dateKey: previousKey,
            baseCurrency: baseCurrency
        ) else {
            return try await initialEndBalance(
                accountID: accountID,
                accountCurrency: accountCurrency,
                fallbackCurrentBalance: fallbackCurrentBalance,
                day: day
            )
        }

        let delta = try await ledgerDelta(accountID: accountID, accountCurrency: accountCurrency, day: day)
        return previous.accountBalance + delta
    }

    private func initialBackfillStartDay(
        accountID: String,
        now: Date,
        fallbackDay: Date
    ) -> Date {
        let calendar = Calendar.current
        let lowerBound = calendar.date(
            byAdding: .day,
            value: -Self.maxInitialBackfillDays,
            to: calendar.startOfDay(for: now)
        ) ?? fallbackDay

        let candidate = earliestKnownAccountDate(accountID: accountID) ?? fallbackDay

        return max(calendar.startOfDay(for: candidate), lowerBound)
    }

    private func earliestKnownAccountDate(accountID: String) -> Date? {
        var dates: [Date] = []
        if let card = card(accountID: accountID) {
            guard card.hasInitialBalance else { return nil }
            dates.append(card.createdAt)
        } else {
            return nil
        }

        dates.append(contentsOf: ledgerTransactionDates(accountID: accountID))
        return dates.min()
    }

    private func initialEndBalance(
        accountID: String,
        accountCurrency: String,
        fallbackCurrentBalance: Double,
        day: Date
    ) async throws -> Double {
        guard let card = card(accountID: accountID), card.hasInitialBalance else {
            return fallbackCurrentBalance
        }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return fallbackCurrentBalance
        }

        var balance = card.initialBalance
        let effectiveStart = min(calendar.startOfDay(for: card.createdAt), start)
        let descriptor = FetchDescriptor<CashflowTransaction>(
            predicate: #Predicate<CashflowTransaction> { transaction in
                transaction.transactionDate >= effectiveStart &&
                transaction.transactionDate < end &&
                transaction.affectsCardBalance
            },
            sortBy: [SortDescriptor(\.transactionDate)]
        )
        let transactions = (try? modelContext.fetch(descriptor)) ?? []
        for transaction in transactions {
            balance += try await transactionDelta(
                for: transaction,
                accountID: accountID,
                accountCurrency: accountCurrency
            )
        }
        return balance
    }

    private func card(accountID: String) -> Card? {
        let descriptor = FetchDescriptor<Card>()
        return ((try? modelContext.fetch(descriptor)) ?? [])
            .first { $0.cardUniqueID == accountID }
    }

    private func ledgerTransactionDates(accountID: String) -> [Date] {
        let descriptor = FetchDescriptor<CashflowTransaction>(
            predicate: #Predicate<CashflowTransaction> { transaction in
                transaction.cardID == accountID || transaction.toCardID == accountID
            }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map(\.transactionDate)
    }

    private func ledgerDelta(accountID: String, accountCurrency: String, day: Date) async throws -> Double {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let descriptor = FetchDescriptor<CashflowTransaction>(
            predicate: #Predicate<CashflowTransaction> { transaction in
                transaction.transactionDate >= start &&
                transaction.transactionDate < end &&
                transaction.affectsCardBalance
            }
        )
        let transactions = (try? modelContext.fetch(descriptor)) ?? []
        var totalDelta: Double = 0
        for transaction in transactions {
            totalDelta += try await transactionDelta(for: transaction, accountID: accountID, accountCurrency: accountCurrency)
        }
        return totalDelta
    }

    private func transactionDelta(for transaction: CashflowTransaction, accountID: String, accountCurrency: String) async throws -> Double {
        let amount = try await convertedAmount(transaction.amount, from: transaction.currency, to: accountCurrency, on: transaction.transactionDate)
        switch transaction.transactionType {
        case .income:
            return transaction.cardID == accountID ? amount : 0
        case .expense:
            return transaction.cardID == accountID ? -amount : 0
        case .transfer:
            if transaction.cardID == accountID {
                return -amount
            }
            if transaction.toCardID == accountID {
                if let rate = transaction.exchangeRate, rate > 0 {
                    return transaction.amount * rate
                }
                return amount
            }
            return 0
        case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            return transaction.cardID == accountID ? amount : 0
        }
    }

    private func convertedAmount(_ amount: Double, from: String, to: String, on date: Date) async throws -> Double {
        let source = normalizedCurrency(from)
        let target = normalizedCurrency(to)
        if source == target { return amount }
        if let rate = await currencyService.getHistoricalRate(on: date, from: source, to: target) {
            return amount * rate
        }
        if let rate = await currencyService.getRate(from: source, to: target) {
            return amount * rate
        }
        throw DailySnapshotClosingError.missingLedgerFxRate(amount: amount, from: source, to: target, date: date)
    }

    private func historicalRate(on date: Date, from: String, to: String) async -> HistoricalRateResult {
        let source = normalizedCurrency(from)
        let target = normalizedCurrency(to)
        if source == target {
            return HistoricalRateResult(
                rate: 1,
                provider: "identity",
                rateDate: Calendar.current.startOfDay(for: date),
                snapshotState: .closed
            )
        }
        if let rate = await currencyService.getHistoricalRate(on: date, from: source, to: target) {
            return HistoricalRateResult(
                rate: rate,
                provider: "historical",
                rateDate: Calendar.current.startOfDay(for: date),
                snapshotState: .closed
            )
        }
        if let rate = await currencyService.getRate(from: source, to: target) {
            return HistoricalRateResult(
                rate: rate,
                provider: "fallback",
                rateDate: Date(),
                snapshotState: .fallbackClosed
            )
        }
        return HistoricalRateResult(
            rate: nil,
            provider: "pending",
            rateDate: nil,
            snapshotState: .pendingFx
        )
    }

    private func date(from dateKey: String) -> Date? {
        AccountDailySnapshotReader.date(from: dateKey)
    }

    private func normalizedCurrency(_ currency: String) -> String {
        let trimmed = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "RUB" : trimmed
    }
}
