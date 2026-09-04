import Foundation
import SwiftData

/// Ленивый перевод счёта `.loan` в детальный режим (спека Р5).
///
/// Счёт, заведённый старой формой, хранит условия в легаси `LoanMeta`. При первом открытии деталки
/// он получает `LoanContract`, собранный из меты через `LoanTermsResolver`. Обратной записи нет:
/// `LoanMeta` после этого только лежит, читать её продолжает исключительно резолвер.
///
/// Массового прохода по всем счетам нет намеренно — миграция «по требованию» не трогает счета,
/// которые пользователь ни разу не открыл, и её нечем сломать на старте приложения.
enum LoanContractBackfill {

    /// Договор счёта: существующий, либо только что собранный из легаси-меты. `nil` — условий нет
    /// ни там, ни там (счёт `.loan` без `LoanMeta`), и выдумывать их нечего.
    ///
    /// Идемпотентно: второй вызов возвращает уже созданный договор и ничего не пишет.
    @discardableResult
    static func ensureContract(
        for account: Account,
        context: ModelContext,
        now: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> LoanContract? {
        let store = LoanContractStore(context: context)
        if let existing = try store.contract(for: account.id) { return existing }
        guard account.kind == .loan else { return nil }
        guard let terms = LoanTermsResolver.terms(for: account, contract: nil, calendar: calendar) else { return nil }

        let progress = progressByCalendar(terms: terms, now: now, calendar: calendar)
        let contract = try store.upsert(accountID: account.id) { contract in
            contract.principal = terms.principal
            contract.annualRatePercent = terms.annualRatePercent
            contract.termPeriods = terms.termPeriods
            contract.firstPaymentDate = terms.firstPaymentDate
            contract.scheduleType = terms.scheduleType
            contract.frequency = terms.frequency
            contract.paymentOverride = terms.paymentOverride
            contract.paymentsMade = progress.paymentsMade
            contract.paidInterestTotal = progress.paidInterest
        }
        try context.save()
        return contract
    }

    /// Прогресс погашения старого счёта восстанавливается по КАЛЕНДАРЮ: сколько платежей по графику
    /// уже наступило к сегодняшнему дню. В легаси-мете факта платежей нет вообще, а `paymentsMade = 0`
    /// у кредита трёхлетней давности дал бы на экране «следующий платёж» из прошлого и полный срок
    /// впереди. Деньги при этом берутся не отсюда, а из ленты событий (Р6) — календарь восстанавливает
    /// только позицию в графике.
    private static func progressByCalendar(
        terms: LoanTerms,
        now: Date,
        calendar: Calendar
    ) -> (paymentsMade: Int, paidInterest: Decimal) {
        let schedule = LoanScheduleEngine.schedule(terms: terms, calendar: calendar)
        let elapsed = schedule.rows.filter { $0.date <= now }
        return (elapsed.count, elapsed.reduce(Decimal.zero) { $0 + $1.interest })
    }
}
