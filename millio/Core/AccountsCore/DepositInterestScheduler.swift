import Foundation
import SwiftData

/// Генератор interest-событий вклада/накопительного счёта по расписанию капитализации
/// (спека §2.7/2.8, план `2026-07-04__accounts-core-rebuild-plan.md`, Фаза 3). Прогнозы карточки
/// («в месяц»/«за срок») — это `AccountBalanceEngine.balanceAt(futureDate)` на уже сгенерированных
/// событиях, отдельного калькулятора прогнозов нет: генератор один раз кладёт события в ленту,
/// дальше реплей естественно компаундит (каждое interest увеличивает базу следующего периода).
enum DepositInterestScheduler {

    /// На сколько месяцев вперёд генерируем расписание БЕССРОЧНОГО вклада/накопительного счёта
    /// (`termEnd == nil`) — «догенерация роллингом» при старте/открытии (брифинг Фазы 3, п.2).
    static let perpetualHorizonMonths = 12

    /// Идемпотентный ключ interest-события генератора (риск Т4 плана): один и тот же период всегда
    /// маппится в один и тот же `sourceTransactionID` — повторный запуск не плодит дубликаты (upsert).
    static func sourceTransactionID(accountID: UUID, dayKey: String) -> String {
        "deposit-interest:\(accountID.uuidString):\(dayKey)"
    }

    private static func generatedPrefix(accountID: UUID) -> String {
        "deposit-interest:\(accountID.uuidString):"
    }

    /// Роллинг-догенерация горизонта ДЛЯ ВСЕХ активных вкладов (план `2026-07-05__cashflow-add-transaction-redesign.md`,
    /// Фаза 0). До этого метода `regenerateFutureInterestEvents` вызывался ТОЛЬКО при создании/правке
    /// счёта — бессрочный вклад (`termEnd == nil`) получал события лишь на первые `perpetualHorizonMonths`
    /// от даты создания и НИКОГДА больше, если пользователь не открывал экран правки счёта. Через год
    /// начисления молча прекратились бы — тот же класс бага «доход невидим», что чинит эта фаза, просто
    /// отложенно. Вызывается из Cashflow-моста при каждой загрузке таба.
    /// Архивные (закрытые) счета исключены — досрочно закрытому вкладу новые проценты не начисляются.
    @discardableResult
    @MainActor
    static func extendActiveDepositHorizons(
        context: ModelContext,
        asOf: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Int {
        let depositKindRaw = AccountKind.deposit.rawValue
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.kindRaw == depositKindRaw && $0.archivedAt == nil }
        )
        guard let accounts = try? context.fetch(descriptor), !accounts.isEmpty else { return 0 }

        // Один фетч всех interest-событий вместо запроса на каждый счёт в цикле.
        let allInterestEvents = ((try? context.fetch(FetchDescriptor<AccountEvent>())) ?? [])
            .filter { $0.type == .interest }

