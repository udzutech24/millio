//
//  InvestmentEditorLayoutPolicyTests.swift
//  millioTests
//

import Testing
@testable import millio

@Suite
struct InvestmentEditorLayoutPolicyTests {
    @Test("Кнопка удаления в редакторе инвестиций доступна только при редактировании существующей записи")
    func deleteButtonVisibilityRequiresExistingInvestment() {
        #expect(InvestmentEditorLayoutPolicy.showsDeleteButton(for: nil) == false)

        let investment = Investment(
            name: "BTC",
            investmentType: .positive,
            category: .crypto,
            amount: 1000,
            currency: "USD"
        )
        #expect(InvestmentEditorLayoutPolicy.showsDeleteButton(for: investment) == true)
    }
}
