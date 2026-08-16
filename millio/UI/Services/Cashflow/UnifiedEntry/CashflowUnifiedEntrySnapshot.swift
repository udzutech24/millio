import Foundation

struct CashflowUnifiedEntrySnapshot {
    let total: Double
    let categoryTotals: [String: Double]
    let budgetPlan: BudgetPlan?
    let budgetSnapshot: BudgetProgressSnapshot?
    let categoryLimits: [String: Double]
}

extension CashflowViewModel {
    /// One public loading pipeline for the Unified Entry screen. Category totals are
    /// converted once and then shared by the total, chart, cards and budget summary.
    func unifiedEntrySnapshot(
        for kind: CashflowCategoryKind,
        month: Date,
        in currency: String
    ) async -> CashflowUnifiedEntrySnapshot {
        let totals = await monthlyCategoryTotals(for: kind, month: month, in: currency)
        guard !Task.isCancelled else {
            return .init(total: 0, categoryTotals: [:], budgetPlan: nil, budgetSnapshot: nil, categoryLimits: [:])
        }
        let budget = await monthlyBudgetSummary(
            for: kind,
            month: month,
            in: currency,
            categoryTotals: totals
        )
        return .init(
            total: totals.values.reduce(0, +),
            categoryTotals: totals,
            budgetPlan: budget.plan,
            budgetSnapshot: budget.snapshot,
            categoryLimits: budget.categoryLimits
        )
    }
}

struct CashflowUnifiedEntrySnapshotKey: Hashable {
    let kindRawValue: String
    let monthStart: Date
    let currency: String
    let revision: Int
}

/// Small LRU-like cache scoped to one entry screen. It deliberately stores only six
/// month/kind combinations so stale financial snapshots cannot grow without bound.
@MainActor
final class CashflowUnifiedEntrySnapshotCache {
    private let capacity: Int
    private var values: [CashflowUnifiedEntrySnapshotKey: CashflowUnifiedEntrySnapshot] = [:]
    private var order: [CashflowUnifiedEntrySnapshotKey] = []

    init(capacity: Int = 6) {
        self.capacity = max(1, capacity)
    }

    func value(for key: CashflowUnifiedEntrySnapshotKey) -> CashflowUnifiedEntrySnapshot? {
        values[key]
    }

    func insert(_ value: CashflowUnifiedEntrySnapshot, for key: CashflowUnifiedEntrySnapshotKey) {
        values[key] = value
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            values.removeValue(forKey: oldest)
        }
    }

    func removeAll() {
        values.removeAll()
        order.removeAll()
    }

    var count: Int { values.count }
}
