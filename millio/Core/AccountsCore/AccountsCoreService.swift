import Foundation
import SwiftData

/// Ошибки записи в ядро счетов.
enum AccountsCoreServiceError: Error {
    /// `recordEvent` вызван с типом, не предназначенным для генерик-записи (перевод — только через `transfer`).
    case unsupportedEventType(AccountEventType)
    /// Перевод счёта самому себе.
    case sameAccountTransfer
    /// Перевод между счетами разной валюты без явного курса — конвертация ДО вызова обязательна (см. спеку §2.6).
    case missingFxRate
    /// Событие без привязанного счёта — не может быть отредактировано этим сервисом.
    case eventWithoutAccount
}

/// Единственная точка записи в новое ядро счетов (event-sourcing). Любое изменение баланса —
/// это вставка/правка `AccountEvent`, никогда прямая мутация хранимого числа (AC1, AC9).
/// Хранимого баланса у `Account` нет вообще — баланс всегда производная `balanceAt`/кэша.
@MainActor
final class AccountsCoreService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Создание счёта

    /// Создаёт счёт и якорное событие `.openingBalance` — ВСЕГДА, даже при нулевом балансе:
    /// без якоря история счёта не имеет точки отсчёта для реплея (первый `balanceAt` до первого
    /// события иначе не отличим от «счёта не существовало»).
    @discardableResult
    func createAccount(
        name: String,
        kind: AccountKind,
        currency: String,
        openingBalance: Decimal,
        group: AccountGroup? = nil,
        cardMeta: CardMeta? = nil,
        note: String? = nil,
        date: Date = Date()
    ) throws -> Account {
        let account = Account(name: name, kind: kind, currency: currency, createdAt: date)
        account.group = group
        account.cardMeta = cardMeta
        account.note = note
        modelContext.insert(account)

        let opening = AccountEvent(account: account, date: date, type: .openingBalance, amount: openingBalance)
        modelContext.insert(opening)

        try modelContext.save()
        return account
    }

    // MARK: - Запись операции

    /// Генерик-запись дохода/расхода/ручной корректировки. Перевод между счетами — не сюда, см. `transfer`.
    /// Сумма ДОЛЖНА быть уже сконвертирована в валюту счёта вызывающим кодом (спека §2.5 п.2);
    /// `fxRateUsed`/`originalAmount`/`originalCurrency` — только зафиксированный след использованного курса,
    /// повторно он не запрашивается (AC10).
    @discardableResult
    func recordEvent(
        account: Account,
        type: AccountEventType,
        amount: Decimal,
        date: Date = Date(),
        categoryID: String? = nil,
        note: String? = nil,
        originalAmount: Decimal? = nil,
        originalCurrency: String? = nil,
        fxRateUsed: Decimal? = nil
    ) throws -> AccountEvent {
        guard type == .income || type == .expense || type == .adjustment else {
            throw AccountsCoreServiceError.unsupportedEventType(type)
        }

        let event = AccountEvent(
            account: account,
            date: date,
            type: type,
            amount: amount,
            fxRateToBase: fxRateUsed,
            categoryID: categoryID,
            note: note,
            originalAmount: originalAmount,
            originalCurrency: originalCurrency
        )
        modelContext.insert(event)
        invalidateCache(for: account, from: date)
        try modelContext.save()
        return event
    }

    /// Корректировка баланса «до значения» (UI: пользователь вбивает новый остаток) — считает
    /// ДЕЛЬТУ от текущего `balanceAt` и создаёт `adjustment`-событие с этой дельтой (AC1: события,
    /// а не хранимое поле, остаются единственным источником истины).
    @discardableResult
    func adjustBalance(account: Account, to newValue: Decimal, on date: Date = Date()) throws -> AccountEvent {
        let current = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: date)
        let delta = newValue - current

        let event = AccountEvent(account: account, date: date, type: .adjustment, amount: delta)
        modelContext.insert(event)
        invalidateCache(for: account, from: date)
        try modelContext.save()
        return event
    }

    // MARK: - Мост Cashflow (Фаза 1b): идемпотентная запись по sourceTransactionID

    /// Идемпотентная запись income/expense/adjustment по `sourceTransactionID` (мост Cashflow →
    /// новое ядро, спека §2.5): если событие с этим `sourceTransactionID` уже есть — обновляет
    /// его на месте, иначе создаёт новое. Повторный вызов с теми же данными не плодит дубликаты
    /// (нужно для правки транзакции задним числом и для повторного запуска recurring-генератора).
    @discardableResult
    func upsertEvent(
        sourceTransactionID: String,
        account: Account,
        type: AccountEventType,
        amount: Decimal,
        date: Date,
        categoryID: String? = nil,
        note: String? = nil,
        originalAmount: Decimal? = nil,
        originalCurrency: String? = nil,
        fxRateUsed: Decimal? = nil,
        fxProvisional: Bool = false
    ) throws -> AccountEvent {
        guard type == .income || type == .expense || type == .adjustment else {
            throw AccountsCoreServiceError.unsupportedEventType(type)
        }

        let descriptor = FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == sourceTransactionID }
        )
        let existing = try? modelContext.fetch(descriptor).first

        let event: AccountEvent
        let earliestDate: Date
        if let existing {
            earliestDate = min(existing.date, date)
            existing.account = account
            existing.typeRaw = type.rawValue
            existing.amount = amount
            existing.setDate(date)
            existing.categoryID = categoryID
            existing.note = note
            existing.originalAmount = originalAmount
            existing.originalCurrency = originalCurrency
            existing.fxRateToBase = fxRateUsed
            existing.fxProvisional = fxProvisional
            event = existing
        } else {
            earliestDate = date
            event = AccountEvent(
                account: account,
                date: date,
                type: type,
                amount: amount,
                fxRateToBase: fxRateUsed,
                fxProvisional: fxProvisional,
                categoryID: categoryID,
                note: note,
                sourceTransactionID: sourceTransactionID,
                originalAmount: originalAmount,
                originalCurrency: originalCurrency
            )
            modelContext.insert(event)
        }

        invalidateCache(for: account, from: earliestDate)
        try modelContext.save()
        return event
    }

    /// Удаляет событие(я), связанное(ые) с легаси-транзакцией Cashflow по `sourceTransactionID`.
    /// Перевод (обе ноги делят один `sourceTransactionID`) удаляется целиком через каскад
    /// `deleteEvent` по `transferID` — фетчим ОДНУ ногу, остальное берёт на себя `deleteEvent`.
    /// Нет связанного события — no-op (частый случай: транзакция никогда не целилась в новый мир).
    func deleteEvents(bySourceTransactionID sourceTransactionID: String) throws {
        let descriptor = FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == sourceTransactionID }
        )
        guard let event = try modelContext.fetch(descriptor).first else { return }
        try deleteEvent(event)
    }

    // MARK: - Перевод между счетами

    /// Перевод — ДВЕ ноги (`transferOut` на источнике + `transferIn` на получателе) с общим `transferID`,
    /// вставляются и сохраняются атомарно в ОДНОЙ транзакции контекста (AC12: Σ переводов = 0).
    /// Сумма получателя = `amountInSourceCurrency × fxRate` (курс фиксируется в обеих ногах и больше
    /// не пересчитывается). При равенстве валют счетов `fxRate` не обязателен (курс = 1).
    @discardableResult
    func transfer(
        from source: Account,
        to destination: Account,
        amountInSourceCurrency: Decimal,
        date: Date = Date(),
        fxRate: Decimal? = nil,
        note: String? = nil,
        sourceTransactionID: String? = nil
    ) throws -> (out: AccountEvent, in: AccountEvent) {
        guard source.id != destination.id else {
            throw AccountsCoreServiceError.sameAccountTransfer
        }

        let rate: Decimal
        if source.currency == destination.currency {
            rate = 1
        } else if let fxRate {
            rate = fxRate
        } else {
            throw AccountsCoreServiceError.missingFxRate
        }

        let transferID = UUID()
        let now = Date()
        let amountInDestinationCurrency = amountInSourceCurrency * rate

        let outEvent = AccountEvent(
            account: source, date: date, createdAt: now, type: .transferOut,
            amount: amountInSourceCurrency, fxRateToBase: fxRate, note: note, transferID: transferID,
            sourceTransactionID: sourceTransactionID
        )
        let inEvent = AccountEvent(
            account: destination, date: date, createdAt: now, type: .transferIn,
            amount: amountInDestinationCurrency, fxRateToBase: fxRate, note: note, transferID: transferID,
            sourceTransactionID: sourceTransactionID
        )

        modelContext.insert(outEvent)
        modelContext.insert(inEvent)
        invalidateCache(for: source, from: date)
        invalidateCache(for: destination, from: date)
        try modelContext.save()
        return (outEvent, inEvent)
    }

    // MARK: - Правка/удаление задним числом

    /// Удаляет событие. Если у события есть `transferID` — удаляются ОБЕ ноги перевода: одну ногу
    /// отменить невозможно (иначе нарушается инвариант Σ переводов = 0, AC12).
    func deleteEvent(_ event: AccountEvent) throws {
        if let transferID = event.transferID {
            let descriptor = FetchDescriptor<AccountEvent>(
                predicate: #Predicate<AccountEvent> { $0.transferID == transferID }
            )
            let legs = try modelContext.fetch(descriptor)
            var touchedAccounts: [Account] = []
            var earliest = event.date
            for leg in legs {
                earliest = min(earliest, leg.date)
                if let account = leg.account, !touchedAccounts.contains(where: { $0.id == account.id }) {
                    touchedAccounts.append(account)
                }
                modelContext.delete(leg)
            }
            for account in touchedAccounts {
                invalidateCache(for: account, from: earliest)
            }
        } else {
            let account = event.account
            let date = event.date
            modelContext.delete(event)
            if let account {
                invalidateCache(for: account, from: date)
            }
        }
        try modelContext.save()
    }

    /// Правка события задним числом (сумма/дата/категория/заметка). Реплей от МИНИМАЛЬНОЙ из
    /// старой и новой даты пересчитывает всё вперёд автоматически (спека §2.5 п.6).
    @discardableResult
    func updateEvent(
        _ event: AccountEvent,
        amount: Decimal? = nil,
        date: Date? = nil,
        categoryID: String? = nil,
        note: String? = nil
    ) throws -> AccountEvent {
        guard let account = event.account else {
            throw AccountsCoreServiceError.eventWithoutAccount
        }

        let oldDate = event.date
        if let amount { event.amount = amount }
        if let date { event.setDate(date) }
        if let categoryID { event.categoryID = categoryID }
        if let note { event.note = note }

        invalidateCache(for: account, from: min(oldDate, event.date))
        try modelContext.save()
        return event
    }

    // MARK: - Архивация

    /// «Удалить» в основном UI = архивация, НИКОГДА не деструктивно (AC7). История ДО `archivedAt`
    /// не меняется — `Account.participates(on:)` уже времязависим (Фаза 0).
    func archiveAccount(_ account: Account, on date: Date = Date()) throws {
        account.archivedAt = date
        invalidateCache(for: account, from: date)
        try modelContext.save()
    }

    func restoreAccount(_ account: Account) throws {
        let previousArchivedAt = account.archivedAt
        account.archivedAt = nil
        if let previousArchivedAt {
            invalidateCache(for: account, from: previousArchivedAt)
        }
        try modelContext.save()
    }

    // MARK: - Инвалидация кэша

    /// Удаляет снапшоты счёта от даты `date` включительно и дальше — снапшот-кэш «синхронный» слой,
    /// пересборка (`AccountSnapshotRebuilder`, фоновый актор) досчитает недостающий хвост при
    /// следующем обращении к тоталам/графику. Точки ДО `date` не трогаем (инкрементальность).
    ///
    /// ВАЖНО: снапшоты вставляет фоновый актор через СВОЙ ModelContext (тот же контейнер/хранилище,
    /// но другой контекст) — закэшированная relationship `account.snapshots` в НАШЕМ mainContext их
    /// не видит без явного refetch (cross-context, тот же нюанс, что в `AccountsTotalsService`).
    /// Поэтому читаем `AccountDailySnapshot` напрямую через `FetchDescriptor`, а не через relationship.
    private func invalidateCache(for account: Account, from date: Date) {
        let cutoffKey = AccountEvent.dayKey(for: date)
        let accountRecordID = account.id
        let descriptor = FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { $0.account?.id == accountRecordID && $0.dayKey >= cutoffKey }
        )
        guard let stale = try? modelContext.fetch(descriptor) else { return }
        for snapshot in stale {
            modelContext.delete(snapshot)
        }
    }
}
