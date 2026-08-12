import Foundation
import SwiftData

enum DebitCardOperationCoordinatorError: Error, Equatable {
    case dirtyContext
    case invalidOperationID
    case duplicateOperationConflict
    case originalExpenseNotFound
    case refundExceedsExpense
    case invalidTransferTarget
    case currencyMismatch
}

struct DebitCardOperationCommand {
    let operationID: String
    let kind: DebitCardOperationKind
    let amount: Decimal
    let date: Date
    let categoryID: String?
    let note: String?

    init(operationID: String, kind: DebitCardOperationKind, amount: Decimal, date: Date = Date(), categoryID: String? = nil, note: String? = nil) {
        self.operationID = operationID
        self.kind = kind
        self.amount = amount
        self.date = date
        self.categoryID = categoryID
        self.note = note
    }
}

struct DebitCardOperationResult {
    let events: [AccountEvent]
    let cashflowTransaction: CashflowTransaction?
    let wasAlreadyPersisted: Bool
}

/// The only commit boundary for new debit-card financial writes.
@MainActor
final class DebitCardOperationCoordinator {
    private let modelContext: ModelContext
    private let saveBoundary: AccountsCoreSaveBoundary

    init(modelContext: ModelContext, saveOperation: @escaping AccountsCoreSaveBoundary.SaveOperation = { try $0.save() }) {
        self.modelContext = modelContext
        self.saveBoundary = AccountsCoreSaveBoundary(saveOperation: saveOperation)
    }

    func record(account: Account, command: DebitCardOperationCommand) throws -> DebitCardOperationResult {
        guard !modelContext.hasChanges else { throw DebitCardOperationCoordinatorError.dirtyContext }
        let operationID = try normalizedOperationID(command.operationID)
        if let existing = try existingResult(operationID: operationID) {
            let expectedGroupID: String
            if case let .refund(originalID) = command.kind {
                expectedGroupID = try normalizedOperationID(originalID)
            } else {
                expectedGroupID = operationID
            }
            guard existing.events.count == 1,
                  existing.events[0].account?.id == account.id,
                  existing.events[0].type == command.kind.eventType,
                  existing.events[0].amount == DebitCurrencyPolicy.round(command.amount, currency: account.currency),
                  existing.cashflowTransaction?.operationGroupID == expectedGroupID else {
                throw DebitCardOperationCoordinatorError.duplicateOperationConflict
            }
            return existing
        }
        try CashflowMonthMutationPolicy(modelContext: modelContext).validate(.create, date: command.date)

        let events = try events(for: account)
        let amount = try DebitCardContract.validate(account: account, events: events, kind: command.kind, amount: command.amount, on: command.date)
        var operationGroupID = operationID
        if case let .refund(originalID) = command.kind {
            operationGroupID = try validateRefund(originalID: originalID, amount: amount, account: account)
        }

        let event = AccountEvent(
            account: account, date: command.date, type: command.kind.eventType, amount: amount,
            categoryID: command.categoryID, note: eventNote(command), sourceTransactionID: operationID
        )
        let transaction = makeCashflow(account: account, command: command, amount: amount, groupID: operationGroupID)
        modelContext.insert(event)
        modelContext.insert(transaction)
        invalidate(account, from: command.date)
        try saveBoundary.commit(modelContext, operation: .updateAccount)
        return DebitCardOperationResult(events: [event], cashflowTransaction: transaction, wasAlreadyPersisted: false)
    }

