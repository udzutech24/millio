//
//  CashflowCategoryGridLayout.swift
//  millio
//

import SwiftUI

/// Единая политика сетки категорий для экранов создания дохода/расхода.
/// Базовая сетка — 3 колонки (компактная плитка: иконка · имя · сумма).
/// На очень узких экранах (<280 pt) падаем до 2 колонок, иначе имя категории
/// схлопывается до нечитаемого.
struct CashflowCategoryGridLayout {
    enum PinAffordanceStyle {
        case hidden
        case compactBadge
        case regularButton
    }

    static let compactColumns = 2
    static let regularColumns = 3
    static let compactWidthThreshold: CGFloat = 280
    static let columnSpacing: CGFloat = 10
    static let unifiedCardMinHeight: CGFloat = 100
    static let unifiedTopRowMinHeight: CGFloat = 24
    static let unifiedFooterMinHeight: CGFloat = 18

    static func columnCount(
        for kind: CashflowCategoryTransactionSheetKind,
        containerWidth: CGFloat
    ) -> Int {
        containerWidth < compactWidthThreshold ? compactColumns : regularColumns
    }

    static func columns(
        for kind: CashflowCategoryTransactionSheetKind,
        containerWidth: CGFloat
    ) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: columnSpacing),
            count: columnCount(for: kind, containerWidth: containerWidth)
        )
    }

    /// Для обеих сеток не засоряем карточки пустыми пинами:
    /// unpinned скрыты, pinned получают компактный badge.
    static func pinAffordanceStyle(
        for kind: CashflowCategoryTransactionSheetKind,
        isPinned: Bool
    ) -> PinAffordanceStyle {
        switch kind {
        case .expense:
            return isPinned ? .compactBadge : .hidden
        case .income:
            return isPinned ? .compactBadge : .hidden
        }
    }

}
