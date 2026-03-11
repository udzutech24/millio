import Foundation

enum MarketSearchFlowPolicy {
    static func shouldAutoOpenSearch(
        previousCategory: InvestmentCategory,
        newCategory: InvestmentCategory,
        marketSymbol: String,
        isEditingLockedIdentity: Bool
    ) -> Bool {
        guard !isEditingLockedIdentity else { return false }
        guard !isMarketCategory(previousCategory), isMarketCategory(newCategory) else { return false }
        return marketSymbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isMarketCategory(_ category: InvestmentCategory) -> Bool {
        category == .stocks || category == .crypto
    }
}
