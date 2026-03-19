//
//  FinanceQuickEditLayoutPolicyTests.swift
//  millioTests
//

import Testing
@testable import millio

@Suite
struct FinanceQuickEditLayoutPolicyTests {
    @Test("Название продукта для удаления очищается от хвостовых пробелов")
    func deleteProductNameIsTrimmedBeforeFormatting() {
        #expect(FinanceDeleteProductCopy.normalizedProductName(" Тест Карта  ") == "Тест Карта")
    }
}
