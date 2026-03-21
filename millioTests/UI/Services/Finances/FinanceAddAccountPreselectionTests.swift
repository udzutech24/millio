//
//  FinanceAddAccountPreselectionTests.swift
//  millioTests
//

import Testing
@testable import millio

@Suite
struct FinanceAddAccountPreselectionTests {
    @Test("Предвыбор карты возвращает заголовок продукта карты")
    func testCardTitle() {
        #expect(
            FinanceAddAccountPreselection.productTitle(for: .card) == FinanceAccountType.card.displayName
        )
    }

    @Test("Предвыбор кредита возвращает заголовок продукта кредита")
    func testCreditTitle() {
        #expect(
            FinanceAddAccountPreselection.productTitle(for: .credit) == FinanceAccountType.credit.displayName
        )
    }
}
