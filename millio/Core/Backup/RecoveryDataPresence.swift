import Foundation

/// Separates user financial data from reference/cache models that can exist in
/// an otherwise empty store (for example downloaded FX rates).
enum RecoveryDataPresence {
    static let userFinancialTypes: Set<String> = [
        "Account",
        "FinanceAccount",
        "Card",
        "Investment",
        "Credit",
        "CashflowTransaction",
        "Cashback",
        "UserSubscription",
        "BudgetPlan",
        "RealEstateProfile"
    ]

    static func userFinancialModelCount(in payload: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return nil }
        return models.reduce(into: 0) { count, model in
            guard let type = model["_type"] as? String,
                  userFinancialTypes.contains(type) else { return }
            count += 1
        }
    }
}
