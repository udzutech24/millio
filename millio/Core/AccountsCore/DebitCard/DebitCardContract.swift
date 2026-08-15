import Foundation

enum DebitCardContractError: Error, Equatable {
    case invalidProduct
    case archivedAccount
    case invalidAmount
    case insufficientFunds
    case invalidAdjustmentReason
}

enum DebitCardOperationKind: Equatable {
    case income
    case expense
    case fee
    case refund(originalOperationID: String)
    case adjustment(reason: String)

    var eventType: AccountEventType {
        switch self {
        case .income, .refund: .income
        case .expense: .expense
        case .fee: .fee
        case .adjustment: .adjustment
        }
    }
}

enum DebitCardLifecycle: Equatable { case active, archived, deleted }
enum DebitCardConversion: Equatable { case unavailable, exact(Decimal, String), provisional(Decimal, String) }

struct DebitCardSnapshot: Equatable {
    let accountID: UUID
    let actualBalance: Decimal
    let currency: String
    let converted: DebitCardConversion
    let participatesInTotal: Bool
    let lifecycle: DebitCardLifecycle
    let incompleteReason: String?
    let canWrite: Bool
}

enum DebitCardContract {
    static let products: Set<AccountProductType> = [.debitCard, .bankAccount]

    static func balance(account: Account, events: [AccountEvent], on date: Date) throws -> Decimal {
        guard let product = account.productType, products.contains(product) else {
            throw DebitCardContractError.invalidProduct
        }
        return DebitCurrencyPolicy.round(
            AccountBalanceEngine.balanceAt(events: events, kind: account.kind, on: date),
            currency: account.currency
        )
    }

    static func validate(
        account: Account,
        events: [AccountEvent],
        kind: DebitCardOperationKind,
        amount: Decimal,
        on date: Date
    ) throws -> Decimal {
        guard let product = account.productType, products.contains(product) else {
            throw DebitCardContractError.invalidProduct
        }
        guard account.archivedAt == nil, account.deletedAt == nil else {
            throw DebitCardContractError.archivedAccount
        }
        let normalized = DebitCurrencyPolicy.round(amount, currency: account.currency)
        guard normalized > 0 else { throw DebitCardContractError.invalidAmount }
        if case let .adjustment(reason) = kind,
           reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DebitCardContractError.invalidAdjustmentReason
        }
        if kind.eventType == .expense || kind.eventType == .fee {
            let available = try balance(account: account, events: events, on: date)
            guard available >= normalized else { throw DebitCardContractError.insufficientFunds }
        }
        return normalized
    }

    static func snapshot(
        account: Account,
        events: [AccountEvent],
        on date: Date,
        converted: DebitCardConversion = .unavailable
    ) -> DebitCardSnapshot? {
        guard let actual = try? balance(account: account, events: events, on: date) else { return nil }
        let lifecycle: DebitCardLifecycle = account.deletedAt != nil ? .deleted : (account.archivedAt != nil ? .archived : .active)
        // CardMeta is optional for a debit account. Absence of presentation metadata must not
        // turn an otherwise valid ledger account into a read-only account.
        let incomplete: String? = nil
        return DebitCardSnapshot(
            accountID: account.id, actualBalance: actual, currency: account.currency,
            converted: converted, participatesInTotal: account.participates(on: date),
            lifecycle: lifecycle, incompleteReason: incomplete,
            canWrite: lifecycle == .active && incomplete == nil
        )
    }
}
