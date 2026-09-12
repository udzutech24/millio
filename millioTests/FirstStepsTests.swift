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
}
