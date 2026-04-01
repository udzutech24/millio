//
//  CashflowBulkExpenseImportLocalizationTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct CashflowBulkExpenseImportLocalizationTests {
    @Test("Bulk expense import uses app language for month formatting")
    func monthFormattingFollowsAppLanguage() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }

        let month = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 1))!

        LanguageManager.shared.setLanguage(.english)
        let englishMonth = CashflowBulkExpenseImportLocalization.monthTitle(for: month)
        let englishRange = CashflowBulkExpenseImportLocalization.periodRangeTitle(for: month)

        LanguageManager.shared.setLanguage(.russian)
        let russianMonth = CashflowBulkExpenseImportLocalization.monthTitle(for: month)
        let russianRange = CashflowBulkExpenseImportLocalization.periodRangeTitle(for: month)

        LanguageManager.shared.setLanguage(.simplifiedChinese)
        let chineseMonth = CashflowBulkExpenseImportLocalization.monthTitle(for: month)
        let chineseRange = CashflowBulkExpenseImportLocalization.periodRangeTitle(for: month)

        #expect(englishMonth.contains("March"))
        #expect(englishRange.contains("Mar"))
        #expect(russianMonth.lowercased().contains("март"))
        #expect(russianRange.lowercased().contains("мар"))
        #expect(chineseMonth.contains("2026"))
        #expect(chineseMonth.contains("3"))
        #expect(chineseRange.contains("2026"))
        #expect(englishMonth != russianMonth)
        #expect(russianMonth != chineseMonth)
    }

    @Test("Bulk expense import sheet avoids device locale and raw review copy")
    func sourceGuardsKeepBulkExpenseScreenLocalized() throws {
        let sheetSource = try String(
            contentsOf: sourceURL("millio/UI/Services/Cashflow/CashflowBulkExpenseImportSheet.swift"),
            encoding: .utf8
        )
        let resolverSource = try String(
            contentsOf: sourceURL("millio/UI/Services/Cashflow/CashflowBulkExpenseImportCategoryResolver.swift"),
            encoding: .utf8
        )

        #expect(sheetSource.contains("CashflowBulkExpenseImportLocalization."))
        #expect(!sheetSource.contains("Locale.autoupdatingCurrent"))
        #expect(!sheetSource.contains("Locale.current"))
        #expect(!sheetSource.contains("\"Проверь импорт\""))
        #expect(!sheetSource.contains("\"Перенести в категории\""))
        #expect(!sheetSource.contains("\"Предположение:"))
        #expect(!resolverSource.contains("locale: .current"))
        #expect(!resolverSource.contains("locale: .autoupdatingCurrent"))
    }

    private func sourceURL(_ relativePath: String) throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        for _ in 0..<12 {
            let candidate = directory.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }

        throw NSError(
            domain: "CashflowBulkExpenseImportLocalizationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate `\(relativePath)` from `#filePath`."]
        )
    }
}
