//
//  CashflowBreakdownCapPolicy.swift
//  millio
//

import Foundation

/// Политика cap-а развёрнутого списка категорий Доходы/Расходы на главном экране
/// Cashflow (Фаза 4 редизайна add-flow, §2.4 плана
/// `2026-07-05__cashflow-add-transaction-redesign.md`). Сортировка по убыванию суммы
/// уже сделана на уровне `CashflowAnalyticsService` — здесь только выбор top-N и
/// признак того, нужна ли ссылка "Показать всё".
enum CashflowBreakdownCapPolicy {
    static let visibleEntryCount = 3

    static func visibleEntries<T>(from entries: [T]) -> [T] {
        Array(entries.prefix(visibleEntryCount))
    }

    /// R6: пустой список (0 записей) не показывает ссылку — нечего раскрывать.
    static func showsExpandLink(totalCount: Int) -> Bool {
        totalCount > visibleEntryCount
    }
}
