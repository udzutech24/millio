import Foundation

/// Кэш баланса «сегодня» для строк списка счетов: один реплей ленты событий на цикл загрузки
/// вместо реплея на каждый проход body каждой строки.
///
/// Зачем: `AccountBalanceEngine.balanceAt` стоит ~2.3 мс на счёт (Ф0, 62 счёта × 30–200 событий),
/// а один проход body экрана «Счета» звал его дважды на строку — 452 мс при бюджете кадра 16.7 мс.
///
/// Почему кэш не может протухнуть: валидность привязана не к «нам сказали обновиться», а к
/// отпечатку ревизий самого счёта (`AccountRevisionStamp`). Их бампит КАЖДЫЙ писатель ленты —
/// список аудируется в `HistoricalValuationWriterInventory`. Запись, о которой экран не узнал,
/// сдвигает отпечаток, значение считается промахом и честно пересчитывается. То есть промах
/// деградирует ровно в то поведение, что было до кэша, а не в неверную цифру на экране.
struct AccountBalanceCache {

    /// Отпечаток ревизий, на которых посчитано значение. Три измерения, а не только `events`:
    /// знаковый вклад строки зависит ещё от `creditLimit` и `kind`, а их правит `updateAccount`,
    /// который бампит `.financial`/`.accountSet`, но НЕ `.events`.
    struct Stamp: Equatable {
        let membership: Int64
        let financial: Int64
        let events: Int64

        init(_ account: Account) {
            membership = account.valuationMembershipRevision ?? 0
            financial = account.valuationFinancialRevision ?? 0
            events = account.valuationEventRevision ?? 0
        }
    }

    private struct Entry {
        let stamp: Stamp
        let value: Decimal
    }

    private var entries: [UUID: Entry] = [:]
    /// Начало суток, на которые посчитан срез. Баланс — величина «на сегодня»: приложение,
    /// пережившее полночь с открытым экраном, обязано пересчитать, а не показывать вчерашнее
    /// (у вкладов есть события, датированные будущим).
    private var day: Date?

    /// Число закэшированных счетов — для тестов и диагностики.
    var count: Int { entries.count }

    /// Пересчёт среза. Вызывается ТОЛЬКО вне тела View (цикл загрузки), поэтому мутация здесь
    /// безопасна: чтение из body (`value(for:today:)`) ничего не мутирует.
    mutating func rebuild(accounts: [Account], today: Date, compute: (Account) -> Decimal) {
        var fresh: [UUID: Entry] = [:]
        fresh.reserveCapacity(accounts.count)
        for account in accounts {
            fresh[account.id] = Entry(stamp: Stamp(account), value: compute(account))
        }
        entries = fresh
        day = Calendar.current.startOfDay(for: today)
    }

    /// Готовое значение или `nil` — промах. Промах обязан обрабатываться реплеем на месте вызова:
    /// молча вернуть 0 значило бы показать неверную цифру.
    func value(for account: Account, today: Date) -> Decimal? {
        guard let day, Calendar.current.startOfDay(for: today) == day else { return nil }
        guard let entry = entries[account.id], entry.stamp == Stamp(account) else { return nil }
        return entry.value
    }

    /// Точечный сброс одного счёта. Отпечаток ревизий уже покрывает штатные правки, но прямая
    /// мутация ленты в обход бампа (или откат транзакции) чинится только явным сбросом.
    mutating func invalidate(_ accountID: UUID) {
        entries.removeValue(forKey: accountID)
    }
}
