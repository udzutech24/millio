import XCTest
@testable import millio

final class QuickSetupExpenseCategoryPresetTests: XCTestCase {
    func testSystemExpenseCategoriesAreLocalizedForRussianLocale() {
        let presets = QuickSetupExpenseCategoryPreset.all(for: Locale(identifier: "ru_RU"))
        let namesByID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0.displayName) })

        XCTAssertEqual(namesByID[ExpenseCategory.groceries.rawValue], "Продукты")
        XCTAssertEqual(namesByID[ExpenseCategory.transport.rawValue], "Транспорт")
        XCTAssertEqual(namesByID[ExpenseCategory.other.rawValue], "Другое")
    }

    func testCustomExpenseCategoriesAreLocalizedForEnglishLocale() {
        let presets = QuickSetupExpenseCategoryPreset.all(for: Locale(identifier: "en_US"))
        let namesByID = Dictionary(uniqueKeysWithValues: presets.map { ($0.id, $0.displayName) })

        XCTAssertEqual(namesByID["custom:travel"], "Travel")
        XCTAssertEqual(namesByID["custom:home"], "Home")
    }
}
