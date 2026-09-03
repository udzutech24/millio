import Foundation
import SwiftData

/// Пересчёт вклада при смене даты открытия задним числом (Коммит 3, «умный режим» — решение
/// владельца 2026-09-03: «добавил вклад в приложение в середине месяца», дата открытия должна
/// быть исправляемой, а уже начисленные проценты — пересчитаться, а не остаться от старой даты).
///
/// Полностью ИЗОЛИРОВАНО от `DepositInterestScheduler.rebuildFutureSchedule`/
/// `deleteGeneratedInterestEvents` — те намеренно НИКОГДА не трогают прошлое/подтверждённое (см. их
/// докстринги и `DepositInterestConfirmationSweep`). `recalculateConfirmed` — ЕДИНСТВЕННОЕ место в
/// кодовой базе, которое осознанно нарушает инвариант «подтверждённое начисление неприкосновенно»,
/// и делает это ТОЛЬКО по явному решению пользователя (подтверждение в UI, см.
/// `DepositAccountDetailsSheet`), никогда молча.
enum DepositOpeningDateRecalculation {

    enum RecalculationError: Error, Equatable {
        /// Дата открытия вклада не может быть в будущем — продукт не поддерживает «ещё не
        /// открытые» вклады, а будущая дата сделала бы прошлые подтверждённые начисления бессмысленными.
        case futureOpeningDate
        case notADeposit
    }

    /// Есть ли у вклада хотя бы одно ПОДТВЕРЖДЁННОЕ (уже наступившее) начисление процентов.
    /// Решает выбор пути в UI: нет — тихая перестройка (`applySilently`), есть — явное
    /// подтверждение пользователя перед `recalculateConfirmed`.
    static func hasConfirmedInterest(events: [AccountEvent]) -> Bool {
        events.contains { isConfirmedInterestEvent($0) }
    }

    /// Число подтверждённых начислений — для текста предупреждения («будет пересчитано N начислений»).
    static func confirmedInterestCount(events: [AccountEvent]) -> Int {
        events.filter { isConfirmedInterestEvent($0) }.count
    }

    private static func isConfirmedInterestEvent(_ event: AccountEvent) -> Bool {
        guard event.type == .interest, let sourceID = event.sourceTransactionID else { return false }
        return sourceID.hasPrefix(DepositInterestConfirmationSweep.confirmedSourcePrefix)
    }

    /// Путь БЕЗ подтверждённых начислений — тихая перестройка, инвариант «прошлое неприкосновенно»
    /// НЕ нарушается: подтверждённых событий ещё нет, трогать нечего (только прогнозы, которые и
    /// так пересобирает `regenerateFutureInterestEvents` при любой правке условий).
    @discardableResult
    @MainActor
    static func applySilently(
        account: Account,
        newOpeningDate: Date,
        meta: DepositMeta,
        service: AccountsCoreService,
        asOf: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian),
        context: ModelContext
    ) throws -> Int {
        try apply(
            account: account, newOpeningDate: newOpeningDate, meta: meta, service: service,
            asOf: asOf, calendar: calendar, context: context, stripConfirmed: false
        )
    }

    /// ⚠️ Путь С подтверждёнными начислениями. Вызывать ТОЛЬКО после явного подтверждения
    /// пользователя (красная кнопка в предупреждающем bottom sheet) — это единственное место,
    /// где удаляются и заново создаются УЖЕ ПОДТВЕРЖДЁННЫЕ interest-события счёта.
    @discardableResult
    @MainActor
    static func recalculateConfirmed(
        account: Account,
        newOpeningDate: Date,
        meta: DepositMeta,
        service: AccountsCoreService,
        asOf: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian),
        context: ModelContext
    ) throws -> Int {
        try apply(
            account: account, newOpeningDate: newOpeningDate, meta: meta, service: service,
            asOf: asOf, calendar: calendar, context: context, stripConfirmed: true
        )
    }

    /// Общая механика обоих путей — различаются только тем, сносим ли уже ПОДТВЕРЖДЁННЫЕ события.
    /// Ручные события (`openingBalance`, `income`/пополнения, `adjustment`, переводы и т.п.) сюда
    /// не попадают ни при каком `stripConfirmed`: фильтр смотрит только на `.interest`-события с
    /// префиксом генератора (`DepositConfirmedBalanceResolver`/`DepositInterestConfirmationSweep`).
    @discardableResult
    @MainActor
    private static func apply(
        account: Account,
        newOpeningDate: Date,
        meta: DepositMeta,
        service: AccountsCoreService,
        asOf: Date,
        calendar: Calendar,
        context: ModelContext,
        stripConfirmed: Bool
    ) throws -> Int {
        guard account.kind == .deposit else { throw RecalculationError.notADeposit }
        guard newOpeningDate <= asOf else { throw RecalculationError.futureOpeningDate }

        let oldOpeningDate = account.createdAt
        let accountID = account.id
        let descriptor = FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.account?.id == accountID }
        )
        let allEvents = (try? context.fetch(descriptor)) ?? (account.events ?? [])

        let toDelete = allEvents.filter { event in
            guard event.type == .interest else { return false }
            let isForecast = DepositConfirmedBalanceResolver.isGeneratedInterest(event, accountID: accountID)
            let isConfirmed = isConfirmedInterestEvent(event)
            return isForecast || (stripConfirmed && isConfirmed)
        }
        let toDeleteIDs = Set(toDelete.map(\.id))
        for event in toDelete { context.delete(event) }

        account.createdAt = newOpeningDate
        account.depositMeta = meta

        // Расписание от новой даты открытия — тот же чистый билдер, что и обычная правка условий
        // (`DepositOperationCoordinator.editTerms` → `buildFutureSchedule`), формулы не переписаны.
        let survivingEvents = allEvents.filter { !toDeleteIDs.contains($0.id) }
        let drafts = DepositInterestScheduler.buildFutureSchedule(
            accountID: accountID, meta: meta, openingDate: newOpeningDate,
            confirmedEvents: survivingEvents, after: newOpeningDate, calendar: calendar
        )
        for draft in drafts {
            _ = try service.upsertInterestEvent(
                sourceTransactionID: draft.sourceTransactionID, account: account,
                amount: draft.amount, date: draft.date, saveChanges: false
            )
        }

        // Досчитать горизонт вперёд ОТ СЕГОДНЯ (для бессрочных вкладов) и подтвердить наступившие
        // даты — оба существующих механизма, вызванных в их обычном порядке (см. `AccountDetailView`
        // `.task` / `extendActiveDepositHorizons`), не переписаны.
        _ = try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: asOf, calendar: calendar, context: context
        )
        DepositInterestConfirmationSweep.run(context: context, asOf: asOf)

        // Кэш снапшотов ЭТОГО счёта от более ранней из старой/новой даты открытия — тот же публичный
        // метод, которым уже пользуется каждая мутация движка. Другие счета, Cashflow-мост и тоталы
        // не читаются и не пишутся.
        service.invalidateSnapshotCache(for: account, from: min(oldOpeningDate, newOpeningDate))
        HistoricalValuationRevisionTracker.bump([.financial, .events], on: account)

        try context.save()
        return drafts.count
    }
}
