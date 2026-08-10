import Foundation
import SwiftData

enum CreditCardOperationError: Error, Equatable {
    case dirtyContext
    case invalidAmount
    case invalidCreditCard
    case archivedAccount
    case duplicateOperationConflict
    case purchaseNotFound
    case refundExceedsPurchase
    case invalidRepaymentSource
    case currencyMismatch
    case insufficientFunds
}

struct CreditCardCashflowCommand {
    let operationID: String
    let kind: CreditCardOperationKind
    let amount: Decimal
    let date: Date
    let categoryID: String?
    let note: String?
    let purchaseID: String?

    init(
        operationID: String,
        kind: CreditCardOperationKind,
        amount: Decimal,
        date: Date = Date(),
        categoryID: String? = nil,
        note: String? = nil,
        purchaseID: String? = nil
    ) {
        self.operationID = operationID
        self.kind = kind
        self.amount = amount
        self.date = date
        self.categoryID = categoryID
        self.note = note
        self.purchaseID = purchaseID
    }
}

struct CreditCardRepaymentCommand {
    let operationID: String
    let amount: Decimal
    let date: Date
    let note: String?

    init(operationID: String, amount: Decimal, date: Date = Date(), note: String? = nil) {
        self.operationID = operationID
        self.amount = amount
        self.date = date
        self.note = note
    }
}

struct CreditCardOperationResult {
    let cardEvent: AccountEvent
    let sourceEvent: AccountEvent?
    let cashflowTransaction: CashflowTransaction?
    let wasAlreadyPersisted: Bool
}

/// Owns the only atomic write boundary for credit-card operations that also affect Cashflow.
/// A caller-supplied stable operation ID makes retries safe across UI re-submission and sync replay.
@MainActor
final class CreditCardOperationCoordinator {
    private let modelContext: ModelContext
    private let saveBoundary: AccountsCoreSaveBoundary

    init(
        modelContext: ModelContext,
        saveOperation: @escaping AccountsCoreSaveBoundary.SaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.saveBoundary = AccountsCoreSaveBoundary(saveOperation: saveOperation)
    }

    func record(
        card: Account,
        command: CreditCardCashflowCommand
    ) throws -> CreditCardOperationResult {
        guard !modelContext.hasChanges else { throw CreditCardOperationError.dirtyContext }
        try validateCard(card)
        try validate(command.amount, operationID: command.operationID)
        guard command.kind != .repayment else { throw CreditCardOperationError.invalidRepaymentSource }

        if let existing = try existingResult(operationID: command.operationID) {
            guard existing.cardEvent.account?.id == card.id,
                  existing.cardEvent.type == command.kind.eventType,
                  existing.cardEvent.amount == command.amount,
                  existing.sourceEvent == nil,
                  existing.cashflowTransaction?.transactionType == .expense else {
                throw CreditCardOperationError.duplicateOperationConflict
            }
            return existing
        }

        var groupID = command.operationID
        if command.kind == .refund {
            guard let purchaseID = normalized(command.purchaseID) else {
                throw CreditCardOperationError.purchaseNotFound
            }
            try validateRefund(amount: command.amount, purchaseID: purchaseID, card: card)
            groupID = purchaseID
        }

        let cashflow = CashflowTransaction(
            transactionType: .expense,
            amount: double(command.kind == .refund ? -command.amount : command.amount),
            currency: card.currency,
            transactionDate: command.date,
            cardID: card.id.uuidString,
            expenseCategoryRaw: command.categoryID,
            note: command.note,
            operationGroupID: groupID,
            affectsCardBalance: false,
            affectsCashflowTotals: true
        )
        cashflow.uniqueID = command.operationID

        let event = AccountEvent(
            account: card,
            date: command.date,
            type: command.kind.eventType,
            amount: command.amount,
            categoryID: command.categoryID,
            note: command.note,
            sourceTransactionID: command.operationID
        )
        modelContext.insert(cashflow)
        modelContext.insert(event)
        invalidate(card, from: command.date)
        try saveBoundary.commit(modelContext, operation: .updateAccount)
        return CreditCardOperationResult(
            cardEvent: event, sourceEvent: nil, cashflowTransaction: cashflow, wasAlreadyPersisted: false
        )
    }

