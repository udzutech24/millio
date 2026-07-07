//
//  CashflowCategoryCapPolicy.swift
//  millio
//

import Foundation

/// Политика cap-сетки избранных категорий в форме добавления (Фаза 2 редизайна
/// add-flow, §2.2 плана `2026-07-05__cashflow-add-transaction-redesign.md`).
///
/// Чистая функция без UI/state: сколько категорий показывать свёрнуто, при условии,
/// что вызывающая сторона уже отсортировала список pinned-first (инвариант
/// `CashflowCategoryService.orderedCategoryOptions`).
enum CashflowCategoryCapPolicy {
    /// Минимум плиток в свёрнутом виде, если запиненных категорий меньше — добираем дефолтными.
    static let minimumVisible = 6
    /// Жёсткий потолок даже для pinned (R4 плана) — иначе теряется смысл компактной сетки.
    static let maximumVisible = 8

    /// - Parameters:
    ///   - pinnedCount: сколько категорий из начала уже отсортированного списка запинены.
    ///   - totalCount: общее число категорий в каталоге (после поиска, если применимо).
    /// - Returns: сколько элементов показывать в свёрнутом виде, `0...totalCount`.
    static func visibleCount(pinnedCount: Int, totalCount: Int) -> Int {
        guard totalCount > 0 else { return 0 }
        let target = pinnedCount >= minimumVisible ? pinnedCount : minimumVisible
        return min(target, maximumVisible, totalCount)
    }
}
