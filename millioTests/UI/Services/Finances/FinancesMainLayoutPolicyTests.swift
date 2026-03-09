//
//  FinancesMainLayoutPolicyTests.swift
//  millioTests
//

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
        #expect(paddingWithoutFAB > 0)
    }
}
