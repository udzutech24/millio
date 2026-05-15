import XCTest
@testable import millio

final class QuickSetupExpenseCategoryPresetTests: XCTestCase {
    func testSystemExpenseCategoriesAreLocalizedForRussianLocale() {
        let presets = QuickSetupExpenseCategoryPreset.all(for: Locale(identifier: "ru_RU"))
        let namesByID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0.displayName) })

        XCTAssertEqual(namesByID[ExpenseCategory.groceries.rawValue], "Продукты")
        XCTAssertEqual(namesByID[ExpenseCategory.fuel.rawValue], "Топливо")
        XCTAssertEqual(namesByID[ExpenseCategory.transfers.rawValue], "Переводы")
        XCTAssertEqual(namesByID[ExpenseCategory.other.rawValue], "Другое")
    }

    func testExpandedSystemExpenseCategoriesAreLocalizedForEnglishLocale() {
        let presets = QuickSetupExpenseCategoryPreset.all(for: Locale(identifier: "en_US"))
        let namesByID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0.displayName) })

        XCTAssertEqual(namesByID[ExpenseCategory.travel.rawValue], "Travel")
        XCTAssertEqual(namesByID[ExpenseCategory.insurance.rawValue], "Insurance")
        XCTAssertEqual(namesByID[ExpenseCategory.transfers.rawValue], "Transfers")
    }

    func testSystemExpenseCategoriesAreLocalizedForSimplifiedChineseLocale() {
        let presets = QuickSetupExpenseCategoryPreset.all(for: Locale(identifier: "zh-Hans"))
        let namesByID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0.displayName) })

        XCTAssertEqual(namesByID[ExpenseCategory.groceries.rawValue], "商超购物")
        XCTAssertEqual(namesByID[ExpenseCategory.dining.rawValue], "外食")
        XCTAssertEqual(namesByID[ExpenseCategory.travel.rawValue], "旅行")
        XCTAssertEqual(namesByID[ExpenseCategory.transfers.rawValue], "转账")
    }
}
