import Foundation

/// Проактивная подсказка по вкладу. Движок решает ЧТО сказать и с какими числами; формулировку
/// даёт слой представления заготовленным локализованным текстом (`DepositNudge+Text`).
enum DepositNudge: Equatable, Identifiable, Sendable {
    /// Срок подходит к концу — осталось `daysRemaining` дней.
    case maturityApproaching(daysRemaining: Int)
    /// Срок вышел `daysSinceMaturity` дней назад, деньги всё ещё лежат на вкладе.
    case maturedNeedsAction(daysSinceMaturity: Int)
    /// В условиях включена пролонгация, но приложение вклад само не продлевает
    /// (`DepositCapabilities.autoRolloverIsOperational` == false) — иначе человек ждёт от нас того,
    /// чего мы не делаем.
    case rolloverIsManual
    /// Срок у вклада есть, а напоминание о его конце выключено.
    case reminderOff

    var id: String {
        switch self {
        case .maturityApproaching: "maturity_approaching"
        case .maturedNeedsAction: "matured_needs_action"
        case .rolloverIsManual: "rollover_is_manual"
        case .reminderOff: "reminder_off"
        }
    }
}

/// Движок подсказок по вкладу — целиком на устройстве, без сети. Работает поверх уже посчитанного
/// `DepositPresentationSnapshot`: своих денежных расчётов не делает и в стор не ходит.
enum DepositNudgeEngine {
    static func nudges(
        snapshot: DepositPresentationSnapshot,
        meta: DepositMeta?,
        calendarPolicy: DepositCalendarPolicy
    ) -> [DepositNudge] {
        guard let meta else { return [] }

        switch snapshot.lifecycleState {
        // `.openEnded` — это накопительный счёт (`termEnd == nil`): срока нет, значит нет ни
        // «скоро конец», ни напоминания, ни пролонгации. `.active` — до конца больше 30 дней,
        // подсказывать рано. `.closed` / `.incomplete` — говорить не о чем.
        case .openEnded, .active, .closed, .incomplete:
            return []

        case .dueSoon:
            var result: [DepositNudge] = [
                .maturityApproaching(daysRemaining: snapshot.daysRemaining ?? 0)
            ]
            if meta.autoRollover { result.append(.rolloverIsManual) }
            if !meta.remindEnd { result.append(.reminderOff) }
            return result

        case .maturedNeedsAction:
            // Напоминание после срока уже бессмысленно — предлагаем только действие и честную
            // оговорку про пролонгацию.
            var result: [DepositNudge] = [
                .maturedNeedsAction(daysSinceMaturity: daysSinceMaturity(snapshot, calendarPolicy))
            ]
            if meta.autoRollover { result.append(.rolloverIsManual) }
            return result
        }
    }

    /// `snapshot.daysRemaining` после срока всегда 0 (`DepositCalendarPolicy.daysRemaining`
    /// клэмпится в неотрицательные) — «сколько дней прошло» считаем отдельно.
    private static func daysSinceMaturity(
        _ snapshot: DepositPresentationSnapshot,
        _ calendarPolicy: DepositCalendarPolicy
    ) -> Int {
        guard let maturity = snapshot.maturityDate else { return 0 }
        return calendarPolicy.daysRemaining(from: maturity, to: snapshot.asOf)
    }
}