    func transfer(from source: Account, to destination: Account, operationID rawID: String, amount: Decimal, date: Date = Date(), note: String? = nil) throws -> DebitCardOperationResult {
        guard !modelContext.hasChanges else { throw DebitCardOperationCoordinatorError.dirtyContext }
        let operationID = try normalizedOperationID(rawID)
        guard source.id != destination.id else { throw DebitCardOperationCoordinatorError.invalidTransferTarget }
        guard source.currency.uppercased() == destination.currency.uppercased() else { throw DebitCardOperationCoordinatorError.currencyMismatch }
        guard let destinationProduct = destination.productType, DebitCardContract.products.contains(destinationProduct), destination.archivedAt == nil, destination.deletedAt == nil else {
            throw DebitCardOperationCoordinatorError.invalidTransferTarget
        }
        if let existing = try existingResult(operationID: operationID) {
            guard existing.events.count == 2,
                  Set(existing.events.compactMap { $0.account?.id }) == Set([source.id, destination.id]),
                  existing.events.allSatisfy({ $0.amount == DebitCurrencyPolicy.round(amount, currency: source.currency) }) else {
                throw DebitCardOperationCoordinatorError.duplicateOperationConflict
            }
            return existing
        }
        try CashflowMonthMutationPolicy(modelContext: modelContext).validate(.create, date: date)
        let sourceEvents = try events(for: source)
        let normalized = try DebitCardContract.validate(account: source, events: sourceEvents, kind: .expense, amount: amount, on: date)
        let transferID = UUID()
        let createdAt = Date()
        let out = AccountEvent(account: source, date: date, createdAt: createdAt, type: .transferOut, amount: normalized, note: note, transferID: transferID, sourceTransactionID: operationID)
        let incoming = AccountEvent(account: destination, date: date, createdAt: createdAt, type: .transferIn, amount: normalized, note: note, transferID: transferID, sourceTransactionID: operationID)
        let transaction = CashflowTransaction(transactionType: .transfer, amount: double(normalized), currency: source.currency, transactionDate: date, cardID: source.id.uuidString, toCardID: destination.id.uuidString, note: note, operationGroupID: operationID, affectsCardBalance: false, affectsCashflowTotals: false)
        transaction.uniqueID = operationID
        modelContext.insert(out); modelContext.insert(incoming); modelContext.insert(transaction)
        invalidate(source, from: date); invalidate(destination, from: date)
        try saveBoundary.commit(modelContext, operation: .updateAccount)
        return DebitCardOperationResult(events: [out, incoming], cashflowTransaction: transaction, wasAlreadyPersisted: false)
    }

    func adjust(account: Account, to targetBalance: Decimal, operationID rawID: String, reason: String, date: Date = Date()) throws -> DebitCardOperationResult {
        guard !modelContext.hasChanges else { throw DebitCardOperationCoordinatorError.dirtyContext }
        let operationID = try normalizedOperationID(rawID)
        guard account.archivedAt == nil, account.deletedAt == nil else { throw DebitCardContractError.archivedAccount }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReason.isEmpty else { throw DebitCardContractError.invalidAdjustmentReason }
        let target = DebitCurrencyPolicy.round(targetBalance, currency: account.currency)
        guard target >= 0 else { throw DebitCardContractError.insufficientFunds }
        if let existing = try existingResult(operationID: operationID) { return existing }
        try CashflowMonthMutationPolicy(modelContext: modelContext).validate(.create, date: date)
        let current = try DebitCardContract.balance(account: account, events: try events(for: account), on: date)
        let delta = target - current
        guard delta != 0 else { throw DebitCardContractError.invalidAmount }
        let event = AccountEvent(account: account, date: date, type: .adjustment, amount: delta, note: normalizedReason, sourceTransactionID: operationID)
        let transaction = CashflowTransaction(transactionType: .balanceAdjustment, amount: double(abs(delta)), currency: account.currency, transactionDate: date, cardID: account.id.uuidString, note: normalizedReason, operationGroupID: operationID, affectsCardBalance: false, affectsCashflowTotals: false)
        transaction.uniqueID = operationID
        modelContext.insert(event); modelContext.insert(transaction)
        invalidate(account, from: date)
        try saveBoundary.commit(modelContext, operation: .updateAccount)
        return DebitCardOperationResult(events: [event], cashflowTransaction: transaction, wasAlreadyPersisted: false)
    }

    func archive(_ account: Account, on date: Date = Date()) throws {
        guard !modelContext.hasChanges else { throw DebitCardOperationCoordinatorError.dirtyContext }
        _ = try DebitCardContract.balance(account: account, events: try events(for: account), on: date)
        account.archivedAt = date
        invalidate(account, from: date)
        try saveBoundary.commit(modelContext, operation: .updateAccount)
    }

