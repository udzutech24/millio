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

    /// `DataScope.storeConfigurationName` активного стора. Берётся явно от владельца сервиса
    /// (конфигурация контейнера), а НЕ из `AppState.activeScopeKey`: тот дефолтится в guest и на
    /// холодном старте может не успеть получить реальный scope.
    private let scopeIdentifier: String

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

    /// Журнал непоказанных применений. Пополняется ТОЛЬКО после успешного `modelContext.save()`.
    private let appliedNoticeStore: AppliedPlannedNoticeStore

    /// Колбэк: имя счёта транзакции. Сервису недоступно — легаси-карты и счета нового ядра
    /// лежат в разных мирах данных, а резолвер обоих живёт в VM.
    private let noticeAccountNameResolver: (CashflowTransaction) -> String

    /// Колбэк: отображаемый заголовок транзакции (заметка/категория) — резолверы категорий в VM.
    private let noticeTitleResolver: (CashflowTransaction) -> String

    // MARK: - State

    private var isRecurringGenerationInProgress = false
    private var isDueAutoApplyInProgress = false

    /// Префикс per-scope ключа чекпойнта. До разделения ключ был общим на всё приложение —
    /// гостевая сессия двигала чекпойнт владельца, и его плановые операции не применялись никогда.
    static let dueAutoApplyCheckpointKeyPrefix = "cashflow_due_auto_apply_checkpoint_v1."

    /// Общий ключ до разделения по scope. Переносится в per-scope ключ при первом запуске: без
    /// переноса чекпойнт стал бы nil, окно [чекпойнт, сейчас] схлопнулось бы и due-операции
    /// из него не применились бы уже никогда.
    static let legacyDueAutoApplyCheckpointKey = "cashflow_due_auto_apply_checkpoint_v1"

    private var dueAutoApplyCheckpointKey: String {
        Self.dueAutoApplyCheckpointKeyPrefix + scopeIdentifier
    }

    // MARK: - Init

    init(
        modelContext: ModelContext,
        defaults: UserDefaults,
        scopeIdentifier: String,
        now: @escaping () -> Date,
        transactionsProvider: @escaping () -> [CashflowTransaction],
        onTransactionsMutated: @escaping () -> Void,
        onResolveExchangeInfo: @escaping (CashflowTransaction) async -> CashflowExchangeInfo,
        onApplyRecurringToCard: @escaping (CashflowTransaction) async -> Void,
        onApplyDuePlannedEffect: @escaping (CashflowTransaction) async throws -> Void,
        appliedNoticeStore: AppliedPlannedNoticeStore,
        noticeAccountNameResolver: @escaping (CashflowTransaction) -> String,
        noticeTitleResolver: @escaping (CashflowTransaction) -> String
    ) {
        self.modelContext = modelContext
        self.defaults = defaults
        self.scopeIdentifier = scopeIdentifier
        self.now = now
        self.transactionsProvider = transactionsProvider
        self.onTransactionsMutated = onTransactionsMutated
        self.onResolveExchangeInfo = onResolveExchangeInfo
        self.onApplyRecurringToCard = onApplyRecurringToCard
        self.onApplyDuePlannedEffect = onApplyDuePlannedEffect
        self.appliedNoticeStore = appliedNoticeStore
        self.noticeAccountNameResolver = noticeAccountNameResolver
        self.noticeTitleResolver = noticeTitleResolver
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
        let plannedDatePolicy = CashflowPlannedDatePolicy(calendar: .current)
        let targetType = transactionType(for: kind)

        return transactionsProvider()
            .filter { transaction in
                guard transaction.transactionType == targetType else { return false }
                guard transaction.recurrenceRule == .none else { return false }
                return plannedDatePolicy.isOneTimePlanned(transaction.transactionDate, relativeTo: baseline)
            }
            .sorted { $0.transactionDate < $1.transactionDate }
    }

    /// Все запланированные записи для planner-экрана: recurring + разовые после baseline.
    func scheduledPlannerEntries(
        for kind: CashflowCategoryKind,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowScheduledEntry] {
        let baseline = Calendar.current.startOfDay(for: referenceDate ?? now())
        let plannedDatePolicy = CashflowPlannedDatePolicy(calendar: .current)
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

                guard transaction.recurrenceRule == .none,
                      plannedDatePolicy.isOneTimePlanned(transaction.transactionDate, relativeTo: baseline) else {
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
        let plannedDatePolicy = CashflowPlannedDatePolicy(calendar: calendar)
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
                guard plannedDatePolicy.isOneTimePlanned(transaction.transactionDate, relativeTo: baseline) else {
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
        let scheduledAt = now()

        Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isDueAutoApplyInProgress = false }

            let didApply = await self.applyDuePlannedTransactionsIfNeeded(referenceNow: scheduledAt)
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
        // Буфер сводки: записи копятся здесь и уходят в журнал только после успешного save().
        var pendingNotices: [AppliedPlannedEntry] = []
        let noticeAppliedAt = now()
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
            guard templateDate <= today else { continue }
            let expectedSeriesKey = "\(templateSeriesID)|\(template.transactionTypeRaw)"
            // The persisted template occupies its anchor date. Generation starts with the next
            // occurrence, otherwise the anchor is duplicated and its balance effect is applied
            // immediately when the user merely creates the template.
            var occurrenceIndex = 1

            while let expectedDate = Self.recurrenceOccurrenceDate(
                templateDate: templateDate,
                rule: template.recurrenceRule,
                weekdays: template.recurrenceWeekdays,
                occurrenceIndex: occurrenceIndex,
                calendar: calendar
            ) {
                guard expectedDate >= templateDate else {
                    occurrenceIndex += 1
                    continue
                }
                if expectedDate > today { break }

                // Шаблоны исключаем из проверки существования: нас интересуют только сгенерированные экземпляры.
                let existsInMonth = allTransactions.contains {
                    guard !$0.isRecurringTemplate else { return false }
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
                    guard (try? CashflowMonthMutationPolicy(modelContext: modelContext).validate(
                        .scheduledApply,
                        date: generated.transactionDate
                    )) != nil else {
                        occurrenceIndex += 1
                        continue
                    }
                    modelContext.insert(generated)
                    await onApplyRecurringToCard(generated)
                    allTransactions.append(generated)
                    pendingNotices.append(
                        makeAppliedNotice(for: generated, kind: .recurring, appliedAt: noticeAppliedAt)
                    )
                    didInsert = true
                }

                occurrenceIndex += 1
            }
        }

        guard didInsert else { return false }
        do {
            try modelContext.save()
            commitAppliedNotices(pendingNotices)
            return true
        } catch {
            // Буфер выбрасывается вместе с несохранённой пачкой: сводка не должна отчитаться
            // об операциях, которых в базе нет.
            AppLogger.log(.error, category: "Cashflow", "Failed to save recurring transactions: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func applyDuePlannedTransactionsIfNeeded(referenceNow: Date? = nil) async -> Bool {
        let referenceNow = referenceNow ?? now()
        migrateLegacyCheckpointIfNeeded()
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

        // Провал применения хотя бы одной операции запрещает двигать чекпойнт: иначе она уходит
        // за окно [чекпойнт, сейчас] и не применится уже никогда (деньги теряются молча).
        // Пропуск по политике закрытого месяца — не провал: это осознанный отказ, и удержание
        // чекпойнта из-за него зациклило бы ретраи навсегда.
        var hasFailedApply = false

        // Буфер сводки согласован с логикой провалов: сюда попадают только операции, чей apply
        // прошёл без ошибки. Провалившаяся остаётся внутри окна (чекпойнт не двигается) и попадёт
        // в журнал тем прогоном, в котором реально применится; повтора по уже применённым не будет —
        // их отсекает hasAppliedBalanceEffect. Пропуск по политике закрытого месяца в буфер не идёт.
        var pendingNotices: [AppliedPlannedEntry] = []

        for transaction in dueTransactions {
            guard (try? CashflowMonthMutationPolicy(modelContext: modelContext).validate(
                .scheduledApply,
                date: transaction.transactionDate
            )) != nil else {
                continue
            }
            do {
                try await onApplyDuePlannedEffect(transaction)
                transaction.hasAppliedBalanceEffect = true
                transaction.updatedAt = referenceNow
                pendingNotices.append(
                    makeAppliedNotice(for: transaction, kind: .scheduled, appliedAt: referenceNow)
                )
            } catch {
                hasFailedApply = true
                AppLogger.log(
                    .error,
                    category: "Cashflow",
                    "Failed to auto-apply due planned transaction: \(error.localizedDescription)"
                )
            }
        }

        do {
            try modelContext.save()
            commitAppliedNotices(pendingNotices)
            // Повторный проход по успешно применённым безопасен — их отсекает hasAppliedBalanceEffect.
            if hasFailedApply {
                AppLogger.log(
                    .warning,
                    category: "Cashflow",
                    "Due auto-apply checkpoint kept at previous value after failed apply"
                )
            } else {
                defaults.set(referenceNow, forKey: dueAutoApplyCheckpointKey)
            }
            return true
        } catch {
            // Сохранение не прошло — буфер сводки выбрасывается целиком (см. комментарий выше).
            AppLogger.log(.error, category: "Cashflow", "Failed to save due planned auto-apply: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private: Applied Notice Journal

    /// Переносит буфер в журнал. Вызывается ТОЛЬКО из ветки успешного `modelContext.save()`.
    private func commitAppliedNotices(_ entries: [AppliedPlannedEntry]) {
        for entry in entries {
            appliedNoticeStore.append(entry)
        }
    }

    /// Собирает запись сводки. Величину берём по модулю, а знак — от типа операции: если в модели
    /// когда-нибудь окажется уже отрицательная сумма расхода, знак не удвоится и нетто-итог сводки
    /// не разойдётся с реальностью.
    private func makeAppliedNotice(
        for transaction: CashflowTransaction,
        kind: AppliedPlannedEntry.Kind,
        appliedAt: Date
    ) -> AppliedPlannedEntry {
        let magnitude = Self.noticeDecimal(from: abs(transaction.amount))
        return AppliedPlannedEntry(
            title: noticeTitleResolver(transaction),
            accountName: noticeAccountNameResolver(transaction),
            amount: transaction.transactionType == .expense ? -magnitude : magnitude,
            currencyCode: transaction.currency,
            appliedAt: appliedAt,
            kind: kind
        )
    }

    /// Double → Decimal через строковое представление — прямой `Decimal(Double)` протаскивает
    /// двоичный мусор в суммы сводки. Тот же приём, что в `AccountsCoreCashflowBridge`.
    private static func noticeDecimal(from value: Double) -> Decimal {
        Decimal(string: String(format: "%.6f", value)) ?? Decimal(value)
    }

    /// Переносит общий (до-scope) чекпойнт в per-scope ключ. Идемпотентно: срабатывает, только пока
    /// per-scope значения нет. Легаси-ключ не удаляем — его ещё может забрать другой scope.
    private func migrateLegacyCheckpointIfNeeded() {
        guard defaults.object(forKey: dueAutoApplyCheckpointKey) == nil,
              let legacyCheckpoint = defaults.object(forKey: Self.legacyDueAutoApplyCheckpointKey) as? Date else {
            return
        }
        defaults.set(legacyCheckpoint, forKey: dueAutoApplyCheckpointKey)
        AppLogger.log(
            .info,
            category: "Cashflow",
            "Migrated shared due auto-apply checkpoint into scope \(scopeIdentifier)"
        )
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
