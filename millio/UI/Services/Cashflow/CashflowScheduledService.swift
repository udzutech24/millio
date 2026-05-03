//
//  CashflowScheduledService.swift
//  millio
//
//  Создан в рамках Phase 7 декомпозиции CashflowViewModel.
//  Отвечает за работу с запланированными и повторяющимися транзакциями:
//  вычисление вхождений, генерацию recurring-транзакций, автопримение due-плановых.
//

import Foundation
import SwiftData

// MARK: - CashflowScheduledService

@MainActor
final class CashflowScheduledService {

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let defaults: UserDefaults
    private let now: () -> Date

    /// Провайдер текущего снапшота транзакций из state
    private let transactionsProvider: () -> [CashflowTransaction]

    /// Колбэк: перезагрузить снапшот транзакций в VM
    private let onTransactionsMutated: () -> Void

    /// Колбэк: разрешить exchange-инфо для транзакции
    private let onResolveExchangeInfo: (CashflowTransaction) async -> CashflowExchangeInfo

    /// Колбэк: применить изменение баланса карты для сгенерированной recurring-транзакции
    private let onApplyRecurringToCard: (CashflowTransaction) async -> Void

    /// Колбэк: применить balance-эффект для due-плановой транзакции
    private let onApplyDuePlannedEffect: (CashflowTransaction) async throws -> Void

    // MARK: - State

    private var isRecurringGenerationInProgress = false
    private var isDueAutoApplyInProgress = false

    private let dueAutoApplyCheckpointKey = "cashflow_due_auto_apply_checkpoint_v1"

    // MARK: - Init

    init(
        modelContext: ModelContext,
        defaults: UserDefaults,
        now: @escaping () -> Date,
        transactionsProvider: @escaping () -> [CashflowTransaction],
        onTransactionsMutated: @escaping () -> Void,
        onResolveExchangeInfo: @escaping (CashflowTransaction) async -> CashflowExchangeInfo,
        onApplyRecurringToCard: @escaping (CashflowTransaction) async -> Void,
        onApplyDuePlannedEffect: @escaping (CashflowTransaction) async throws -> Void
    ) {
        self.modelContext = modelContext
        self.defaults = defaults
        self.now = now
        self.transactionsProvider = transactionsProvider
        self.onTransactionsMutated = onTransactionsMutated
        self.onResolveExchangeInfo = onResolveExchangeInfo
        self.onApplyRecurringToCard = onApplyRecurringToCard
        self.onApplyDuePlannedEffect = onApplyDuePlannedEffect
    }

    // MARK: - Public: Queries

    /// Повторяющиеся шаблоны указанного вида, отсортированные по следующей дате вхождения.
    func recurringTemplates(
        for kind: CashflowCategoryKind,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowTransaction] {
        let baseline = referenceDate ?? now()
        let targetType = transactionType(for: kind)

        return transactionsProvider()
            .filter { $0.transactionType == targetType && $0.isRecurringTemplate }
            .sorted { lhs, rhs in
                let leftDate = nextOccurrenceDate(for: lhs, relativeTo: baseline) ?? lhs.transactionDate
                let rightDate = nextOccurrenceDate(for: rhs, relativeTo: baseline) ?? rhs.transactionDate
                if leftDate == rightDate { return lhs.createdAt < rhs.createdAt }
                return leftDate < rightDate
            }
    }

    /// Разовые запланированные транзакции (после baseline), без recurrence.
    func plannedOneTimeTransactions(
        for kind: CashflowCategoryKind,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowTransaction] {
        let baseline = referenceDate ?? now()
        let targetType = transactionType(for: kind)

        return transactionsProvider()
            .filter { transaction in
                guard transaction.transactionType == targetType else { return false }
                guard transaction.recurrenceRule == .none else { return false }
                return transaction.transactionDate > baseline
            }
            .sorted { $0.transactionDate < $1.transactionDate }
    }

