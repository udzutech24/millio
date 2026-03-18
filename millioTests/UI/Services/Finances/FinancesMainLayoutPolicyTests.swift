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
        #expect(paddingWithFAB == FinancesMainLayoutPolicy.fabDiameter + FinancesMainLayoutPolicy.fabBottomPadding)
        #expect(paddingWithoutFAB == FinancesMainLayoutPolicy.scrollBottomPaddingWithoutFAB)
    }

    @Test("Главный экран использует компактный FAB и согласованные отступы")
    func financeMainUsesSharedSpacingConstants() {
        #expect(FinancesMainLayoutPolicy.sectionSpacing == 16)
        #expect(FinancesMainLayoutPolicy.horizontalPadding == 16)
        #expect(FinancesMainLayoutPolicy.heroCornerRadius == 24)
        #expect(FinancesMainLayoutPolicy.sectionCardCornerRadius == 20)
        #expect(FinancesMainLayoutPolicy.groupRowChevronSize == 24)
        #expect(FinancesMainLayoutPolicy.groupRowAmountMinWidth == 110)
        #expect(FinancesMainLayoutPolicy.groupRowAmountMaxWidth == 126)
        #expect(FinancesMainLayoutPolicy.groupRowNameFadeStart == 0.90)
        #expect(FinancesMainLayoutPolicy.groupRowNameFadeEnd == 0.98)
        #expect(FinancesMainLayoutPolicy.fabDiameter == 56)
        #expect(FinancesMainLayoutPolicy.fabIconSize == 20)
        #expect(FinancesMainLayoutPolicy.fabTrailingPadding == 20)
        #expect(FinancesMainLayoutPolicy.fabBottomPadding == 28)
        #expect(FinancesMainLayoutPolicy.scrollBottomPaddingWithoutFAB == 28)
    }

    @Test("Ширина суммы группы ограничена и адаптируется под компактные экраны")
    func groupRowAmountWidthUsesClampedResponsiveRange() {
        #expect(FinancesMainLayoutPolicy.groupRowAmountWidth(containerWidth: 320) == 110)
        #expect(FinancesMainLayoutPolicy.groupRowAmountWidth(containerWidth: 360) == 111.6)
        #expect(FinancesMainLayoutPolicy.groupRowAmountWidth(containerWidth: 393) == 121.83)
        #expect(FinancesMainLayoutPolicy.groupRowAmountWidth(containerWidth: 430) == 126)
        #expect(FinancesMainLayoutPolicy.groupRowAmountWidth(containerWidth: 600) == 126)
    }
}
