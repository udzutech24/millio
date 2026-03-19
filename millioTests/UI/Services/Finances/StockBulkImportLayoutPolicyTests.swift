//
//  StockBulkImportLayoutPolicyTests.swift
//  millioTests
//

import Testing
@testable import millio

@Suite
struct StockBulkImportLayoutPolicyTests {
    @Test("Режим скриншотов использует photo-stack и понятный onboarding текст")
    func screenshotPresentationUsesDedicatedContent() {
        let presentation = StockBulkImportLayoutPolicy.presentation(for: .screenshot)

        #expect(presentation.icon == "photo.stack")
        #expect(!presentation.title.isEmpty)
        #expect(!presentation.subtitle.isEmpty)
    }

    @Test("Ручной режим использует pencil-иконку и не теряет подсказку")
    func manualPresentationUsesDedicatedContent() {
        let presentation = StockBulkImportLayoutPolicy.presentation(for: .manual)

        #expect(presentation.icon == "square.and.pencil")
        #expect(!presentation.title.isEmpty)
        #expect(!presentation.subtitle.isEmpty)
    }

    @Test("Нижний CTA явно сообщает, когда импорт недоступен")
    func bottomActionTitleReflectsAvailability() {
        #expect(StockBulkImportLayoutPolicy.bottomActionTitle(addableCount: 0) != "")
        #expect(StockBulkImportLayoutPolicy.bottomActionTitle(addableCount: 3) != StockBulkImportLayoutPolicy.bottomActionTitle(addableCount: 0))
    }
}