    /// Все запланированные записи для planner-экрана: recurring + разовые после baseline.
    func scheduledPlannerEntries(
        for kind: CashflowCategoryKind,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowScheduledEntry] {
        let baseline = Calendar.current.startOfDay(for: referenceDate ?? now())
        let targetType = transactionType(for: kind)

        return transactionsProvider()
            .compactMap { transaction -> CashflowScheduledEntry? in
                guard transaction.transactionType == targetType else { return nil }

                if transaction.isRecurringTemplate,
                   let nextDate = nextOccurrenceDate(for: transaction, relativeTo: baseline) {
                    return CashflowScheduledEntry(
                        transaction: transaction,
                        scheduledDate: nextDate,
                        kind: .recurringMonthly
                    )
                }

                guard transaction.recurrenceRule == .none, transaction.transactionDate > baseline else {
                    return nil
                }
                return CashflowScheduledEntry(
                    transaction: transaction,
                    scheduledDate: transaction.transactionDate,
                    kind: .oneTimePlanned
                )
            }
            .sorted(by: scheduledEntrySort)
    }

    /// Все запланированные записи для calendar-экрана: recurring + разовые в указанном месяце.
    func scheduledCalendarEntries(
        for kind: CashflowCategoryKind,
        month: Date,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowScheduledEntry] {
        let calendar = Calendar.current
        let baseline = calendar.startOfDay(for: referenceDate ?? now())
        let targetType = transactionType(for: kind)
        let monthStart = Self.monthStart(for: month, calendar: calendar)

        return transactionsProvider()
            .compactMap { transaction -> CashflowScheduledEntry? in
                guard transaction.transactionType == targetType else { return nil }

                if transaction.isRecurringTemplate {
                    let rangeStart = max(baseline, monthStart)
                    guard let scheduledDate = nextOccurrenceDate(for: transaction, relativeTo: rangeStart) else {
                        return nil
                    }
                    guard calendar.isDate(scheduledDate, equalTo: monthStart, toGranularity: .month) else {
                        return nil
                    }
                    guard scheduledDate >= baseline else { return nil }
                    return CashflowScheduledEntry(
                        transaction: transaction,
                        scheduledDate: scheduledDate,
                        kind: .recurringMonthly
                    )
                }

                guard transaction.recurrenceRule == .none else { return nil }
                guard calendar.isDate(transaction.transactionDate, equalTo: monthStart, toGranularity: .month) else {
                    return nil
                }
                guard transaction.transactionDate > baseline else { return nil }
                return CashflowScheduledEntry(
                    transaction: transaction,
                    scheduledDate: transaction.transactionDate,
                    kind: .oneTimePlanned
                )
            }
            .sorted(by: scheduledEntrySort)
    }

    /// Следующая дата вхождения для recurring-шаблона относительно referenceDate.
    func nextOccurrenceDate(
        for template: CashflowTransaction,
        relativeTo referenceDate: Date? = nil
    ) -> Date? {
        guard template.isRecurringTemplate else { return nil }

        let calendar = Calendar.current
        let baseline = calendar.startOfDay(for: referenceDate ?? now())
        let templateDate = calendar.startOfDay(for: template.transactionDate)
        var occurrenceIndex = 0

        while let candidate = Self.recurrenceOccurrenceDate(
            templateDate: templateDate,
            rule: template.recurrenceRule,
            weekdays: template.recurrenceWeekdays,
            occurrenceIndex: occurrenceIndex,
            calendar: calendar
        ) {
            if candidate >= baseline { return candidate }
            occurrenceIndex += 1
        }
        return nil
    }

    // MARK: - Public: Scheduling

    /// Запустить фоновую генерацию recurring-транзакций (с guard от дублирования).
    func scheduleRecurringGeneration() {
        guard !isRecurringGenerationInProgress else { return }
        isRecurringGenerationInProgress = true

        Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRecurringGenerationInProgress = false }

