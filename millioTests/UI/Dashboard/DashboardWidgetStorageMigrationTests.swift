import Foundation
import XCTest
@testable import millio

/// Ф1b, риск 1: `DashboardWidgetStorage.load()` возвращает СОХРАНЁННЫЙ массив виджетов.
/// У пользователя, который хоть раз открывал настройки дашборда, новый виджет без явной
/// дозаписи не появился бы никогда.
final class DashboardWidgetStorageMigrationTests: XCTestCase {
    private let widgetsKey = "dashboard.active_widgets.v1"
    private let offeredKey = "dashboard.active_widgets.offered_ids.v1"
    private var savedWidgets: Data?
    private var savedOffered: [String]?

    override func setUp() {
        super.setUp()
        savedWidgets = UserDefaults.standard.data(forKey: widgetsKey)
        savedOffered = UserDefaults.standard.stringArray(forKey: offeredKey)
    }

    override func tearDown() {
        if let savedWidgets {
            UserDefaults.standard.set(savedWidgets, forKey: widgetsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: widgetsKey)
        }
        if let savedOffered {
            UserDefaults.standard.set(savedOffered, forKey: offeredKey)
        } else {
            UserDefaults.standard.removeObject(forKey: offeredKey)
        }
        super.tearDown()
    }

    // MARK: - Чистая логика дозаписи

    func testIntroducedWidgetIsAppendedToLegacySavedSet() {
        let legacy: [DashboardWidgetID] = [.totalBalance, .quickActions, .cashflowSummary, .currencyRates]
        let result = DashboardWidgetStorage.applyingIntroducedWidgets(
            to: legacy,
            introduced: [.aiSummary],
            alreadyOffered: []
        )
        XCTAssertTrue(result.widgets.contains(.aiSummary))
        XCTAssertTrue(result.offered.contains(DashboardWidgetID.aiSummary.rawValue))
    }

    func testIntroducedWidgetLandsRightAfterTotalBalance() {
        let legacy: [DashboardWidgetID] = [.totalBalance, .quickActions, .cashflowSummary, .currencyRates]
        let result = DashboardWidgetStorage.applyingIntroducedWidgets(
            to: legacy,
            introduced: [.aiSummary],
            alreadyOffered: []
        )
        XCTAssertEqual(result.widgets, [.totalBalance, .aiSummary, .quickActions, .cashflowSummary, .currencyRates])
    }

    func testIntroducedWidgetRespectsCustomOrder() {
        // Пользователь переставил виджеты: карточка встаёт перед первым, кто в дефолтном
        // порядке идёт после неё (quickActions), а не в конец списка.
        let custom: [DashboardWidgetID] = [.currencyRates, .totalBalance, .quickActions]
        let result = DashboardWidgetStorage.applyingIntroducedWidgets(
            to: custom,
            introduced: [.aiSummary],
            alreadyOffered: []
        )
        XCTAssertEqual(result.widgets, [.currencyRates, .totalBalance, .aiSummary, .quickActions])
    }

    func testRemovedWidgetIsNotReAddedOnSecondLaunch() {
        let first = DashboardWidgetStorage.applyingIntroducedWidgets(
            to: [.totalBalance, .quickActions],
            introduced: [.aiSummary],
            alreadyOffered: []
        )
        // Пользователь убрал карточку руками.
        let afterRemoval = first.widgets.filter { $0 != .aiSummary }
        let second = DashboardWidgetStorage.applyingIntroducedWidgets(
            to: afterRemoval,
            introduced: [.aiSummary],
            alreadyOffered: first.offered
        )
        XCTAssertFalse(second.widgets.contains(.aiSummary))
    }

    func testAlreadyPresentWidgetIsNotDuplicated() {
        let saved: [DashboardWidgetID] = [.totalBalance, .aiSummary, .quickActions]
        let result = DashboardWidgetStorage.applyingIntroducedWidgets(
            to: saved,
            introduced: [.aiSummary],
            alreadyOffered: []
        )
        XCTAssertEqual(result.widgets, saved)
        XCTAssertEqual(result.widgets.filter { $0 == .aiSummary }.count, 1)
    }

    // MARK: - Сценарий владельца целиком

    func testLoadAddsWidgetToAlreadySavedSetOfExistingUser() throws {
        let legacy: [DashboardWidgetID] = [.totalBalance, .quickActions, .cashflowSummary, .currencyRates]
        UserDefaults.standard.set(try JSONEncoder().encode(legacy), forKey: widgetsKey)
        UserDefaults.standard.removeObject(forKey: offeredKey)

        let loaded = DashboardWidgetStorage.load()

        XCTAssertEqual(loaded, [.totalBalance, .aiSummary, .quickActions, .cashflowSummary, .currencyRates])
        // Дозапись должна быть сохранена, иначе на следующем запуске всё повторится.
        let persisted = try JSONDecoder().decode(
            [DashboardWidgetID].self,
            from: XCTUnwrap(UserDefaults.standard.data(forKey: widgetsKey))
        )
        XCTAssertEqual(persisted, loaded)
    }

    func testLoadDoesNotResurrectWidgetUserRemoved() throws {
        let withoutAI: [DashboardWidgetID] = [.totalBalance, .quickActions]
        UserDefaults.standard.set(try JSONEncoder().encode(withoutAI), forKey: widgetsKey)
        UserDefaults.standard.set([DashboardWidgetID.aiSummary.rawValue], forKey: offeredKey)

        XCTAssertEqual(DashboardWidgetStorage.load(), withoutAI)
    }

    func testFreshInstallGetsWidgetFromDefaultsAndMarksItOffered() {
        UserDefaults.standard.removeObject(forKey: widgetsKey)
        UserDefaults.standard.removeObject(forKey: offeredKey)

        XCTAssertTrue(DashboardWidgetStorage.load().contains(.aiSummary))
        XCTAssertEqual(
            UserDefaults.standard.stringArray(forKey: offeredKey),
            [DashboardWidgetID.aiSummary.rawValue],
            "Иначе после первого же сохранения виджет дозапишется повторно"
        )
    }

    func testDefaultWidgetsContainEveryCase() {
        XCTAssertEqual(Set(DashboardWidgetStorage.defaultWidgets), Set(DashboardWidgetID.allCases))
    }
}
