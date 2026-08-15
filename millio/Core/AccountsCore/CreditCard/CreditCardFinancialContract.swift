import Foundation

/// Pure compatibility boundary for credit cards persisted with Millio's original
/// "available balance" ledger. Consumers use `netPosition`, never the ambiguous raw balance.
/// This avoids rewriting existing events while establishing one signed financial contract:
/// debt is negative, zero is settled, and overpayment is positive.
struct CreditCardFinancialSnapshot: Equatable {
    let creditLimit: Decimal
    let netPosition: Decimal
    let debt: Decimal
    let overpayment: Decimal
    let availableLimit: Decimal
    let utilization: Decimal
    let accruedFees: Decimal
    let accruedInterest: Decimal

    var isOverLimit: Bool { availableLimit < 0 }
}

enum CreditCardFinancialContract {
    /// Converts the persisted available-balance ledger into the canonical signed position.
    static func netPosition(rawAvailableBalance: Decimal, creditLimit: Decimal) -> Decimal {
        rawAvailableBalance - creditLimit
    }

    /// Converts the debt amount entered by the user back to the persisted available-balance ledger.
    static func rawAvailableBalance(debt: Decimal, creditLimit: Decimal) -> Decimal {
        creditLimit - max(0, debt)
    }

    static func snapshot(
        rawAvailableBalance: Decimal,
        creditLimit: Decimal,
        events: [AccountEvent] = []
    ) -> CreditCardFinancialSnapshot? {
        guard creditLimit > 0 else { return nil }

        let netPosition = netPosition(rawAvailableBalance: rawAvailableBalance, creditLimit: creditLimit)
        let debt = max(0, -netPosition)
        let overpayment = max(0, netPosition)
        let availableLimit = creditLimit - debt
        let utilization = debt / creditLimit
        let accruedFees = events.reduce(Decimal.zero) { result, event in
            result + (event.type == .creditCardFee ? max(0, event.amount ?? 0) : 0)
        }
        let accruedInterest = events.reduce(Decimal.zero) { result, event in
            result + (event.type == .creditCardInterest ? max(0, event.amount ?? 0) : 0)
        }

        return CreditCardFinancialSnapshot(
            creditLimit: creditLimit,
            netPosition: netPosition,
            debt: debt,
            overpayment: overpayment,
            availableLimit: availableLimit,
            utilization: utilization,
            accruedFees: accruedFees,
            accruedInterest: accruedInterest
        )
    }
}

enum CreditCardOperationKind: CaseIterable {
    case purchase
    case refund
    case repayment
    case fee
    case interest

    var eventType: AccountEventType {
        switch self {
        case .purchase: .creditCardPurchase
        case .refund: .creditCardRefund
        case .repayment: .creditCardRepayment
        case .fee: .creditCardFee
        case .interest: .creditCardInterest
        }
    }
}