            let didGenerate = await self.generateRecurringTransactionsIfNeeded()
            if didGenerate {
                self.onTransactionsMutated()
            }
        }
    }

    /// Запустить фоновое автоприменение due-плановых транзакций (с guard от дублирования).
    func scheduleDueAutoApplyIfNeeded() {
        guard !isDueAutoApplyInProgress else { return }
        isDueAutoApplyInProgress = true

        Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isDueAutoApplyInProgress = false }

            let didApply = await self.applyDuePlannedTransactionsIfNeeded()
            if didApply {
                self.onTransactionsMutated()
            }
        }
    }

    // MARK: - Private: Core Generation

    @discardableResult
    func generateRecurringTransactionsIfNeeded() async -> Bool {
        let descriptor = FetchDescriptor<CashflowTransaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .forward)]
        )
        guard var allTransactions = try? modelContext.fetch(descriptor),
              !allTransactions.isEmpty else {
            return false
        }

        let templates = allTransactions.filter(\.isRecurringTemplate)
        guard !templates.isEmpty else { return false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())

        var didInsert = false
        let seriesKey = { (transaction: CashflowTransaction) -> String? in
            guard let recurrenceSeriesID = transaction.recurrenceSeriesID else { return nil }
            return "\(recurrenceSeriesID)|\(transaction.transactionTypeRaw)"
        }

        for template in templates {
            guard let templateSeriesID = template.recurrenceSeriesID,
                  template.transactionType == .income || template.transactionType == .expense else {
                continue
            }
            guard template.recurrenceRule != .none else { continue }

            let templateDate = calendar.startOfDay(for: template.transactionDate)
            guard templateDate < today else { continue }
            let expectedSeriesKey = "\(templateSeriesID)|\(template.transactionTypeRaw)"
            var occurrenceIndex = 1

            while let expectedDate = Self.recurrenceOccurrenceDate(
                templateDate: templateDate,
                rule: template.recurrenceRule,
                weekdays: template.recurrenceWeekdays,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            ) {
                guard expectedDate > templateDate else {
                    occurrenceIndex += 1
                    continue
                }
                if expectedDate > today { break }

                let existsInMonth = allTransactions.contains {
                    guard seriesKey($0) == expectedSeriesKey else { return false }
                    return calendar.isDate($0.transactionDate, inSameDayAs: expectedDate)
                }

                if !existsInMonth {
                    let generated = CashflowTransaction(
                        transactionType: template.transactionType,
                        amount: template.amount,
                        currency: template.currency,
                        transactionDate: expectedDate,
                        cardID: template.cardID,
                        toCardID: template.toCardID,
                        creditID: template.creditID,
                        investmentID: template.investmentID,
                        incomeCategoryRaw: template.incomeCategoryRaw,
                        expenseCategoryRaw: template.expenseCategoryRaw,
                        note: template.note,
                        recurrenceRule: .none,
                        recurrenceWeekdays: [],
                        recurrenceSeriesID: templateSeriesID,
                        affectsCardBalance: template.affectsCardBalance
                    )
                    let exchangeInfo = await onResolveExchangeInfo(generated)
                    generated.exchangeRate = exchangeInfo.rate
                    generated.exchangeRateDate = exchangeInfo.rateDate
                    generated.exchangeRateCurrency = exchangeInfo.rateCurrency
                    modelContext.insert(generated)
                    await onApplyRecurringToCard(generated)
                    allTransactions.append(generated)
                    didInsert = true
                }

                occurrenceIndex += 1
            }
        }

        guard didInsert else { return false }
        do {
            try modelContext.save()
            return true
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to save recurring transactions: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func applyDuePlannedTransactionsIfNeeded() async -> Bool {
        let referenceNow = now()
        guard let storedCheckpoint = defaults.object(forKey: dueAutoApplyCheckpointKey) as? Date else {
            defaults.set(referenceNow, forKey: dueAutoApplyCheckpointKey)
            return false
        }
        let previousCheckpoint = min(storedCheckpoint, referenceNow)

        if previousCheckpoint != storedCheckpoint {
            defaults.set(previousCheckpoint, forKey: dueAutoApplyCheckpointKey)
        }

        let dueTransactions = transactionsProvider()
            .filter { transaction in
                guard transaction.transactionType == .income || transaction.transactionType == .expense else {
                    return false
                }
                guard transaction.recurrenceRule == .none else { return false }
                guard transaction.affectsCardBalance else { return false }
                guard !transaction.hasAppliedBalanceEffect else { return false }
                return transaction.transactionDate > previousCheckpoint
                    && transaction.transactionDate <= referenceNow
            }
            .sorted { $0.transactionDate < $1.transactionDate }

        guard !dueTransactions.isEmpty else {
            defaults.set(referenceNow, forKey: dueAutoApplyCheckpointKey)
            return false
        }

        for transaction in dueTransactions {
            do {
                try await onApplyDuePlannedEffect(transaction)
                transaction.hasAppliedBalanceEffect = true
                transaction.updatedAt = referenceNow
            } catch {
                AppLogger.log(
                    .error,
                    category: "Cashflow",
                    "Failed to auto-apply due planned transaction: \(error.localizedDescription)"
                )
            }
        }

        do {
            try modelContext.save()
            defaults.set(referenceNow, forKey: dueAutoApplyCheckpointKey)
            return true
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to save due planned auto-apply: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private: Helpers

    private func transactionType(for kind: CashflowCategoryKind) -> CashflowTransactionType {
        switch kind {
        case .income: return .income
        case .expense: return .expense
        }
    }

    private func scheduledEntrySort(lhs: CashflowScheduledEntry, rhs: CashflowScheduledEntry) -> Bool {
        if lhs.scheduledDate != rhs.scheduledDate {
            return lhs.scheduledDate < rhs.scheduledDate
        }
        if lhs.kind.sortPriority != rhs.kind.sortPriority {
            return lhs.kind.sortPriority < rhs.kind.sortPriority
        }
        return lhs.transaction.createdAt < rhs.transaction.createdAt
    }

    // MARK: - Private: Static Recurrence

    static func recurrenceOccurrenceDate(
        templateDate: Date,
        rule: CashflowRecurrenceRule,
        weekdays: Set<CashflowRecurrenceWeekday>,
        occurrenceIndex: Int,
        calendar: Calendar
    ) -> Date? {
        guard occurrenceIndex >= 0 else { return nil }
        if rule == .weekly {
            var selectedWeekdays = weekdays
            if selectedWeekdays.isEmpty,
               let templateWeekday = CashflowRecurrenceWeekday.from(calendarWeekday: calendar.component(.weekday, from: templateDate)) {
                selectedWeekdays.insert(templateWeekday)
            }
            let normalized = Set(selectedWeekdays.compactMap { CashflowRecurrenceWeekday(rawValue: $0.rawValue) })
            guard !normalized.isEmpty else { return occurrenceIndex == 0 ? templateDate : nil }

            var candidate = templateDate
            var matchesCount = 0
            let maxIterations = 366 * 6
            for _ in 0..<maxIterations {
                let weekday = calendar.component(.weekday, from: candidate)
                if normalized.contains(where: { $0.rawValue == weekday }) {
                    if matchesCount == occurrenceIndex { return candidate }
                    matchesCount += 1
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: candidate) else { break }
                candidate = nextDay
            }
            return nil
        }

        guard let monthInterval = rule.monthInterval else { return occurrenceIndex == 0 ? templateDate : nil }

        let monthStart = Self.monthStart(for: templateDate, calendar: calendar)
        guard let targetMonthStart = calendar.date(
            byAdding: .month,
            value: monthInterval * occurrenceIndex,
            to: monthStart
        ) else {
            return nil
        }

        let anchorDay = calendar.component(.day, from: templateDate)
        return Self.makeMonthlyDate(monthStart: targetMonthStart, day: anchorDay, calendar: calendar)
    }

    static func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func makeMonthlyDate(monthStart: Date, day: Int, calendar: Calendar) -> Date {
        let maxDay = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? day
        let clampedDay = min(max(day, 1), maxDay)
        return calendar.date(byAdding: .day, value: clampedDay - 1, to: monthStart) ?? monthStart
    }
}
