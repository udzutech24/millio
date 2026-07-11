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
        depositMeta: DepositMeta? = nil,
        loanMeta: LoanMeta? = nil,
        debtMeta: DebtMeta? = nil,
        marketMeta: MarketMeta? = nil,
        manualAssetMeta: ManualAssetMeta? = nil,
        note: String? = nil,
        date: Date = Date()
    ) throws -> Account {
        let account = Account(name: name, kind: kind, currency: currency, createdAt: date)
        account.group = group
        account.cardMeta = cardMeta
        account.depositMeta = depositMeta
        account.loanMeta = loanMeta
        account.debtMeta = debtMeta
        account.marketMeta = marketMeta
        account.manualAssetMeta = manualAssetMeta
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

    // MARK: - Рыночный счёт (Фаза 4): buy/sell/dividend/fee

    /// Покупка актива — увеличивает `quantity` (движок E реплеит Σ buy−sell × цена(дата)).
    /// `unitPrice` — цена ПОКУПКИ (не текущая рыночная), фиксируется на событии навсегда.
    @discardableResult
    func buy(account: Account, quantity: Decimal, unitPrice: Decimal, date: Date = Date(), note: String? = nil) throws -> AccountEvent {
        guard account.kind == .marketInvestment else { throw AccountsCoreServiceError.unsupportedEventType(.buy) }
        let event = AccountEvent(account: account, date: date, type: .buy, quantity: quantity, unitPrice: unitPrice, note: note)
        modelContext.insert(event)
        invalidateCache(for: account, from: date)
        try modelContext.save()
        return event
    }

    /// Продажа актива — уменьшает `quantity`. НЕ проверяет «продажа больше остатка» (не жёсткий
    /// запрет, брифинг Фазы 4, п.4) — предупреждение считает вызывающий UI по текущему `quantity`.
    @discardableResult
    func sell(account: Account, quantity: Decimal, unitPrice: Decimal, date: Date = Date(), note: String? = nil) throws -> AccountEvent {
        guard account.kind == .marketInvestment else { throw AccountsCoreServiceError.unsupportedEventType(.sell) }
        let event = AccountEvent(account: account, date: date, type: .sell, quantity: quantity, unitPrice: unitPrice, note: note)
        modelContext.insert(event)
        invalidateCache(for: account, from: date)
        try modelContext.save()
        return event
    }

    /// Дивиденд/комиссия рыночного счёта — ЧИСТО ИНФОРМАЦИОННЫЕ события для P&L карточки счёта
    /// (брифинг Фазы 4, задача 6, решение): движок E (`AccountBalanceEngine.marketBalance`) считает
    /// баланс ТОЛЬКО по buy/sell, dividend/fee НЕ влияют на quantity и не входят в qty×price —
    /// намеренно, чтобы «стоимость позиции» не путалась с денежными потоками от неё.
    @discardableResult
    func recordMarketCashEvent(
        account: Account,
        type: AccountEventType,
        amount: Decimal,
        date: Date = Date(),
        note: String? = nil
    ) throws -> AccountEvent {
        guard account.kind == .marketInvestment, type == .dividend || type == .fee else {
            throw AccountsCoreServiceError.unsupportedEventType(type)
        }
        let event = AccountEvent(account: account, date: date, type: type, amount: amount, note: note)
        modelContext.insert(event)
        try modelContext.save()
        return event
    }

    // MARK: - Ручной актив (Фаза 4): переоценка

    /// Переоценка ручного актива — `revaluation` фиксирует НОВУЮ полную стоимость (не дельту),
    /// движок F (`AccountBalanceEngine.manualAssetBalance`) берёт последнюю ≤ дате реплея.
    @discardableResult
    func revalue(account: Account, newValue: Decimal, date: Date = Date(), note: String? = nil) throws -> AccountEvent {
        guard account.kind == .manualAsset else { throw AccountsCoreServiceError.unsupportedEventType(.revaluation) }
        let event = AccountEvent(account: account, date: date, type: .revaluation, amount: newValue, note: note)
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

    // MARK: - Проценты по вкладу (Фаза 3): идемпотентная запись отдельно от upsertEvent

    /// Идемпотентная запись/обновление interest-события генератора (`DepositInterestScheduler`) по
    /// `sourceTransactionID`. Отдельно от `upsertEvent` (тот ограничен income/expense/adjustment —
    /// мост Cashflow), т.к. проценты вклада порождаются генератором расписания, а не транзакцией Cashflow.
    @discardableResult
    func upsertInterestEvent(
        sourceTransactionID: String,
        account: Account,
        amount: Decimal,
        date: Date
    ) throws -> AccountEvent {
        let descriptor = FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == sourceTransactionID }
        )
        let existing = try? modelContext.fetch(descriptor).first

        let event: AccountEvent
        if let existing {
            existing.account = account
            existing.typeRaw = AccountEventType.interest.rawValue
            existing.amount = amount
            existing.setDate(date)
            event = existing
        } else {
            event = AccountEvent(account: account, date: date, type: .interest, amount: amount, sourceTransactionID: sourceTransactionID)
            modelContext.insert(event)
        }
        invalidateCache(for: account, from: date)
        try modelContext.save()
        return event
    }

    /// Точка входа для внешних генераторов событий (`DepositInterestScheduler`), которые правят ленту
    /// НАПРЯМУЮ через `ModelContext` (удаление будущих сгенерированных interest-событий), минуя
    /// `recordEvent`/`upsertEvent`. Не делает save — вызывающий код сам решает, когда сохранять пачку.
    func invalidateSnapshotCache(for account: Account, from date: Date) {
        invalidateCache(for: account, from: date)
    }

    /// Досрочное закрытие вклада (спека §2.7 п.5, брифинг Фазы 3, п.3): НЕ удаление — последовательность
    /// событий + архивация (AC7), история сохраняется. Если предусмотрен `earlyClosePenalty` — сторно-событие
    /// `.fee` на долю начисленных % (0…1, см. докстринг `DepositMeta.earlyClosePenalty`); остаток переводится
    /// на `destination` (двуногий transfer); будущие сгенерированные interest-события удаляются (вклад закрыт,
    /// им больше не наступить); в конце — архивация счёта.
    @discardableResult
    func earlyCloseDeposit(
        _ account: Account,
        transferTo destination: Account,
        on date: Date = Date()
    ) throws -> AccountEvent? {
        guard account.kind == .deposit else {
            throw AccountsCoreServiceError.unsupportedEventType(.adjustment)
        }

        invalidateCache(for: account, from: date)
        try DepositInterestScheduler.deleteGeneratedInterestEvents(for: account, after: date, context: modelContext)

        // ВАЖНО: читаем ленту ЯВНЫМ фетчем, не через `account.events` — в пределах одной несохранённой
        // транзакции relationship-массив ненадёжен (эмпирически: два последовательных чтения
        // `account.events` в этом же методе давали РАЗНЫЙ состав). Один фетч в начале + ручной
        // append только что созданного penalty-события — детерминированно.
        let accountID = account.id
        let eventsDescriptor = FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.account?.id == accountID }
        )
        var currentEvents = (try? modelContext.fetch(eventsDescriptor)) ?? (account.events ?? [])

        var penaltyEvent: AccountEvent?
        if let penaltyShare = account.depositMeta?.earlyClosePenalty, penaltyShare > 0 {
            let accruedInterest = currentEvents
                .filter { $0.type == .interest && $0.date <= date }
                .reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
            let penaltyAmount = accruedInterest * penaltyShare
            if penaltyAmount > 0 {
                let event = AccountEvent(account: account, date: date, type: .fee, amount: penaltyAmount, note: "early_close_penalty")
                modelContext.insert(event)
                currentEvents.append(event)
                penaltyEvent = event
            }
        }

        let balanceBeforeTransfer = AccountBalanceEngine.balanceAt(events: currentEvents, kind: .deposit, on: date)

        if balanceBeforeTransfer > 0 {
            _ = try transfer(from: account, to: destination, amountInSourceCurrency: balanceBeforeTransfer, date: date, note: "early_close_transfer")
        }

        try archiveAccount(account, on: date)
        return penaltyEvent
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

    // MARK: - Правка метаданных счёта (rename / группа / заметка / мета)

    /// Правит «карточку» счёта: имя, группу, заметку и meta-структуру своего kind. Это НЕ событие,
    /// а прямая мутация полей — по тому же принципу, что `archiveAccount` (архив тоже поле `archivedAt`,
    /// не событие): имя/группа/мета не имеют временной балансовой семантики и не участвуют в реплее
    /// `balanceAt`, поэтому событие им не нужно (создавать «rename-событие» = абстракция на будущее,
    /// новый `AccountEventType` + правки backup-схемы + обработка реплея — на ровном месте).
    ///
    /// ВАЛЮТА НАМЕРЕННО НЕ МЕНЯЕТСЯ (инвариант 8 плана 5c.7): суммы всех событий уже зафиксированы в
    /// валюте счёта — молчаливая подмена `currency` переинтерпретировала бы всю историю (100 000 RUB
    /// прочиталось бы как 100 000 USD = порча данных). Смена валюты — отдельное revalue-событие с явной
    /// конвертацией, вне скоупа этого API; поэтому параметра валюты здесь нет намеренно.
    ///
    /// Снапшот-кэш НЕ инвалидируется намеренно: `AccountDailySnapshot` ключёван по счёту (не по группе),
    /// групповой тотал считается на чтении из живого `account.group` — смена имени/группы/меты баланс и
    /// снапшоты счёта не затрагивает, инвалидация была бы no-op со сносом валидного кэша (инвариант
    /// `Total(Groups)==Total(Accounts)` держит тест смены группы через этот метод).
    ///
    /// Семантика параметров: `name`/`group`/`note` — желаемое итоговое значение (полная замена,
    /// `group == nil` = «Без группы»); meta-структуры — патч (`nil` = не трогать существующую), вызывающий
    /// код передаёт только meta своего kind.
    @discardableResult
    func updateAccount(
        _ account: Account,
        name: String,
        group: AccountGroup?,
        note: String? = nil,
        cardMeta: CardMeta? = nil,
        depositMeta: DepositMeta? = nil,
        loanMeta: LoanMeta? = nil,
        debtMeta: DebtMeta? = nil,
        marketMeta: MarketMeta? = nil,
        manualAssetMeta: ManualAssetMeta? = nil
    ) throws -> Account {
        account.name = name
        account.group = group
        account.note = note
        if let cardMeta { account.cardMeta = cardMeta }
        if let depositMeta { account.depositMeta = depositMeta }
        if let loanMeta { account.loanMeta = loanMeta }
        if let debtMeta { account.debtMeta = debtMeta }
        if let marketMeta { account.marketMeta = marketMeta }
        if let manualAssetMeta { account.manualAssetMeta = manualAssetMeta }
        try modelContext.save()
        return account
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

    // MARK: - Физическое удаление (экран «Архив» ТОЛЬКО, AC7)

    /// Безвозвратно удаляет счёт вместе с его событиями/снапшотами (SwiftData `.cascade`).
    /// ОБЯЗАТЕЛЬНО перед каскадом чинит инвариант Σ переводов = 0 (S2, риск плана): нога перевода
    /// на ВЫЖИВШЕМ счёте не может остаться привязанной к `transferID`, у которого вторая нога сейчас
    /// улетит вместе с удалённым счётом — иначе баланс выжившего счёта продолжит включать сумму,
    /// «прилетевшую в никуда». Конвертируем такую ногу в обычное income/expense-событие с пометкой
    /// в `note`, `transferID` сбрасываем — деньги остаются на выжившем счёте, но это уже не перевод.
    /// Единственная точка вызова — экран «Архив» (см. `ArchivedAccountsView`), проверено grep-гейтом
    /// (задача 2 брифинга Фазы 5): нигде больше в UI `modelContext.delete(Account)` не зовётся.
    func physicallyDelete(_ account: Account) throws {
        let accountID = account.id
        let ownEvents = try modelContext.fetch(
            FetchDescriptor<AccountEvent>(predicate: #Predicate<AccountEvent> { $0.account?.id == accountID })
        )

        let transferIDs = Set(ownEvents.compactMap(\.transferID))
        if !transferIDs.isEmpty {
            // #Predicate плохо дружит с `Set.contains` на опциональном UUID (SwiftData macro-ограничение) —
            // фетчим все события с непустым transferID и фильтруем множеством в памяти. Датасет переводов
            // конкретного счёта мал (не вся база), это дешевле, чем N отдельных запросов по одному transferID.
            let legsDescriptor = FetchDescriptor<AccountEvent>(
                predicate: #Predicate<AccountEvent> { $0.transferID != nil }
            )
            let allLegs = try modelContext.fetch(legsDescriptor).filter { leg in
                guard let legTransferID = leg.transferID else { return false }
                return transferIDs.contains(legTransferID)
            }
            var earliestBySurvivor: [UUID: Date] = [:]

            for leg in allLegs {
                // Пропускаем ноги самого удаляемого счёта — они уйдут каскадом ниже.
                guard let legAccount = leg.account, legAccount.id != accountID else { continue }

                // Конвертация: transferIn → income, transferOut → expense (сохраняем знак движения
                // денег на выжившем счёте — именно это отличает income/expense от произвольной суммы).
                leg.typeRaw = (leg.type == .transferIn ? AccountEventType.income : AccountEventType.expense).rawValue
                leg.transferID = nil
                let markerNote = String(format: L("accounts_core.archive.transfer_orphan_note"), account.name)
                leg.note = [leg.note, markerNote].compactMap { $0 }.joined(separator: " · ")

                earliestBySurvivor[legAccount.id] = min(earliestBySurvivor[legAccount.id] ?? leg.date, leg.date)
            }

            let survivorsByID = Dictionary(uniqueKeysWithValues: allLegs.compactMap { leg -> (UUID, Account)? in
                guard let legAccount = leg.account, legAccount.id != accountID else { return nil }
                return (legAccount.id, legAccount)
            })
            for (survivorID, earliestDate) in earliestBySurvivor {
                guard let survivor = survivorsByID[survivorID] else { continue }
                invalidateCache(for: survivor, from: earliestDate)
            }
        }

        modelContext.delete(account) // каскад .cascade удалит events + snapshots самого счёта
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