        let service = AccountsCoreService(modelContext: context)
        var totalGenerated = 0
        for account in accounts {
            let latestGeneratedDate = allInterestEvents
                .filter { $0.account?.id == account.id }
                .map(\.date)
                .max()

            // Горизонт ещё «здоровый» (последнее уже сгенерированное событие — в будущем относительно
            // `asOf`) — продлевать нечего, обычный случай почти на каждой загрузке таба. Резюмируем
            // регенерацию ТОЛЬКО когда горизонт исчерпан, и именно ОТ ТОЧКИ ПОСЛЕДНЕГО события, а не
            // от `asOf`: `regenerateFutureInterestEvents` считает всё `<= asOf` «уже случившимся» и
            // молча пропускает такие периоды — если резюмировать от `asOf`, а не от последнего известного
            // события, периоды, попавшие в разрыв между исчерпанным горизонтом и текущей датой (когда
            // `asOf` шагнул вперёд больше, чем на один горизонт разом), никогда не будут сгенерированы.
            guard latestGeneratedDate == nil || latestGeneratedDate! < asOf else { continue }
            let resumePoint = latestGeneratedDate ?? account.createdAt

            do {
                totalGenerated += try regenerateFutureInterestEvents(
                    for: account, service: service, asOf: resumePoint, calendar: calendar, context: context
                )
            } catch {
                AppLogger.log(.error, category: "AccountsCore", "Не удалось продлить горизонт вклада \(account.id): \(error)")
            }
        }
        return totalGenerated
    }

    /// Генерирует (при создании счёта) ИЛИ регенерирует (при правке ставки/срока/капитализации)
    /// БУДУЩИЕ interest-события вклада начиная строго ПОСЛЕ `asOf` — прошлые (≤ asOf) события НЕ
    /// трогает, они уже зафиксированы в реальной ленте (брифинг Фазы 3, п.2: «прошедшие ≤today не трогаются»).
    @discardableResult
    @MainActor
    static func regenerateFutureInterestEvents(
        for account: Account,
        service: AccountsCoreService,
        asOf: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian),
        context: ModelContext
    ) throws -> Int {
        guard account.kind == .deposit, let meta = account.depositMeta else { return 0 }

        service.invalidateSnapshotCache(for: account, from: asOf)
        try deleteGeneratedInterestEvents(for: account, after: asOf, context: context)

        let openingDate = account.createdAt
        let horizon = effectiveHorizon(meta: meta, asOf: asOf, calendar: calendar)
        guard horizon > asOf else { return 0 } // вклад уже закончился/заканчивается сегодня — генерировать нечего

        // Свежий фетч (не `account.events`, который в памяти мог не обновиться после удаления выше).
        let accountID = account.id
        let descriptor = FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.account?.id == accountID }
        )
        let existingEvents = (try? context.fetch(descriptor)) ?? (account.events ?? [])

        return try generate(
            account: account,
            meta: meta,
            openingDate: openingDate,
            existingEvents: existingEvents,
            after: asOf,
            horizon: horizon,
            service: service,
            calendar: calendar
        )
    }

    /// Удаляет СГЕНЕРИРОВАННЫЕ этим генератором (по конвенции `sourceTransactionID`) interest-события
    /// вклада с датой СТРОГО ПОЗЖЕ `after`. Прошлые и НЕ-сгенерированные события (ручной ввод, сид) не трогает.
    static func deleteGeneratedInterestEvents(for account: Account, after: Date, context: ModelContext) throws {
        let accountID = account.id
        let prefix = generatedPrefix(accountID: accountID)
        let descriptor = FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { event in
                event.account?.id == accountID && event.date > after
            }
        )
        let candidates = try context.fetch(descriptor)
        for event in candidates where event.type == .interest && (event.sourceTransactionID?.hasPrefix(prefix) ?? false) {
            context.delete(event)
        }
    }

    private static func effectiveHorizon(meta: DepositMeta, asOf: Date, calendar: Calendar) -> Date {
        if let termEnd = meta.termEnd {
            return termEnd
        }
        return calendar.date(byAdding: .month, value: perpetualHorizonMonths, to: asOf) ?? asOf
    }

    @MainActor
    private static func generate(
        account: Account,
        meta: DepositMeta,
        openingDate: Date,
        existingEvents: [AccountEvent],
        after asOf: Date,
        horizon: Date,
        service: AccountsCoreService,
        calendar: Calendar
    ) throws -> Int {
        var workingEvents = existingEvents
        var generated = 0

        switch meta.capitalization {
        case .none:
            // Простые проценты ОДНИМ начислением на дату окончания (брифинг Фазы 3, п.2):
            // opening × rate × дней_срока / 365. Без термина считать нечего (edge case — no-op).
            guard let termEnd = meta.termEnd, termEnd > asOf else { return 0 }
            guard let openingAmount = workingEvents.first(where: { $0.type == .openingBalance })?.amount else { return 0 }
            let days = calendar.dateComponents([.day], from: openingDate, to: termEnd).day ?? 0
            guard days > 0 else { return 0 }
            let interest = round2(openingAmount * meta.rate / 100 * Decimal(days) / 365)
            let dayKey = AccountEvent.dayKey(for: termEnd)
            let sourceID = sourceTransactionID(accountID: account.id, dayKey: dayKey)
            let event = try service.upsertInterestEvent(sourceTransactionID: sourceID, account: account, amount: interest, date: termEnd)
            workingEvents.append(event)
            generated = 1

        case .monthly, .quarterly:
            let stepMonths = meta.capitalization == .quarterly ? 3 : 1
            let periodRate = meta.capitalization == .quarterly ? meta.rate / 4 : meta.rate / 12
            var n = 1
            while true {
                guard let periodEnd = calendar.date(byAdding: .month, value: n * stepMonths, to: openingDate) else { break }
                if periodEnd > horizon { break }
                n += 1
                guard periodEnd > asOf else { continue } // прошлый период — не трогаем

                let balanceBefore = AccountBalanceEngine.balanceAt(events: workingEvents, kind: .deposit, on: periodEnd)
                let interest = round2(balanceBefore * periodRate / 100)
                guard interest != 0 else { continue }
                let dayKey = AccountEvent.dayKey(for: periodEnd)
                let sourceID = sourceTransactionID(accountID: account.id, dayKey: dayKey)
                let event = try service.upsertInterestEvent(sourceTransactionID: sourceID, account: account, amount: interest, date: periodEnd)
                workingEvents.append(event)
                generated += 1
            }
        }

        return generated
    }

    /// Округление процентов до копейки — ОБЫЧНОЕ (`.plain`, «половина вверх»), НЕ bankers rounding
    /// (брифинг Фазы 3, п.2: явное решение, не считаем банковское округление до чётной копейки).
    static func round2(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var mutable = value
        NSDecimalRound(&result, &mutable, 2, .plain)
        return result
    }
}
