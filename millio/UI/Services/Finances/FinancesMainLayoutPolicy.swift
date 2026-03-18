//
//  FinancesMainLayoutPolicy.swift
//  millio
//

import SwiftUI

/// Политика компоновки экрана «Финансы».
///
/// Важное поведение: когда список продуктов пуст, нижние подсказки/доп. контент не должны
/// выталкивать CTA «Добавить продукт» к самому низу (и тем более под таббар/поверх него).
enum FinancesMainLayoutPolicy {
    static let sectionSpacing: CGFloat = 16
    static let horizontalPadding: CGFloat = 16
    static let heroCornerRadius: CGFloat = FinanceScreenChrome.heroCornerRadius
    static let sectionCardCornerRadius: CGFloat = FinanceScreenChrome.sectionCornerRadius
    static let groupRowChevronSize: CGFloat = 24
    static let groupRowAmountMinWidth: CGFloat = 110
    static let groupRowAmountMaxWidth: CGFloat = 126
    static let groupRowNameFadeStart: CGFloat = 0.90
    static let groupRowNameFadeEnd: CGFloat = 0.98
    static let fabDiameter: CGFloat = FinanceScreenChrome.fabDiameter
    static let fabIconSize: CGFloat = FinanceScreenChrome.fabIconSize
    static let fabTrailingPadding: CGFloat = 20
    /// FAB должен висеть непосредственно над tab bar, а не в середине пустого пространства.
    static let fabBottomPadding: CGFloat = 28
    static let scrollBottomPaddingWithoutFAB: CGFloat = 28

    static func showsAddFAB(visibleGroupsCount: Int) -> Bool {
        visibleGroupsCount > 0
    }

    static func scrollContentBottomPadding(showsAddFAB: Bool) -> CGFloat {
        // Привязываем отступ к реальным размерам FAB, чтобы не было "пустой пропасти".
        // Раньше это был магический 92, который на некоторых девайсах визуально ронял экран слишком низко.
        showsAddFAB ? (fabDiameter + fabBottomPadding) : scrollBottomPaddingWithoutFAB
    }

    static func groupRowAmountWidth(containerWidth: CGFloat) -> CGFloat {
        let normalizedWidth = max(320, containerWidth)
        let preferredWidth = normalizedWidth * 0.31
        return min(max(preferredWidth, groupRowAmountMinWidth), groupRowAmountMaxWidth)
    }
}
