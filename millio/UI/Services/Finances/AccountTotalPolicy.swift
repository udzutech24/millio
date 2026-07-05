//
//  AccountTotalPolicy.swift
//  millio
//
//  Единый источник правды для вопроса "включать ли legacy-счёт (Card/Credit/Investment)
//  в общий баланс и с каким знаком". До появления этого файла одна и та же логика была
//  продублирована в FinanceDynamicsViewModel (заголовок «Динамика») и FinanceTotalsService
//  (Дашборд, экран «Счета»), из-за чего экраны расходились в цифрах — см.
//  plans/2026-07-05__unified-totals.md.
//

import Foundation

/// Политика участия legacy-счёта в net-total. Считает ТОЛЬКО решение "включать/знак" —
/// сама сумма (текущий баланс vs исторический replay) остаётся за вызывающей стороной.
enum AccountTotalPolicy {

    /// Активен ли счёт на дату `date` для целей подсчёта тотала.
    /// Правило: включён флагом `includeInTotal` И (не архивирован ИЛИ архивирован строго позже `date`).
    /// `date > archivedAt` — счёт архивирован раньше или в момент запрашиваемой даты, значит уже не участвует;
    /// это делает архивацию time-aware: точки истории ДО архивации по-прежнему включают счёт.
    static func isActive(includeInTotal: Bool, archivedAt: Date?, at date: Date) -> Bool {
        guard includeInTotal else { return false }
        if let archivedAt, date > archivedAt { return false }
        return true
    }

    /// Применяет знак liability-счёта (кредит, кредитная карта) к уже сконвертированной сумме.
    /// При `debtAsNegative == false` (например, просмотр одного счёта "как есть") знак не трогаем —
    /// пользователь смотрит на величину долга, а не на её вклад в net worth.
    static func signedContribution(_ amount: Double, isLiability: Bool, debtAsNegative: Bool) -> Double {
        guard debtAsNegative, isLiability else { return amount }
        return -abs(amount)
    }
}
