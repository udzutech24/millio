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

    @Test("Stock bulk import layout policy serves Simplified Chinese copy from the catalog")
    @MainActor
    func stockBulkImportSupportsSimplifiedChineseCatalogCopy() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }

        LanguageManager.shared.setLanguage(.simplifiedChinese)

        let presentation = StockBulkImportLayoutPolicy.presentation(for: .screenshot)

        #expect(presentation.title == "最多选择 8 张截图")
        #expect(presentation.subtitle == "最多上传 8 张截图，我们会生成持仓草稿并标出有歧义的行。")
        #expect(StockBulkImportLayoutPolicy.screenshotInstructionsTitle == "如何准备截图")
        #expect(StockBulkImportLayoutPolicy.bottomActionTitle(addableCount: 3) == "导入：3")
    }
}
