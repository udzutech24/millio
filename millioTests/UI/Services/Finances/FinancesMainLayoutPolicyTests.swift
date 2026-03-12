//
//  FinancesMainLayoutPolicyTests.swift
//  millioTests
//

import CoreGraphics
import Testing
@testable import millio

@Suite
struct FinancesMainLayoutPolicyTests {
    @Test("FAB отображается только когда есть группы")
    func showsAddFABDependsOnGroupsCount() {
        #expect(FinancesMainLayoutPolicy.showsAddFAB(visibleGroupsCount: 0) == false)
        #expect(FinancesMainLayoutPolicy.showsAddFAB(visibleGroupsCount: 1) == true)
        #expect(FinancesMainLayoutPolicy.showsAddFAB(visibleGroupsCount: 10) == true)
    }

    @Test("Нижний отступ контента меньше когда FAB скрыт")
    func scrollBottomPaddingIsSmallerWhenFABIsHidden() {
        let paddingWithFAB = FinancesMainLayoutPolicy.scrollContentBottomPadding(showsAddFAB: true)
        let paddingWithoutFAB = FinancesMainLayoutPolicy.scrollContentBottomPadding(showsAddFAB: false)

        #expect(paddingWithFAB > paddingWithoutFAB)
        #expect(paddingWithoutFAB > CGFloat.zero)
        #expect(paddingWithFAB == 92)
        #expect(paddingWithoutFAB == 28)
    }

    @Test("Главный экран использует компактный FAB и согласованные отступы")
    func financeMainUsesSharedSpacingConstants() {
        #expect(FinancesMainLayoutPolicy.sectionSpacing == 18)
        #expect(FinancesMainLayoutPolicy.horizontalPadding == 18)
        #expect(FinancesMainLayoutPolicy.heroCornerRadius == 26)
        #expect(FinancesMainLayoutPolicy.sectionCardCornerRadius == 22)
        #expect(FinancesMainLayoutPolicy.fabDiameter == 52)
        #expect(FinancesMainLayoutPolicy.fabIconSize == 20)
        #expect(FinancesMainLayoutPolicy.fabTrailingPadding == 20)
        #expect(FinancesMainLayoutPolicy.fabBottomPadding == 28)
    }
}