    /// Adopts a Cashflow row already staged by the editor and commits its debit event in the same
    /// transaction. Editing replaces the prior projection inside this rollback boundary.
    func commitStagedCashflow(
        _ transaction: CashflowTransaction,
        account: Account,
        kind: DebitCardOperationKind,
        resolvedAmount: Decimal,
        eventNote: String? = nil,
        originalAmount: Decimal? = nil,
        originalCurrency: String? = nil,
        fxRate: Decimal? = nil,
        fxProvisional: Bool = false
    ) throws -> DebitCardOperationResult {
        try CashflowMonthMutationPolicy(modelContext: modelContext).validate(.edit, date: transaction.transactionDate)
        let operationID = try normalizedOperationID(transaction.uniqueID)
        let remaining = try events(for: account).filter { $0.sourceTransactionID != operationID }
        try deleteEvents(operationID: operationID)
        let magnitude = abs(resolvedAmount)
        let amount = try DebitCardContract.validate(account: account, events: remaining, kind: kind, amount: magnitude, on: transaction.transactionDate)
        if case let .refund(originalID) = kind {
            _ = try validateRefund(originalID: originalID, amount: amount, account: account)
        }
        let event = AccountEvent(
            account: account, date: transaction.transactionDate, type: kind.eventType, amount: amount,
            fxRateToBase: fxRate, fxProvisional: fxProvisional,
            categoryID: transaction.transactionType == .income ? transaction.incomeCategoryRaw : transaction.expenseCategoryRaw,
            note: eventNote ?? transaction.note, sourceTransactionID: operationID,
            originalAmount: originalAmount, originalCurrency: originalCurrency
        )
        modelContext.insert(event)
        invalidate(account, from: transaction.transactionDate)
        try saveBoundary.commit(modelContext, operation: .updateAccount)
        return DebitCardOperationResult(events: [event], cashflowTransaction: transaction, wasAlreadyPersisted: false)
    }

    func commitStagedTransfer(
        _ transaction: CashflowTransaction,
        from source: Account,
        to destination: Account,
        sourceAmount: Decimal,
        destinationAmount: Decimal
    ) throws -> DebitCardOperationResult {
        try CashflowMonthMutationPolicy(modelContext: modelContext).validate(.edit, date: transaction.transactionDate)
        let operationID = try normalizedOperationID(transaction.uniqueID)
        guard source.id != destination.id else { throw DebitCardOperationCoordinatorError.invalidTransferTarget }
        guard let targetProduct = destination.productType, DebitCardContract.products.contains(targetProduct), destination.archivedAt == nil, destination.deletedAt == nil else {
            throw DebitCardOperationCoordinatorError.invalidTransferTarget
        }
        let remainingSourceEvents = try events(for: source).filter { $0.sourceTransactionID != operationID }
        try deleteEvents(operationID: operationID)
        let normalizedSource = try DebitCardContract.validate(account: source, events: remainingSourceEvents, kind: .expense, amount: sourceAmount, on: transaction.transactionDate)
        let normalizedDestination = DebitCurrencyPolicy.round(destinationAmount, currency: destination.currency)
        guard normalizedDestination > 0 else { throw DebitCardContractError.invalidAmount }
        let transferID = UUID()
        let createdAt = Date()
        let out = AccountEvent(account: source, date: transaction.transactionDate, createdAt: createdAt, type: .transferOut, amount: normalizedSource, note: transaction.note, transferID: transferID, sourceTransactionID: operationID)
        let incoming = AccountEvent(account: destination, date: transaction.transactionDate, createdAt: createdAt, type: .transferIn, amount: normalizedDestination, note: transaction.note, transferID: transferID, sourceTransactionID: operationID)
        modelContext.insert(out); modelContext.insert(incoming)
        invalidate(source, from: transaction.transactionDate); invalidate(destination, from: transaction.transactionDate)
        try saveBoundary.commit(modelContext, operation: .updateAccount)
        return DebitCardOperationResult(events: [out, incoming], cashflowTransaction: transaction, wasAlreadyPersisted: false)
    }

    func deleteCashflowGraph(_ transaction: CashflowTransaction) throws {
        try CashflowMonthMutationPolicy(modelContext: modelContext).validate(.delete, date: transaction.transactionDate)
        try deleteEvents(operationID: transaction.uniqueID)
        modelContext.delete(transaction)
        try saveBoundary.commit(modelContext, operation: .updateAccount)
    }

