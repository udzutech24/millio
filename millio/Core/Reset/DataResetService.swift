//
//  DataResetService.swift
//  millio
//
//  Created by Codex on 05.03.2026.
//

import Foundation
import SwiftData

enum DataResetPeriodPreset: String, CaseIterable, Identifiable {
    case allTime
    case last30Days
    case last90Days
    case last365Days
    case custom

    var id: String { rawValue }

    var title: String {
        // TODO: localize — используй SmartDataResetLocalization.periodTitle(_:locale:) в UI вместо этого свойства
        switch self {
        case .allTime: return "All time"
        case .last30Days: return "Last 30 days"
        case .last90Days: return "Last 90 days"
        case .last365Days: return "Last 365 days"
        case .custom: return "Custom range"
        }
    }
}

struct DataResetPeriod: Equatable {
    var preset: DataResetPeriodPreset
    var customStartDate: Date
    var customEndDate: Date

    static func allTime(referenceDate: Date = Date()) -> DataResetPeriod {
        DataResetPeriod(
            preset: .allTime,
            customStartDate: referenceDate,
            customEndDate: referenceDate
        )
    }

    func resolvedInterval(calendar: Calendar = .current, referenceDate: Date = Date()) -> DateInterval? {
        let startOfToday = calendar.startOfDay(for: referenceDate)

        switch preset {
        case .allTime:
            return nil
        case .last30Days:
            guard let start = calendar.date(byAdding: .day, value: -29, to: startOfToday),
                  let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
                return nil
            }
            return DateInterval(start: start, end: end)
        case .last90Days:
            guard let start = calendar.date(byAdding: .day, value: -89, to: startOfToday),
                  let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
                return nil
            }
            return DateInterval(start: start, end: end)
        case .last365Days:
            guard let start = calendar.date(byAdding: .day, value: -364, to: startOfToday),
                  let end = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
                return nil
            }
            return DateInterval(start: start, end: end)
        case .custom:
            let start = calendar.startOfDay(for: min(customStartDate, customEndDate))
            let normalizedEnd = calendar.startOfDay(for: max(customStartDate, customEndDate))
            guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: normalizedEnd) else {
                return nil
            }
            return DateInterval(start: start, end: endExclusive)
        }
    }
}

enum DataResetTarget: String, CaseIterable, Identifiable {
    case operations
    case accountOperations
    case zeroAccountsInPeriod
    case cashback
    case accounts
    case categories
    case settings

    var id: String { rawValue }

    var title: String {
        // TODO: localize — используй SmartDataResetLocalization.targetTitle(_:locale:) в UI вместо этого свойства
        switch self {
        case .operations: return "Operations"
        case .accountOperations: return "Account operations"
        case .zeroAccountsInPeriod: return "Zero balances in period"
        case .cashback: return "Cashback"
        case .accounts: return "Accounts"
        case .categories: return "Categories"
        case .settings: return "Settings"
        }
    }
}

struct DataResetRequest: Equatable {
    var period: DataResetPeriod
    var targets: Set<DataResetTarget>

    var isValid: Bool { !targets.isEmpty }
}

struct DataResetEstimate: Equatable {
    var deletedTransactions: Int = 0
    var deletedCashbacks: Int = 0
    var deletedCards: Int = 0
    var deletedCredits: Int = 0
    var deletedInvestments: Int = 0
    var deletedFinanceAccounts: Int = 0
    var deletedFinanceGroups: Int = 0
    var deletedCashflowCustomCategories: Int = 0
    var deletedCashflowSystemOverrides: Int = 0
    var deletedCashbackCustomCategories: Int = 0
    var zeroedCards: Int = 0
    var zeroedCredits: Int = 0
    var zeroedInvestments: Int = 0
    var createdAdjustmentTransactions: Int = 0
    var settingsReset: Bool = false

