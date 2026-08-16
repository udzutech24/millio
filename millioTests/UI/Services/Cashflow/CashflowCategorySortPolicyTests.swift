import XCTest
@testable import millio

final class CashflowCategorySortPolicyTests: XCTestCase {
    private let options = [
        CashflowCategoryOption(rawValue: "a", displayName: "Zulu", icon: "z.circle", isCustom: false),
        CashflowCategoryOption(rawValue: "b", displayName: "Alpha", icon: "a.circle", isCustom: false),
        CashflowCategoryOption(rawValue: "c", displayName: "Beta", icon: "b.circle", isCustom: false)
    ]

    func testPinnedAlwaysPrecedesAmountSort() {
        let result = CashflowCategorySortPolicy.sorted(
            options,
            mode: .amount,
            pinned: ["a"],
            totals: ["a": 1, "b": 100, "c": 50],
            latestActivity: [:]
        )
        XCTAssertEqual(result.map(\.rawValue), ["a", "b", "c"])
    }

    func testActivitySortUsesLatestDateAndKeepsStableTieOrder() {
        let result = CashflowCategorySortPolicy.sorted(
            options,
            mode: .activity,
            pinned: [],
            totals: [:],
            latestActivity: ["c": Date(timeIntervalSince1970: 20), "a": Date(timeIntervalSince1970: 10)]
        )
        XCTAssertEqual(result.map(\.rawValue), ["c", "a", "b"])
    }

    func testNameAndManualModes() {
        XCTAssertEqual(
            CashflowCategorySortPolicy.sorted(options, mode: .name, pinned: [], totals: [:], latestActivity: [:]).map(\.rawValue),
            ["b", "c", "a"]
        )
        XCTAssertEqual(
            CashflowCategorySortPolicy.sorted(options, mode: .manual, pinned: [], totals: [:], latestActivity: [:]).map(\.rawValue),
            ["a", "b", "c"]
        )
    }

    func testPreferencesAreSeparateByKind() {
        let suite = "CashflowCategorySortPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        CashflowCategorySortPreferences.save(.amount, for: .income, defaults: defaults)
        CashflowCategorySortPreferences.save(.name, for: .expense, defaults: defaults)
        XCTAssertEqual(CashflowCategorySortPreferences.load(for: .income, defaults: defaults), .amount)
        XCTAssertEqual(CashflowCategorySortPreferences.load(for: .expense, defaults: defaults), .name)
    }
}
