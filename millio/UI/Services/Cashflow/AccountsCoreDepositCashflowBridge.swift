//
//  AccountsCoreDepositCashflowBridge.swift
//  millio
//
//  Мост АccountsCore → Cashflow (Фаза 0 плана `2026-07-05__cashflow-add-transaction-redesign.md`,
//  §1.8/§4). Направление ПРОТИВОПОЛОЖНОЕ `AccountsCoreCashflowBridge` (тот пишет Cashflow → ядро):
//  здесь мы читаем уже сгенерированные `AccountEvent(.interest)` вклада (см. `DepositInterestScheduler`)
//  и делаем ставшие due (`date <= today`) события ВИДИМЫМИ доходными записями в ленте Cashflow —
//  без этого начисление процентов по вкладам, созданным через новое ядро счетов, происходит
//  «в фоне», а пользователь не видит дохода в табе Cashflow (подтверждённая находка §1.8.B).
//
//  Почему материализация в `CashflowTransaction`, а не read-слой на лету при рендере ленты:
//  Cashflow (история, breakdown по категориям, месячные итоги, бюджет-прогресс) целиком читает
//  `CashflowTransaction` через SwiftData `FetchDescriptor` в десятках мест `CashflowViewModel`/
//  `CashflowAnalyticsService`. Подмешивать виртуальные (не persisted) записи в КАЖДОЕ из этих мест —
//  инвазивнее и рискованнее, чем один раз материализовать событие в реальную строку по тому же
//  идемпотентному upsert-паттерну, что уже применяет `CashflowScheduledService` (existsInMonth-проверка
//  перед вставкой). Баланс при этом не задваивается: у материализованной транзакции
//  `affectsCardBalance = false` и `cardID = nil` — баланс вклада уже отражён в AccountsCore
//  через сам AccountEvent, эта запись — ТОЛЬКО для видимости в Cashflow (лента/бюджет/история).
//

import Foundation
import SwiftData

/// Делает due-проценты вкладов нового ядра счетов видимыми в Cashflow (см. докстринг файла).
@MainActor
final class AccountsCoreDepositCashflowBridge {

    /// Значение `importSourceRaw` для материализованных строк — свой namespace, не пересекается
    /// с `CashflowBulkExpenseImportTransactionSource` (та сравнивается строковым равенством, а не
    /// декодированием enum, поэтому новое значение здесь безопасно и не ломает bulk-import дедуп).
    static let interestImportSource = "accountsCoreDepositInterest"

    private let modelContext: ModelContext
    private let now: () -> Date
    /// Инжектируемый, по образцу `DepositInterestScheduler.regenerateFutureInterestEvents(calendar:)` —
    /// без этого тесты, фиксирующие даты через явный UTC-календарь, и `Calendar.current` рантайма
    /// (device timezone) расходятся на несколько часов у полуночных границ периода, и due-события
    /// на самой границе `date <= today` то пропадают, то дублируются в зависимости от TZ машины.
    private let calendar: Calendar
    private var isSyncInProgress = false

    init(
        modelContext: ModelContext,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.modelContext = modelContext
        self.now = now
        self.calendar = calendar
    }

