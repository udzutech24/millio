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
    static func showsAddFAB(visibleGroupsCount: Int) -> Bool {
        visibleGroupsCount > 0
    }

    static func scrollContentBottomPadding(showsAddFAB: Bool) -> CGFloat {
        showsAddFAB ? 100 : 24
    }
}