    func repay(
        card: Account,
        from source: Account,
        command: CreditCardRepaymentCommand
    ) throws -> CreditCardOperationResult {
        guard !modelContext.hasChanges else { throw CreditCardOperationError.dirtyContext }
        try validateCard(card)
        try validate(command.amount, operationID: command.operationID)
        try validateRepaymentSource(source, card: card, amount: command.amount, on: command.date)

        if let existing = try existingResult(operationID: command.operationID) {
            guard existing.cardEvent.account?.id == card.id,
                  existing.cardEvent.type == .creditCardRepayment,
                  existing.cardEvent.amount == command.amount,
                  existing.sourceEvent?.account?.id == source.id,
                  existing.sourceEvent?.type == .transferOut,
                  existing.cashflowTransaction?.transactionType == .transfer else {
                throw CreditCardOperationError.duplicateOperationConflict
            }
            return existing
        }

        let transferID = UUID()
        let createdAt = Date()
        let sourceEvent = AccountEvent(
            account: source, date: command.date, createdAt: createdAt, type: .transferOut,
            amount: command.amount, note: command.note, transferID: transferID,
            sourceTransactionID: command.operationID
        )
        let cardEvent = AccountEvent(
            account: card, date: command.date, createdAt: createdAt, type: .creditCardRepayment,
            amount: command.amount, note: command.note, transferID: transferID,
            sourceTransactionID: command.operationID
        )
        let cashflow = CashflowTransaction(
            transactionType: .transfer,
            amount: double(command.amount),
            currency: card.currency,
            transactionDate: command.date,
            cardID: source.id.uuidString,
            toCardID: card.id.uuidString,
            note: command.note,
            operationGroupID: command.operationID,
            affectsCardBalance: false,
            affectsCashflowTotals: false
        )
        cashflow.uniqueID = command.operationID

        modelContext.insert(sourceEvent)
        modelContext.insert(cardEvent)
        modelContext.insert(cashflow)
        invalidate(source, from: command.date)
        invalidate(card, from: command.date)
        try saveBoundary.commit(modelContext, operation: .updateAccount)
        return CreditCardOperationResult(
            cardEvent: cardEvent, sourceEvent: sourceEvent,
            cashflowTransaction: cashflow, wasAlreadyPersisted: false
        )
    }

    private func validateCard(_ card: Account) throws {
        guard card.productType == .creditCard else { throw CreditCardOperationError.invalidCreditCard }
        guard card.archivedAt == nil, card.deletedAt == nil else { throw CreditCardOperationError.archivedAccount }
    }

    private func validate(_ amount: Decimal, operationID: String) throws {
        guard amount > 0, normalized(operationID) != nil else { throw CreditCardOperationError.invalidAmount }
    }

    private func validateRepaymentSource(
        _ source: Account,
        card: Account,
        amount: Decimal,
        on date: Date
    ) throws {
        let allowed: Set<AccountProductType> = [.cash, .debitCard, .bankAccount]
        guard allowed.contains(source.productType ?? .unknownLegacy), source.id != card.id,
              source.archivedAt == nil, source.deletedAt == nil else {
            throw CreditCardOperationError.invalidRepaymentSource
        }
        guard source.currency.uppercased() == card.currency.uppercased() else {
            throw CreditCardOperationError.currencyMismatch
        }
        let events = try events(for: source)
        let balance = AccountBalanceEngine.balanceAt(events: events, kind: source.kind, on: date)
        guard balance >= amount else { throw CreditCardOperationError.insufficientFunds }
    }

    private func validateRefund(amount: Decimal, purchaseID: String, card: Account) throws {
        let transactionDescriptor = FetchDescriptor<CashflowTransaction>(
            predicate: #Predicate<CashflowTransaction> { $0.operationGroupID == purchaseID }
        )
        let group = try modelContext.fetch(transactionDescriptor)
        guard let purchase = group.first(where: {
            $0.uniqueID == purchaseID && $0.transactionTypeRaw == CashflowTransactionType.expense.rawValue
                && $0.cardID == card.id.uuidString && $0.amount > 0
        }) else {
            throw CreditCardOperationError.purchaseNotFound
        }
        let refunded = group.filter { $0.amount < 0 }.reduce(Decimal.zero) { $0 + decimal(-$1.amount) }
        guard refunded + amount <= decimal(purchase.amount) else {
            throw CreditCardOperationError.refundExceedsPurchase
        }
    }

    private func existingResult(operationID: String) throws -> CreditCardOperationResult? {
        let eventDescriptor = FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == operationID }
        )
        let events = try modelContext.fetch(eventDescriptor)
        guard let cardEvent = events.first(where: {
            $0.type == .creditCardPurchase || $0.type == .creditCardRefund
                || $0.type == .creditCardFee || $0.type == .creditCardInterest
                || $0.type == .creditCardRepayment
        }) else { return nil }
        let transactionDescriptor = FetchDescriptor<CashflowTransaction>(
            predicate: #Predicate<CashflowTransaction> { $0.uniqueID == operationID }
        )
        return CreditCardOperationResult(
            cardEvent: cardEvent,
            sourceEvent: events.first(where: { $0.id != cardEvent.id }),
            cashflowTransaction: try modelContext.fetch(transactionDescriptor).first,
            wasAlreadyPersisted: true
        )
    }

    private func events(for account: Account) throws -> [AccountEvent] {
        let id = account.id
        return try modelContext.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.account?.id == id }
        ))
    }

    private func invalidate(_ account: Account, from date: Date) {
        AccountsCoreService(modelContext: modelContext).invalidateSnapshotCache(for: account, from: date)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private func decimal(_ value: Double) -> Decimal {
        Decimal(string: String(format: "%.6f", value)) ?? Decimal(value)
    }

    private func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
