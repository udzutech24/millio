//
//  FirstStepsTests.swift
//  millioTests
//

import XCTest
@testable import millio

/// Прогресс чек-листа первых шагов считается чистой функцией от снимка данных —
/// ни UI, ни SwiftData-контейнер для проверки не нужны.
final class FirstStepsTests: XCTestCase {

    /// Состояние сразу после QuickSetup: валюта и категории есть, остального нет.
    private let afterQuickSetup = FirstStepsSnapshot(
        hasCurrency: true,
        categoryCount: 12,
        accountCount: 0,
        transactionCount: 0,
        backupEnabled: false
    )

    func testAfterQuickSetupTwoStepsOfFiveAreDone() {
        XCTAssertEqual(FirstStep.all.count, 5)
        XCTAssertEqual(FirstStep.doneCount(in: afterQuickSetup), 2)
    }

    func testAddingAccountClosesThirdStep() {
        var snapshot = afterQuickSetup
        snapshot.accountCount = 1

        XCTAssertEqual(FirstStep.doneCount(in: snapshot), 3)
    }

    func testFullSnapshotCompletesChecklist() {
        let snapshot = FirstStepsSnapshot(
            hasCurrency: true,
            categoryCount: 12,
            accountCount: 1,
            transactionCount: 1,
            backupEnabled: true
        )

        XCTAssertEqual(FirstStep.doneCount(in: snapshot), FirstStep.all.count)
    }

    /// Регрессия: у «currency» и «categories» `action` был `nil` — тап по строке ничего не
    /// открывал. Каждый шаг чек-листа обязан вести куда-то.
    func testEveryStepHasAnAction() {
        for step in FirstStep.all {
            XCTAssertNotNil(step.action, "У шага \(step.id) нет action — тап по нему ничего не сделает")
        }
    }

    /// Шаг «Язык и валюта» больше не открывает мастер быстрой настройки: строку из профиля
    /// убрали, путь — профиль с подсветкой «Основной валюты».
    func testCurrencyStepOpensProfilePrimaryCurrency() {
        let step = FirstStep.all.first { $0.id == "currency" }
        XCTAssertEqual(step?.action, .openPrimaryCurrency)
        XCTAssertEqual(step?.highlightID, "profile.primaryCurrencyLink")
    }

    func testCategoriesStepOpensCategorySettings() {
        let step = FirstStep.all.first { $0.id == "categories" }
        XCTAssertEqual(step?.action, .openCategorySettings)
    }
}