    var totalChanges: Int {
        deletedTransactions
            + deletedCashbacks
            + deletedCards
            + deletedCredits
            + deletedInvestments
            + deletedFinanceAccounts
            + deletedFinanceGroups
            + deletedCashflowCustomCategories
            + deletedCashflowSystemOverrides
            + deletedCashbackCustomCategories
            + zeroedCards
            + zeroedCredits
            + zeroedInvestments
            + createdAdjustmentTransactions
            + (settingsReset ? 1 : 0)
    }
}

@MainActor
protocol DataResetServiceProtocol {
    func estimate(_ request: DataResetRequest) throws -> DataResetEstimate
    func execute(_ request: DataResetRequest) throws -> DataResetEstimate
}

@MainActor
final class DataResetService: DataResetServiceProtocol {
    private let modelContext: ModelContext
    private let appState: AppState
    private let settingsManager: SettingsManager
    private let defaults: UserDefaults
    private let financeAuditSnapshotStorageKey: String
    private let clearPinCode: () -> Void
    private let disableDailyReminder: () -> Void
    private let publishEvent: (AppEvent) -> Void
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        appState: AppState,
        settingsManager: SettingsManager = .shared,
        defaults: UserDefaults = .standard,
        financeAuditSnapshotStorageKey: String = "finance.balance.audit.snapshot.store",
        clearPinCode: @escaping () -> Void = { AppLockPinStore.shared.clear() },
        disableDailyReminder: @escaping () -> Void = {
            Task { await NotificationManager.shared.scheduleDailyReminder(enabled: false) }
        },
        publishEvent: ((AppEvent) -> Void)? = nil,
        calendar: Calendar = .current
    ) {
        self.modelContext = modelContext
        self.appState = appState
        self.settingsManager = settingsManager
        self.defaults = defaults
        self.financeAuditSnapshotStorageKey = financeAuditSnapshotStorageKey
        self.clearPinCode = clearPinCode
        self.disableDailyReminder = disableDailyReminder
        self.publishEvent = publishEvent ?? { event in
            EventBus.shared.publish(event)
        }
        self.calendar = calendar
    }

    func estimate(_ request: DataResetRequest) throws -> DataResetEstimate {
        guard request.isValid else { return DataResetEstimate() }

        let interval = request.period.resolvedInterval(calendar: calendar)
        var estimate = DataResetEstimate()

        if request.targets.contains(.accounts) {
            let accountEstimate = try estimateAccountsCleanup()
            estimate.deletedCards = accountEstimate.deletedCards
            estimate.deletedCredits = accountEstimate.deletedCredits
            estimate.deletedInvestments = accountEstimate.deletedInvestments
            estimate.deletedFinanceAccounts = accountEstimate.deletedFinanceAccounts
            estimate.deletedFinanceGroups = accountEstimate.deletedFinanceGroups
            estimate.deletedTransactions += accountEstimate.deletedLinkedTransactions
            estimate.deletedCashbacks += accountEstimate.deletedLinkedCashbacks
        }

        if request.targets.contains(.operations) {
            let currentTransactions = try modelContext.fetch(FetchDescriptor<CashflowTransaction>())
            estimate.deletedTransactions += currentTransactions.filter {
                Self.matches(date: $0.transactionDate, in: interval)
            }.count
        }
        if request.targets.contains(.accountOperations) {
            estimate.deletedTransactions += try estimateLinkedTransactions(in: interval)
        }
        if request.targets.contains(.zeroAccountsInPeriod) {
            let zeroingEstimate = try estimateZeroingAccounts()
            estimate.zeroedCards = zeroingEstimate.zeroedCards
            estimate.zeroedCredits = zeroingEstimate.zeroedCredits
            estimate.zeroedInvestments = zeroingEstimate.zeroedInvestments
            estimate.createdAdjustmentTransactions = zeroingEstimate.createdAdjustmentTransactions
        }

        if request.targets.contains(.cashback) {
            let cashbacks = try modelContext.fetch(FetchDescriptor<Cashback>())
            estimate.deletedCashbacks += cashbacks.filter {
                guard let monthDate = Cashback.startOfMonth(for: $0.monthKey, calendar: calendar) else { return true }
                return Self.matches(date: monthDate, in: interval)
            }.count
        }

        if request.targets.contains(.categories) {
            estimate.deletedCashflowCustomCategories = try modelContext.fetch(FetchDescriptor<CashflowCustomCategory>()).count
            estimate.deletedCashflowSystemOverrides = try modelContext.fetch(FetchDescriptor<CashflowSystemCategoryOverride>()).count
            estimate.deletedCashbackCustomCategories = try modelContext.fetch(FetchDescriptor<CashbackCustomCategory>()).count
        }

        if request.targets.contains(.settings) {
            estimate.settingsReset = true
        }

        return estimate
    }

    func execute(_ request: DataResetRequest) throws -> DataResetEstimate {
        guard request.isValid else { return DataResetEstimate() }

        var result = DataResetEstimate()
        let interval = request.period.resolvedInterval(calendar: calendar)

        if request.targets.contains(.accounts) {
            let accountResult = try cleanupAccountsAndDependencies()
            result.deletedCards = accountResult.deletedCards
            result.deletedCredits = accountResult.deletedCredits
            result.deletedInvestments = accountResult.deletedInvestments
            result.deletedFinanceAccounts = accountResult.deletedFinanceAccounts
            result.deletedFinanceGroups = accountResult.deletedFinanceGroups
            result.deletedTransactions += accountResult.deletedLinkedTransactions
            result.deletedCashbacks += accountResult.deletedLinkedCashbacks
        }

        if request.targets.contains(.operations) {
            result.deletedTransactions += try deleteTransactions(in: interval)
        }
        if request.targets.contains(.accountOperations) {
            result.deletedTransactions += try deleteLinkedTransactionsForCurrentAccounts(in: interval)
        }
        if request.targets.contains(.zeroAccountsInPeriod) {
            let zeroingResult = try zeroAccounts(in: interval)
            result.zeroedCards = zeroingResult.zeroedCards
            result.zeroedCredits = zeroingResult.zeroedCredits
            result.zeroedInvestments = zeroingResult.zeroedInvestments
            result.createdAdjustmentTransactions = zeroingResult.createdAdjustmentTransactions
        }

        if request.targets.contains(.cashback) {
            result.deletedCashbacks += try deleteCashbacks(in: interval)
        }

        if request.targets.contains(.categories) {
            let categoriesResult = try resetCategories()
            result.deletedCashflowCustomCategories = categoriesResult.deletedCashflowCustomCategories
            result.deletedCashflowSystemOverrides = categoriesResult.deletedCashflowSystemOverrides
            result.deletedCashbackCustomCategories = categoriesResult.deletedCashbackCustomCategories
        }

        if shouldRebaseAccountHistoryAnchors(request: request, interval: interval) {
            try rebaseAccountHistoryAnchorsToCurrentValues()
        }

        if shouldClearFinanceAuditSnapshotStore(for: request.targets) {
            clearFinanceAuditSnapshotStore()
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }

        if request.targets.contains(.settings) {
            resetAppSettings()
            result.settingsReset = true
        }

        // Оповещаем подписчиков, чтобы экраны перечитали состояние после пакетной очистки.
        publishEvent(FinanceEvent.cardsUpdated)
        publishEvent(FinanceEvent.creditsUpdated)
        publishEvent(FinanceEvent.transactionsUpdated)
        publishEvent(FinanceEvent.auditSnapshotsUpdated)
        publishEvent(BackupEvent.restoreCompleted)

        return result
    }

    private struct AccountCleanupResult {
        var deletedCards: Int = 0
        var deletedCredits: Int = 0
        var deletedInvestments: Int = 0
        var deletedFinanceAccounts: Int = 0
        var deletedFinanceGroups: Int = 0
        var deletedLinkedTransactions: Int = 0
        var deletedLinkedCashbacks: Int = 0
    }

    private struct CategoryResetResult {
        var deletedCashflowCustomCategories: Int = 0
        var deletedCashflowSystemOverrides: Int = 0
        var deletedCashbackCustomCategories: Int = 0
    }

    private struct ZeroingAccountsResult {
        var zeroedCards: Int = 0
        var zeroedCredits: Int = 0
        var zeroedInvestments: Int = 0
        var createdAdjustmentTransactions: Int = 0
    }

    private func estimateAccountsCleanup() throws -> AccountCleanupResult {
        let cards = try modelContext.fetch(FetchDescriptor<Card>())
        let credits = try modelContext.fetch(FetchDescriptor<Credit>())
        let investments = try modelContext.fetch(FetchDescriptor<Investment>())
        let financeAccounts = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        let financeGroups = try modelContext.fetch(FetchDescriptor<FinanceGroup>())
        let transactions = try modelContext.fetch(FetchDescriptor<CashflowTransaction>())
        let cashbacks = try modelContext.fetch(FetchDescriptor<Cashback>())

        let cardIDs = Set(cards.map(\.cardUniqueID))
        let creditIDs = Set(credits.map(\.creditUniqueID))
        let investmentIDs = Set(investments.map(\.investmentUniqueID))

        let linkedTransactions = transactions.filter { transaction in
            Self.isLinkedToAnyAccount(
                transaction: transaction,
                cardIDs: cardIDs,
                creditIDs: creditIDs,
                investmentIDs: investmentIDs
            )
        }.count

        let linkedCashbacks = cashbacks.filter {
            let filteredIDs = $0.cardIDs.filter { id in !cardIDs.contains(id) }
            return filteredIDs.isEmpty && !$0.cardIDs.isEmpty
        }.count

        return AccountCleanupResult(
            deletedCards: cards.count,
            deletedCredits: credits.count,
            deletedInvestments: investments.count,
            deletedFinanceAccounts: financeAccounts.count,
            deletedFinanceGroups: financeGroups.count,
            deletedLinkedTransactions: linkedTransactions,
            deletedLinkedCashbacks: linkedCashbacks
        )
    }

    private func estimateLinkedTransactions(in interval: DateInterval?) throws -> Int {
        let cards = try modelContext.fetch(FetchDescriptor<Card>())
        let credits = try modelContext.fetch(FetchDescriptor<Credit>())
        let investments = try modelContext.fetch(FetchDescriptor<Investment>())
        let transactions = try modelContext.fetch(FetchDescriptor<CashflowTransaction>())

        let cardIDs = Set(cards.map(\.cardUniqueID))
        let creditIDs = Set(credits.map(\.creditUniqueID))
        let investmentIDs = Set(investments.map(\.investmentUniqueID))

        return transactions.filter { transaction in
            Self.matches(date: transaction.transactionDate, in: interval)
                && Self.isLinkedToAnyAccount(
                    transaction: transaction,
                    cardIDs: cardIDs,
                    creditIDs: creditIDs,
                    investmentIDs: investmentIDs
                )
        }.count
    }

    private func estimateZeroingAccounts() throws -> ZeroingAccountsResult {
        let cards = try modelContext.fetch(FetchDescriptor<Card>()).filter { $0.archivedAt == nil }
        let credits = try modelContext.fetch(FetchDescriptor<Credit>()).filter { $0.archivedAt == nil }
        let investments = try modelContext.fetch(FetchDescriptor<Investment>()).filter { $0.archivedAt == nil }

        let zeroedCards = cards.filter { card in
            if card.cardType == .credit, let limit = card.creditLimit {
                return max(0, limit - card.balance) > 0.01
            }
            return abs(card.balance) > 0.01
        }.count

        let zeroedCredits = credits.filter { abs($0.remainingAmount) > 0.01 }.count
        let zeroedInvestments = investments.filter { abs($0.amount) > 0.01 }.count
        let adjustments = (zeroedCards + zeroedCredits + zeroedInvestments) * 2

        return ZeroingAccountsResult(
            zeroedCards: zeroedCards,
            zeroedCredits: zeroedCredits,
            zeroedInvestments: zeroedInvestments,
            createdAdjustmentTransactions: adjustments
        )
    }

    private func cleanupAccountsAndDependencies() throws -> AccountCleanupResult {
        let cards = try modelContext.fetch(FetchDescriptor<Card>())
        let credits = try modelContext.fetch(FetchDescriptor<Credit>())
        let investments = try modelContext.fetch(FetchDescriptor<Investment>())
        let financeAccounts = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        let financeGroups = try modelContext.fetch(FetchDescriptor<FinanceGroup>())

        let cardIDs = Set(cards.map(\.cardUniqueID))
        let creditIDs = Set(credits.map(\.creditUniqueID))
        let investmentIDs = Set(investments.map(\.investmentUniqueID))

        var deletedLinkedTransactions = 0
        let transactions = try modelContext.fetch(FetchDescriptor<CashflowTransaction>())
        for transaction in transactions where Self.isLinkedToAnyAccount(
            transaction: transaction,
            cardIDs: cardIDs,
            creditIDs: creditIDs,
            investmentIDs: investmentIDs
        ) {
            modelContext.delete(transaction)
            deletedLinkedTransactions += 1
        }

        var deletedLinkedCashbacks = 0
        let cashbacks = try modelContext.fetch(FetchDescriptor<Cashback>())
        for cashback in cashbacks {
            let remainingCardIDs = cashback.cardIDs.filter { !cardIDs.contains($0) }
            if remainingCardIDs.isEmpty, !cashback.cardIDs.isEmpty {
                modelContext.delete(cashback)
                deletedLinkedCashbacks += 1
            } else if remainingCardIDs != cashback.cardIDs {
                cashback.cardIDs = remainingCardIDs
                cashback.updatedAt = Date()
            }
        }

        for account in financeAccounts { modelContext.delete(account) }
        for group in financeGroups { modelContext.delete(group) }
        for card in cards { modelContext.delete(card) }
        for credit in credits { modelContext.delete(credit) }
        for investment in investments { modelContext.delete(investment) }

        return AccountCleanupResult(
            deletedCards: cards.count,
            deletedCredits: credits.count,
            deletedInvestments: investments.count,
            deletedFinanceAccounts: financeAccounts.count,
            deletedFinanceGroups: financeGroups.count,
            deletedLinkedTransactions: deletedLinkedTransactions,
            deletedLinkedCashbacks: deletedLinkedCashbacks
        )
    }

    private func deleteTransactions(in interval: DateInterval?) throws -> Int {
        let transactions = try modelContext.fetch(FetchDescriptor<CashflowTransaction>())
        var deleted = 0
        for transaction in transactions where Self.matches(date: transaction.transactionDate, in: interval) {
            modelContext.delete(transaction)
            deleted += 1
        }
        return deleted
    }

    private func deleteLinkedTransactionsForCurrentAccounts(in interval: DateInterval?) throws -> Int {
        let cards = try modelContext.fetch(FetchDescriptor<Card>())
        let credits = try modelContext.fetch(FetchDescriptor<Credit>())
        let investments = try modelContext.fetch(FetchDescriptor<Investment>())
        let transactions = try modelContext.fetch(FetchDescriptor<CashflowTransaction>())

        let cardIDs = Set(cards.map(\.cardUniqueID))
        let creditIDs = Set(credits.map(\.creditUniqueID))
        let investmentIDs = Set(investments.map(\.investmentUniqueID))

        var deleted = 0
        for transaction in transactions where
            Self.matches(date: transaction.transactionDate, in: interval)
                && Self.isLinkedToAnyAccount(
                    transaction: transaction,
                    cardIDs: cardIDs,
                    creditIDs: creditIDs,
                    investmentIDs: investmentIDs
                ) {
            modelContext.delete(transaction)
            deleted += 1
        }

        return deleted
    }

    private func zeroAccounts(in interval: DateInterval?) throws -> ZeroingAccountsResult {
        let anchorDate: Date = {
            if let end = interval?.end {
                return end.addingTimeInterval(-1)
            }
            return Date()
        }()
        let startOfAnchorDay = calendar.startOfDay(for: anchorDate)
        let restoreDate = calendar.date(byAdding: .day, value: 1, to: startOfAnchorDay) ?? anchorDate.addingTimeInterval(86_400)

        var result = ZeroingAccountsResult()

        let cards = try modelContext.fetch(FetchDescriptor<Card>()).filter { $0.archivedAt == nil }
        for card in cards {
            if card.cardType == .credit, let limit = card.creditLimit {
                let oldDebt = max(0, limit - card.balance)
                guard oldDebt > 0.01 else { continue }

                result.zeroedCards += 1

                let toZeroTransaction = CashflowTransaction(
                    transactionType: .creditDebtAdjustment,
                    amount: oldDebt,
                    currency: card.currency,
                    transactionDate: anchorDate,
                    cardID: card.cardUniqueID,
                    note: "Обнуление долга по счету за период (end)"
                )
                toZeroTransaction.exchangeRate = 1.0
                toZeroTransaction.exchangeRateDate = startOfAnchorDay
                toZeroTransaction.exchangeRateCurrency = card.currency
                modelContext.insert(toZeroTransaction)
                result.createdAdjustmentTransactions += 1

                let restoreTransaction = CashflowTransaction(
                    transactionType: .creditDebtAdjustment,
                    amount: -oldDebt,
                    currency: card.currency,
                    transactionDate: restoreDate,
                    cardID: card.cardUniqueID,
                    note: "Восстановление долга по счету после периода (restore)"
                )
                restoreTransaction.exchangeRate = 1.0
                restoreTransaction.exchangeRateDate = calendar.startOfDay(for: restoreDate)
                restoreTransaction.exchangeRateCurrency = card.currency
                modelContext.insert(restoreTransaction)
                result.createdAdjustmentTransactions += 1
            } else {
                let oldBalance = card.balance
                guard abs(oldBalance) > 0.01 else { continue }

                result.zeroedCards += 1

                let toZeroTransaction = CashflowTransaction(
                    transactionType: .cardBalanceAdjustment,
                    amount: -oldBalance,
                    currency: card.currency,
                    transactionDate: anchorDate,
                    cardID: card.cardUniqueID,
                    note: "Обнуление баланса счета за период (end)"
                )
                toZeroTransaction.exchangeRate = 1.0
                toZeroTransaction.exchangeRateDate = startOfAnchorDay
                toZeroTransaction.exchangeRateCurrency = card.currency
                modelContext.insert(toZeroTransaction)
                result.createdAdjustmentTransactions += 1

                let restoreTransaction = CashflowTransaction(
                    transactionType: .cardBalanceAdjustment,
                    amount: oldBalance,
                    currency: card.currency,
                    transactionDate: restoreDate,
                    cardID: card.cardUniqueID,
                    note: "Восстановление баланса счета после периода (restore)"
                )
                restoreTransaction.exchangeRate = 1.0
                restoreTransaction.exchangeRateDate = calendar.startOfDay(for: restoreDate)
                restoreTransaction.exchangeRateCurrency = card.currency
                modelContext.insert(restoreTransaction)
                result.createdAdjustmentTransactions += 1
            }
        }

        let credits = try modelContext.fetch(FetchDescriptor<Credit>()).filter { $0.archivedAt == nil }
        for credit in credits {
            let oldRemaining = credit.remainingAmount
            guard abs(oldRemaining) > 0.01 else { continue }

            result.zeroedCredits += 1

            let toZeroTransaction = CashflowTransaction(
                transactionType: .creditDebtAdjustment,
                amount: oldRemaining,
                currency: credit.currency,
                transactionDate: anchorDate,
                creditID: credit.creditUniqueID,
                note: "Обнуление долга по кредиту за период (end)"
            )
            toZeroTransaction.exchangeRate = 1.0
            toZeroTransaction.exchangeRateDate = startOfAnchorDay
            toZeroTransaction.exchangeRateCurrency = credit.currency
            modelContext.insert(toZeroTransaction)
            result.createdAdjustmentTransactions += 1

            let restoreTransaction = CashflowTransaction(
                transactionType: .creditDebtAdjustment,
                amount: -oldRemaining,
                currency: credit.currency,
                transactionDate: restoreDate,
                creditID: credit.creditUniqueID,
                note: "Восстановление долга по кредиту после периода (restore)"
            )
            restoreTransaction.exchangeRate = 1.0
            restoreTransaction.exchangeRateDate = calendar.startOfDay(for: restoreDate)
            restoreTransaction.exchangeRateCurrency = credit.currency
            modelContext.insert(restoreTransaction)
            result.createdAdjustmentTransactions += 1
        }

        let investments = try modelContext.fetch(FetchDescriptor<Investment>()).filter { $0.archivedAt == nil }
        for investment in investments {
            let oldAmount = investment.amount
            guard abs(oldAmount) > 0.01 else { continue }

            result.zeroedInvestments += 1

            let signedCurrent = investment.investmentType == .positive ? oldAmount : -oldAmount

            let toZeroTransaction = CashflowTransaction(
                transactionType: .balanceAdjustment,
                amount: -signedCurrent,
                currency: investment.currency,
                transactionDate: anchorDate,
                investmentID: investment.investmentUniqueID,
                note: "Обнуление стоимости актива за период (end)"
            )
            toZeroTransaction.exchangeRate = 1.0
            toZeroTransaction.exchangeRateDate = startOfAnchorDay
            toZeroTransaction.exchangeRateCurrency = investment.currency
            modelContext.insert(toZeroTransaction)
            result.createdAdjustmentTransactions += 1

            let restoreTransaction = CashflowTransaction(
                transactionType: .balanceAdjustment,
                amount: signedCurrent,
                currency: investment.currency,
                transactionDate: restoreDate,
                investmentID: investment.investmentUniqueID,
                note: "Восстановление стоимости актива после периода (restore)"
            )
            restoreTransaction.exchangeRate = 1.0
            restoreTransaction.exchangeRateDate = calendar.startOfDay(for: restoreDate)
            restoreTransaction.exchangeRateCurrency = investment.currency
            modelContext.insert(restoreTransaction)
            result.createdAdjustmentTransactions += 1
        }

        return result
    }

    private func deleteCashbacks(in interval: DateInterval?) throws -> Int {
        let cashbacks = try modelContext.fetch(FetchDescriptor<Cashback>())
        var deleted = 0

        for cashback in cashbacks {
            let monthDate = Cashback.startOfMonth(for: cashback.monthKey, calendar: calendar) ?? cashback.createdAt
            guard Self.matches(date: monthDate, in: interval) else { continue }
            modelContext.delete(cashback)
            deleted += 1
        }

        return deleted
    }

    private func resetCategories() throws -> CategoryResetResult {
        let transactions = try modelContext.fetch(FetchDescriptor<CashflowTransaction>())
        for transaction in transactions {
            if let incomeRaw = transaction.incomeCategoryRaw,
               incomeRaw.hasPrefix(CashflowTransaction.customCategoryPrefix) {
                transaction.incomeCategoryRaw = IncomeCategory.other.rawValue
            }
            if let expenseRaw = transaction.expenseCategoryRaw,
               expenseRaw.hasPrefix(CashflowTransaction.customCategoryPrefix) {
                transaction.expenseCategoryRaw = ExpenseCategory.other.rawValue
            }
        }

        let cashflowCustomCategories = try modelContext.fetch(FetchDescriptor<CashflowCustomCategory>())
        for category in cashflowCustomCategories {
            modelContext.delete(category)
        }

        let cashflowOverrides = try modelContext.fetch(FetchDescriptor<CashflowSystemCategoryOverride>())
        for override in cashflowOverrides {
            modelContext.delete(override)
        }

        let cashbackItems = try modelContext.fetch(FetchDescriptor<Cashback>())
        for cashback in cashbackItems where cashback.categoryRaw.hasPrefix(Cashback.customCategoryPrefix) {
            cashback.categoryRaw = CashbackCategory.other.rawValue
            cashback.name = CashbackCategory.other.displayName
            cashback.updatedAt = Date()
        }

        let cashbackCustomCategories = try modelContext.fetch(FetchDescriptor<CashbackCustomCategory>())
        for category in cashbackCustomCategories {
            modelContext.delete(category)
        }

        return CategoryResetResult(
            deletedCashflowCustomCategories: cashflowCustomCategories.count,
            deletedCashflowSystemOverrides: cashflowOverrides.count,
            deletedCashbackCustomCategories: cashbackCustomCategories.count
        )
    }

    private func resetAppSettings() {
        if let avatarPath = settingsManager.profileAvatarFilePath {
            try? FileManager.default.removeItem(atPath: avatarPath)
        }

        settingsManager.resetToDefaults()
        RateSourcePreferenceStore.shared.reset()

        clearPinCode()
        disableDailyReminder()

        appState.selectedLanguage = .system
        appState.primaryCurrencyCode = settingsManager.primaryCurrencyCode
        appState.isBackupEnabled = settingsManager.isBackupEnabled
        appState.isAutoBackupEnabled = settingsManager.isAutoBackupEnabled
        appState.isICloudAvailable = false
        appState.lastBackupDate = nil
        appState.isDailyReminderEnabled = settingsManager.isDailyReminderEnabled
        appState.isAppLockEnabled = settingsManager.isAppLockEnabled
        appState.isBiometricUnlockEnabled = settingsManager.isBiometricUnlockEnabled
        appState.isAppLocked = false
        appState.profileDisplayName = settingsManager.profileDisplayName
        appState.profileAvatarPath = settingsManager.profileAvatarFilePath
    }

    private func shouldRebaseAccountHistoryAnchors(
        request: DataResetRequest,
        interval: DateInterval?
    ) -> Bool {
        guard interval == nil else { return false }
        return request.targets.contains(.operations) || request.targets.contains(.accountOperations)
    }

    private func shouldClearFinanceAuditSnapshotStore(for targets: Set<DataResetTarget>) -> Bool {
        let affectingTargets: Set<DataResetTarget> = [
            .operations,
            .accountOperations,
            .zeroAccountsInPeriod,
            .accounts
        ]
        return !targets.isDisjoint(with: affectingTargets)
    }

    private func rebaseAccountHistoryAnchorsToCurrentValues() throws {
        let cards = try modelContext.fetch(FetchDescriptor<Card>())
        for card in cards {
            card.initialBalance = card.balance
            card.hasInitialBalance = true
        }

        let credits = try modelContext.fetch(FetchDescriptor<Credit>())
        for credit in credits {
            credit.initialRemainingAmount = credit.remainingAmount
            credit.hasInitialRemainingAmount = true
        }

        let investments = try modelContext.fetch(FetchDescriptor<Investment>())
        for investment in investments {
            investment.initialAmount = investment.amount
            investment.hasInitialAmount = true
        }
    }

    private func clearFinanceAuditSnapshotStore() {
        defaults.removeObject(forKey: financeAuditSnapshotStorageKey)
    }

    private static func matches(date: Date, in interval: DateInterval?) -> Bool {
        guard let interval else { return true }
        return interval.contains(date)
    }

    private static func isLinkedToAnyAccount(
        transaction: CashflowTransaction,
        cardIDs: Set<String>,
        creditIDs: Set<String>,
        investmentIDs: Set<String>
    ) -> Bool {
        if let cardID = transaction.cardID, cardIDs.contains(cardID) {
            return true
        }
        if let toCardID = transaction.toCardID, cardIDs.contains(toCardID) {
            return true
        }
        if let creditID = transaction.creditID, creditIDs.contains(creditID) {
            return true
        }
        if let investmentID = transaction.investmentID, investmentIDs.contains(investmentID) {
            return true
        }
        return false
    }
}
