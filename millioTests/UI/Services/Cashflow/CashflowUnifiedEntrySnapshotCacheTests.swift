import XCTest
@testable import millio

@MainActor
final class CashflowUnifiedEntrySnapshotCacheTests: XCTestCase {
    func testCacheIsBoundedAndIsolatesMonthCurrencyAndRevision() {
        let cache = CashflowUnifiedEntrySnapshotCache(capacity: 2)
        let month = Date(timeIntervalSince1970: 1_700_000_000)
        func key(_ currency: String, _ revision: Int) -> CashflowUnifiedEntrySnapshotKey {
            .init(kindRawValue: "expense", monthStart: month, currency: currency, revision: revision)
        }
        let snapshot = CashflowUnifiedEntrySnapshot(
            total: 0, categoryTotals: [:], budgetPlan: nil, budgetSnapshot: nil, categoryLimits: [:]
        )
        cache.insert(snapshot, for: key("RUB", 0))
        cache.insert(snapshot, for: key("USD", 0))
        XCTAssertNil(cache.value(for: key("RUB", 1)))
        cache.insert(snapshot, for: key("EUR", 0))
        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache.value(for: key("RUB", 0)))
    }

    func testRemoveAllInvalidatesSnapshots() {
        let cache = CashflowUnifiedEntrySnapshotCache()
        let key = CashflowUnifiedEntrySnapshotKey(
            kindRawValue: "income", monthStart: .distantPast, currency: "RUB", revision: 0
        )
        cache.insert(.init(total: 0, categoryTotals: [:], budgetPlan: nil, budgetSnapshot: nil, categoryLimits: [:]), for: key)
        cache.removeAll()
        XCTAssertNil(cache.value(for: key))
    }
}
