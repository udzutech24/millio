//
//  FinanceQuickEditLayoutPolicyTests.swift
//  millioTests
//

import Testing
@testable import millio

@Suite
struct FinanceQuickEditLayoutPolicyTests {
    @Test("Кнопка удаления в быстром редактировании доступна для карты и инвестиций")
    func deleteButtonVisibilityMatchesSupportedAccountTypes() {
        #expect(FinanceQuickEditLayoutPolicy.showsDeleteButton(for: .card) == true)
        #expect(FinanceQuickEditLayoutPolicy.showsDeleteButton(for: .investment) == true)
        #expect(FinanceQuickEditLayoutPolicy.showsDeleteButton(for: .credit) == false)
    }
}
