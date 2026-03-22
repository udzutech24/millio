import XCTest
@testable import millio

final class QuickSetupExpenseCategoryPresetTests: XCTestCase {
    func testSystemExpenseCategoriesAreLocalizedForRussianLocale() {
        let presets = QuickSetupExpenseCategoryPreset.all(for: Locale(identifier: "ru_RU"))
        let namesByID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0.displayName) })

        XCTAssertEqual(namesByID[ExpenseCategory.groceries.rawValue], "Продукты")
        XCTAssertEqual(namesByID[ExpenseCategory.fuel.rawValue], "АЗС")
        XCTAssertEqual(namesByID[ExpenseCategory.transfers.rawValue], "Переводы")
        XCTAssertEqual(namesByID[ExpenseCategory.other.rawValue], "Разное")
    }

    func testExpandedSystemExpenseCategoriesAreLocalizedForEnglishLocale() {
        let presets = QuickSetupExpenseCategoryPreset.all(for: Locale(identifier: "en_US"))
        let namesByID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0.displayName) })

        XCTAssertEqual(namesByID[ExpenseCategory.travel.rawValue], "Travel")
        XCTAssertEqual(namesByID[ExpenseCategory.insurance.rawValue], "Insurance")
        XCTAssertEqual(namesByID[ExpenseCategory.transfers.rawValue], "Transfers")
    }
}
