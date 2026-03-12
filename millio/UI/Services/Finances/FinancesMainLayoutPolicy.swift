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
    static let sectionSpacing: CGFloat = 18
    static let horizontalPadding: CGFloat = 18
    static let heroCornerRadius: CGFloat = 26
    static let sectionCardCornerRadius: CGFloat = 22
    static let fabDiameter: CGFloat = 52
    static let fabIconSize: CGFloat = 20
    static let fabTrailingPadding: CGFloat = 20
    /// FAB должен висеть непосредственно над tab bar, а не в середине пустого пространства.
    static let fabBottomPadding: CGFloat = 28

    static func showsAddFAB(visibleGroupsCount: Int) -> Bool {
        visibleGroupsCount > 0
    }

    static func scrollContentBottomPadding(showsAddFAB: Bool) -> CGFloat {
        showsAddFAB ? 92 : 28
    }
}
