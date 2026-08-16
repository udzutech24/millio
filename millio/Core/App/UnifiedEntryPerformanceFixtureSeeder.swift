import Foundation
import SwiftData

/// Deterministic, synthetic workload for target-device profiling.
/// Enabled only by `MILLIO_UNIFIED_ENTRY_PERF_MODE=1`; never uses user data.
@MainActor
enum UnifiedEntryPerformanceFixtureSeeder {
    static let environmentKey = "MILLIO_UNIFIED_ENTRY_PERF_MODE"
    static let months = 18
    static let transactionsPerMonth = 64
    static let expectedTransactionCount = months * transactionsPerMonth

    static func seed(into context: ModelContext, now: Date = .now) throws {
        try context.delete(model: CashflowTransaction.self)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monthAnchor = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now
        let expenseCategories = ExpenseCategory.allCases
        let incomeCategories = IncomeCategory.allCases

        for monthOffset in 0..<months {
            guard let month = calendar.date(byAdding: .month, value: -monthOffset, to: monthAnchor) else {
                continue
            }
            for index in 0..<transactionsPerMonth {
                let day = (index % 27) + 1
                let date = calendar.date(byAdding: .day, value: day - 1, to: month) ?? month
                let isIncome = index.isMultiple(of: 5)
                let transaction = CashflowTransaction(
                    transactionType: isIncome ? .income : .expense,
                    amount: deterministicAmount(monthOffset: monthOffset, index: index),
                    currency: "RUB",
                    transactionDate: date,
                    incomeCategory: isIncome ? incomeCategories[index % incomeCategories.count] : nil,
                    expenseCategory: isIncome ? nil : expenseCategories[index % expenseCategories.count],
                    note: "Performance fixture #\(monthOffset)-\(index)",
                    affectsCardBalance: false
                )
                context.insert(transaction)
            }
        }
        try context.save()
    }

    private static func deterministicAmount(monthOffset: Int, index: Int) -> Double {
        let base = ((monthOffset + 3) * 97 + (index + 11) * 193) % 48_000
        return Double(base + 250)
    }
}
