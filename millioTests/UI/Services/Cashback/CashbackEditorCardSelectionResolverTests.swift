//
//  CashbackEditorCardSelectionResolverTests.swift
//  millioTests
//

import Testing
@testable import millio

@Suite
struct CashbackEditorCardSelectionResolverTests {
    @Test("Сохраняет текущий выбор, если у выбранной карты еще нет сохраненных категорий")
    func testResolvePreservesCurrentDraftWhenExistingSelectionIsEmpty() {
        let resolved = CashbackEditorCardSelectionResolver.resolve(
            existingCategoryRaws: [],
            existingCardCashbacks: [:],
            currentCategoryRaws: ["restaurant", "transport"],
            currentCardCashbacks: [
                "restaurant": "5",
                "transport": "7"
            ],
            preserveCurrentIfExistingIsEmpty: true
        )

        #expect(resolved.selectedCategoryRaws == Set(["restaurant", "transport"]))
        #expect(resolved.cardCashbacks["restaurant"] == "5")
        #expect(resolved.cardCashbacks["transport"] == "7")
    }

    @Test("Применяет сохраненные категории карты, если они существуют")
    func testResolveUsesStoredSelectionWhenAvailable() {
        let resolved = CashbackEditorCardSelectionResolver.resolve(
            existingCategoryRaws: ["pharmacy"],
            existingCardCashbacks: ["pharmacy": "10"],
            currentCategoryRaws: ["restaurant"],
            currentCardCashbacks: ["restaurant": "5"],
            preserveCurrentIfExistingIsEmpty: true
        )

        #expect(resolved.selectedCategoryRaws == Set(["pharmacy"]))
        #expect(resolved.cardCashbacks == ["pharmacy": "10"])
    }
}

