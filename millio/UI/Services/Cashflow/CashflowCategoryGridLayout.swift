//
//  CashflowCategoryGridLayout.swift
//  millio
//

import SwiftUI

/// Единая политика сетки категорий для экранов создания дохода/расхода.
/// На узких экранах обе сетки переключаются на 3 колонки, чтобы размещение
/// категорий в доходах и расходах оставалось консистентным. Для расходов с
/// лимитами делаем это раньше, потому что карточки становятся плотнее.
struct CashflowCategoryGridLayout {
    struct CardMetrics {
        let topRowMinHeight: CGFloat
        let contentSpacing: CGFloat
        let titleMinHeight: CGFloat
        let cardMinHeight: CGFloat
        let verticalPadding: CGFloat
        let amountTopPadding: CGFloat
        let usesFlexibleSpacer: Bool
        let footerMinHeight: CGFloat
    }

    enum PinAffordanceStyle {
        case hidden
        case compactBadge
        case regularButton
    }

    enum PinPlacement {
        case hidden
        case inlineBadge
        case overlayButton
    }

    static let compactColumns = 2
    static let regularColumns = 2
    static let compactWidthThreshold: CGFloat = 280
    static let budgetCompactWidthThreshold: CGFloat = 280
    static let columnSpacing: CGFloat = 10
    static let unifiedCardMinHeight: CGFloat = 100
    static let unifiedTopRowMinHeight: CGFloat = 24
    static let unifiedFooterMinHeight: CGFloat = 18

    static func columnCount(
        for kind: CashflowCategoryTransactionSheetKind,
        containerWidth: CGFloat,
        showsBudgetDetails: Bool = false
    ) -> Int {
        if showsBudgetDetails, containerWidth < budgetCompactWidthThreshold {
            return compactColumns
        }
        if containerWidth < compactWidthThreshold {
            return compactColumns
        }
        return regularColumns
    }

    static func columns(
        for kind: CashflowCategoryTransactionSheetKind,
        containerWidth: CGFloat,
        showsBudgetDetails: Bool = false
    ) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: columnSpacing),
            count: columnCount(
                for: kind,
                containerWidth: containerWidth,
                showsBudgetDetails: showsBudgetDetails
            )
        )
    }

    static func cardMetrics(showsBudgetDetails: Bool) -> CardMetrics {
        if showsBudgetDetails {
            return CardMetrics(
                topRowMinHeight: unifiedTopRowMinHeight,
                contentSpacing: 5,
                titleMinHeight: 20,
                cardMinHeight: unifiedCardMinHeight,
                verticalPadding: 10,
                amountTopPadding: 0,
                usesFlexibleSpacer: true,
                footerMinHeight: unifiedFooterMinHeight
            )
        }

        return CardMetrics(
            topRowMinHeight: unifiedTopRowMinHeight,
            contentSpacing: 5,
            titleMinHeight: 20,
            cardMinHeight: unifiedCardMinHeight,
            verticalPadding: 10,
            amountTopPadding: 2,
            usesFlexibleSpacer: false,
            footerMinHeight: unifiedFooterMinHeight
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

    static func pinPlacement(for style: PinAffordanceStyle) -> PinPlacement {
        switch style {
        case .hidden:
            return .hidden
        case .compactBadge:
            return .inlineBadge
        case .regularButton:
            return .overlayButton
        }
    }
}