    /// Фоновый запуск с guard от дублирования — по образцу `CashflowScheduledService
    /// .scheduleRecurringGeneration()`. Вызывающая сторона узнаёт о новых материализованных
    /// транзакциях через колбэк (нужно перечитать `state.transactions`).
    func scheduleSync(onDidMaterialize: @escaping () -> Void) {
        guard !isSyncInProgress else { return }
        isSyncInProgress = true
        Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isSyncInProgress = false }
            if self.syncDepositInterestLedger() {
                onDidMaterialize()
            }
        }
    }

    /// Единая точка входа: продлевает горизонт генерации будущих interest-событий для активных
    /// вкладов (см. `DepositInterestScheduler.extendActiveDepositHorizons`), затем материализует
    /// в Cashflow всё, что уже наступило. Порядок важен: без первого шага бессрочный вклад старше
    /// исходного горизонта не породил бы новых событий для материализации во втором шаге.
    @discardableResult
    func syncDepositInterestLedger() -> Bool {
        DepositInterestScheduler.extendActiveDepositHorizons(context: modelContext, asOf: now(), calendar: calendar)
        return materializeDueInterestIncome()
    }

    /// Будущее (ещё не due) начисление процентов по вкладу — читает уже сгенерированный
    /// `AccountEvent` (см. `DepositInterestScheduler.extendActiveDepositHorizons`), суммы/даты
    /// не пересчитываются заново. Используется секцией «Предстоящие» на главном экране Cashflow
    /// (Фаза 0, Шаг 6, план `2026-07-05__cashflow-add-transaction-redesign.md`).
    struct UpcomingInterestEvent {
        let date: Date
        let amount: Double
        let currencyCode: String
        let accountID: UUID
        let accountName: String
    }

    /// Ближайшие будущие (`date > today`) начисления процентов по активным вкладам — до
    /// материализации в Cashflow (см. `materializeDueInterestIncome`). Тот же приём чтения, что и
    /// там: широкий фетч `AccountEvent` + фильтрация в Swift (без compound-предиката с traversal).
    /// Архивные вклады не исключаются намеренно — согласуется с тем, что уже сгенерированные ДО
    /// закрытия due-события всё равно материализуются (см. §7.3.2 плана).
    func upcomingInterestEvents(limit: Int = 10) -> [UpcomingInterestEvent] {
        let today = calendar.startOfDay(for: now())
        let allEvents = (try? modelContext.fetch(FetchDescriptor<AccountEvent>())) ?? []

        return allEvents
            .filter { $0.type == .interest && $0.date > today && $0.account?.kind == .deposit }
            .sorted { $0.date < $1.date }
            .compactMap { event -> UpcomingInterestEvent? in
                guard let account = event.account, let amount = event.amount, amount > 0 else { return nil }
                return UpcomingInterestEvent(
                    date: event.date,
                    amount: NSDecimalNumber(decimal: amount).doubleValue,
                    currencyCode: account.currency,
                    accountID: account.id,
                    accountName: account.name
                )
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Материализует в Cashflow все due (`date <= today`) interest-события вкладов, у которых ещё
    /// нет соответствующей строки. Идемпотентно: ключ дедупа — `importReferenceKey` == `AccountEvent
    /// .sourceTransactionID` (тот уже уникален на период по конвенции `DepositInterestScheduler`).
    /// Повторный вызов (при каждой загрузке таба Cashflow) не создаёт дублей.
    @discardableResult
    func materializeDueInterestIncome() -> Bool {
        let today = calendar.startOfDay(for: now())
        let sourceTag = Self.interestImportSource

        // Фетч БЕЗ compound-предиката с traversal через relationship + сравнением дат: сочетание
        // `account?.kindRaw == X && date <= Y` в одном #Predicate на этой SwiftData-версии не находит
        // совпадений (проверено эмпирически — 0 результатов при заведомо существующих событиях).
        // Фетчим широко и фильтруем в Swift — тот же приём, что уже использует
        // `CashflowScheduledService` (fetch всех транзакций, фильтрация `.filter` в памяти).
        let allEvents = (try? modelContext.fetch(FetchDescriptor<AccountEvent>())) ?? []
        let dueEvents = allEvents
            .filter { $0.type == .interest && $0.date <= today && $0.account?.kind == .deposit }
            .sorted { $0.date < $1.date }
        guard !dueEvents.isEmpty else { return false }

        let allTransactions = (try? modelContext.fetch(FetchDescriptor<CashflowTransaction>())) ?? []
        let existingKeys = Set(
            allTransactions
                .filter { $0.importSourceRaw == sourceTag }
                .compactMap(\.importReferenceKey)
        )

        var didInsert = false
        for event in dueEvents {
            guard let key = event.sourceTransactionID, !existingKeys.contains(key) else { continue }
            guard let account = event.account, let amount = event.amount, amount > 0 else { continue }

            let transaction = CashflowTransaction(
                transactionType: .income,
                amount: NSDecimalNumber(decimal: amount).doubleValue,
                currency: account.currency,
                transactionDate: event.date,
                incomeCategory: .interest,
                // Имя счёта — данные пользователя (он сам его так назвал при создании вклада),
                // не UI-строка приложения, поэтому localization-правило про raw RU-литералы не применимо.
                note: account.name.isEmpty ? nil : account.name,
                importSourceRaw: sourceTag,
                importReferenceKey: key,
                affectsCardBalance: false
            )
            modelContext.insert(transaction)
            didInsert = true
        }

        guard didInsert else { return false }
        do {
            try modelContext.save()
            return true
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось материализовать доход по вкладу в Cashflow: \(error)")
            return false
        }
    }
}
