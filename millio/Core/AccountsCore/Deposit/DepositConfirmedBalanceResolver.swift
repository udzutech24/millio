import Foundation

/// Единственное определение «подтверждённого» баланса вклада: прогнозные начисления,
/// сгенерированные `DepositInterestScheduler`, в баланс не входят (план
/// `2026-08-26__deposit-confirmed-balance-unification.md`, Ф1).
///
/// До этого резолвера конвенция префикса `deposit-interest:` была продублирована в шести местах,
/// и «текущий баланс» существовал в двух несовпадающих версиях: сырой реплей ленты (список,
/// тоталы, снапшоты) и confirmed-путь `DepositFinancialContract`.
enum DepositConfirmedBalanceResolver {

    /// Конвенция идентификатора прогнозного начисления — см. `DepositInterestScheduler.sourceTransactionID`.
    private static let generatedInterestPrefix = "deposit-interest:"

    /// Признак прогнозного (ещё не подтверждённого) начисления процентов.
    /// Защиты на уровне данных нет — признак только в `sourceTransactionID`.
    static func isGeneratedInterest(_ event: AccountEvent, accountID: UUID) -> Bool {
        guard event.type == .interest, let sourceID = event.sourceTransactionID else { return false }
        return sourceID.hasPrefix("\(generatedInterestPrefix)\(accountID.uuidString):")
    }

    /// Лента событий, пригодная для расчёта баланса. Для не-вклада возвращается как есть:
    /// прогнозы бывают только у вкладов (аудит 2026-08-27 — все 442 прогнозных события
    /// принадлежат счетам `kind == .deposit`), а вызов идёт в горячем цикле серии «Динамики»
    /// (день × счёт), где лишний скан строк на 50 счетах платить не за что.
    /// Фильтровать нужно ОДИН раз на счёт, а не на каждую дату реплея.
    static func confirmedEvents(_ events: [AccountEvent], accountID: UUID, kind: AccountKind) -> [AccountEvent] {
        guard kind == .deposit else { return events }
        return events.filter { !isGeneratedInterest($0, accountID: accountID) }
    }

    /// Подтверждённый баланс вклада на дату.
    ///
    /// Границу «в прошлом» задаёт сам движок (`event.date <= date`) — по ВРЕМЕНИ, а не по dayKey:
    /// при ежедневной капитализации сегодняшнее, ещё не наступившее начисление иначе попало бы
    /// в баланс уже с утра.
    ///
    /// `confirmedInterestDays` из `DepositFinancialContract` сюда намеренно НЕ копируется —
    /// он влияет только на выборку прогнозов (`eligibleGenerated`), и как фильтр баланса дал бы
    /// третью, ещё одну неверную цифру.
    static func balanceAt(events: [AccountEvent], accountID: UUID, on date: Date) -> Decimal {
        AccountBalanceEngine.balanceAt(
            events: confirmedEvents(events, accountID: accountID, kind: .deposit),
            kind: .deposit,
            on: date
        )
    }
}