    private func makeCashflow(account: Account, command: DebitCardOperationCommand, amount: Decimal, groupID: String) -> CashflowTransaction {
        let type: CashflowTransactionType
        let projectedAmount: Decimal
        let affectsTotals: Bool
        switch command.kind {
        case .income: type = .income; projectedAmount = amount; affectsTotals = true
        case .expense, .fee: type = .expense; projectedAmount = amount; affectsTotals = true
        case .refund: type = .expense; projectedAmount = -amount; affectsTotals = true
        case .adjustment: type = .balanceAdjustment; projectedAmount = amount; affectsTotals = false
        }
        let transaction = CashflowTransaction(transactionType: type, amount: double(projectedAmount), currency: account.currency, transactionDate: command.date, cardID: account.id.uuidString, incomeCategoryRaw: type == .income ? command.categoryID : nil, expenseCategoryRaw: type == .expense ? command.categoryID : nil, note: command.note, operationGroupID: groupID, affectsCardBalance: false, affectsCashflowTotals: affectsTotals)
        transaction.uniqueID = command.operationID.trimmingCharacters(in: .whitespacesAndNewlines)
        return transaction
    }

    private func validateRefund(originalID: String, amount: Decimal, account: Account) throws -> String {
        let id = try normalizedOperationID(originalID)
        let descriptor = FetchDescriptor<CashflowTransaction>(predicate: #Predicate<CashflowTransaction> { $0.operationGroupID == id })
        let group = try modelContext.fetch(descriptor)
        guard let original = group.first(where: { $0.uniqueID == id && $0.cardID == account.id.uuidString && $0.transactionType == .expense && $0.amount > 0 }) else {
            throw DebitCardOperationCoordinatorError.originalExpenseNotFound
        }
        let refunded = group.filter { $0.amount < 0 }.reduce(Decimal.zero) { $0 + decimal(-$1.amount) }
        guard refunded + amount <= decimal(original.amount) else { throw DebitCardOperationCoordinatorError.refundExceedsExpense }
        return id
    }

    private func existingResult(operationID: String) throws -> DebitCardOperationResult? {
        let events = try modelContext.fetch(FetchDescriptor<AccountEvent>(predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == operationID }))
        let transactions = try modelContext.fetch(FetchDescriptor<CashflowTransaction>(predicate: #Predicate<CashflowTransaction> { $0.uniqueID == operationID }))
        guard !events.isEmpty || !transactions.isEmpty else { return nil }
        guard !events.isEmpty, let transaction = transactions.first, transactions.count == 1 else { throw DebitCardOperationCoordinatorError.duplicateOperationConflict }
        return DebitCardOperationResult(events: events, cashflowTransaction: transaction, wasAlreadyPersisted: true)
    }

    private func deleteEvents(operationID: String) throws {
        let descriptor = FetchDescriptor<AccountEvent>(predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == operationID })
        for event in try modelContext.fetch(descriptor) {
            if let account = event.account { invalidate(account, from: event.date) }
            modelContext.delete(event)
        }
    }

    private func events(for account: Account) throws -> [AccountEvent] {
        let id = account.id
        return try modelContext.fetch(FetchDescriptor<AccountEvent>(predicate: #Predicate<AccountEvent> { $0.account?.id == id }))
    }

    private func invalidate(_ account: Account, from date: Date) { AccountsCoreService(modelContext: modelContext).invalidateSnapshotCache(for: account, from: date) }
    private func normalizedOperationID(_ value: String) throws -> String { let id = value.trimmingCharacters(in: .whitespacesAndNewlines); guard !id.isEmpty else { throw DebitCardOperationCoordinatorError.invalidOperationID }; return id }
    private func eventNote(_ command: DebitCardOperationCommand) -> String? { if case let .adjustment(reason) = command.kind { return reason.trimmingCharacters(in: .whitespacesAndNewlines) }; return command.note }
    private func decimal(_ value: Double) -> Decimal { Decimal(string: String(format: "%.6f", value)) ?? Decimal(value) }
    private func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }
}
