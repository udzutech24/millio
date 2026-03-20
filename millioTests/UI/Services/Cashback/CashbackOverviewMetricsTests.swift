import Foundation
import Testing
@testable import millio

struct CashbackOverviewMetricsTests {
    @Test("Summary for cashback counts categories and unique linked cards")
    func countsCategoriesAndLinkedCards() {
        let cashbacks = [
            Cashback(name: "Продукты", category: .supermarket, percentage: 5, cardIDs: ["a", "b"], monthKey: "2026-03"),
            Cashback(name: "Кафе", category: .coffeeShop, percentage: 7, cardIDs: ["b", "c"], monthKey: "2026-03")
        ]

        let metrics = CashbackOverviewMetrics.make(from: cashbacks)

        #expect(metrics.categoryCount == 2)
        #expect(metrics.linkedCardCount == 3)
        #expect(metrics.formattedHighestPercentage == "7%")
        #expect(metrics.formattedAveragePercentage == "6%")
        #expect(metrics.featuredCategoryName == CashbackCategory.coffeeShop.displayName)
    }

    @Test("Featured cashback prefers more linked cards when percentage is tied")
    func prefersMoreLinkedCardsForTie() {
        let first = Cashback(name: "Рестораны", category: .restaurant, percentage: 10, cardIDs: ["a"], monthKey: "2026-03")
        let second = Cashback(name: "Заправки", category: .gasStation, percentage: 10, cardIDs: ["a", "b"], monthKey: "2026-03")

        let metrics = CashbackOverviewMetrics.make(from: [first, second])

        #expect(metrics.featuredCategoryName == CashbackCategory.gasStation.displayName)
        #expect(metrics.featuredCashbackKey == CashbackOverviewMetrics.stableKey(for: second))
    }

    @Test("Empty cashback summary stays zeroed")
    func returnsEmptyMetricsForNoCashbacks() {
        let metrics = CashbackOverviewMetrics.make(from: [])

        #expect(metrics == .empty)
        #expect(metrics.formattedAveragePercentage == "0%")
        #expect(metrics.formattedHighestPercentage == "0%")
    }
}
