import Foundation
import SwiftData

enum DepositOperationError: Error, Equatable {
    case invalidOperationID
    case invalidAmount
    case accountNotFound(UUID)
    case invalidDeposit
    case missingMetadata
    case inactiveDeposit
    case topUpNotAllowed
    case earlyCloseNotAllowed
    case withdrawalUnsupported
    case invalidCounterparty
    case currencyMismatch
    case insufficientFunds
    case invalidTerms
    case notMatured
    case duplicateOperationConflict
}

enum DepositOperationStage: String, CaseIterable {
    case validation
    case load
    case futureCleanup
    case metadata
    case primaryEvent
    case penalty
    case transferOut
    case transferIn
    case schedule
    case archive
    case save
}

struct DepositTopUpCommand {
    let operationID: String
    let sourceAccountID: UUID
    let amount: Decimal
    let date: Date
    let note: String?

    init(
        operationID: String,
        sourceAccountID: UUID,
        amount: Decimal,
        date: Date = Date(),
        note: String? = nil
    ) {
        self.operationID = operationID
        self.sourceAccountID = sourceAccountID
        self.amount = amount
        self.date = date
        self.note = note
    }
}

struct DepositInterestConfirmationCommand {
    let operationID: String
    let amount: Decimal
    let date: Date
    let note: String?

    init(operationID: String, amount: Decimal, date: Date, note: String? = nil) {
        self.operationID = operationID
        self.amount = amount
        self.date = date
        self.note = note
    }
}

struct DepositTermsEditCommand {
    let meta: DepositMeta
    let effectiveDate: Date
    let calendar: Calendar

    init(
        meta: DepositMeta,
        effectiveDate: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.meta = meta
        self.effectiveDate = effectiveDate
        self.calendar = calendar
    }
}

struct DepositTransferCommand {
    let operationID: String
    let destinationAccountID: UUID
    let date: Date
    let note: String?

    init(
        operationID: String,
        destinationAccountID: UUID,
        date: Date = Date(),
        note: String? = nil
    ) {
        self.operationID = operationID
        self.destinationAccountID = destinationAccountID
        self.date = date
        self.note = note
    }
}

struct DepositRolloverCommand {
    let operationID: String
    let meta: DepositMeta
    let date: Date
    let calendar: Calendar

    init(
        operationID: String,
        meta: DepositMeta,
        date: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.operationID = operationID
        self.meta = meta
        self.date = date
        self.calendar = calendar
    }
}

struct DepositOperationResult: Equatable {
    let operationID: String?
    let eventIDs: [UUID]
    let wasAlreadyPersisted: Bool
}

/// Sole atomic writer for deposit-specific operations. Every command resolves persisted IDs in a
/// disposable context and performs one outer commit; failed graphs can never leak into the caller.
@MainActor
final class DepositOperationCoordinator {
    typealias StageHook = (DepositOperationStage) throws -> Void

    private let container: ModelContainer
    private let saveBoundary: AccountsCoreSaveBoundary
    private let publishCommitted: () -> Void

    init(
        modelContext: ModelContext,
        saveOperation: @escaping AccountsCoreSaveBoundary.SaveOperation = { try $0.save() },
        publishCommitted: (() -> Void)? = nil
    ) {
        self.container = modelContext.container
        self.saveBoundary = AccountsCoreSaveBoundary(saveOperation: saveOperation)
        self.publishCommitted = publishCommitted ?? {
            EventBus.shared.publish(FinanceEvent.depositOperationCommitted)
        }
    }

    func topUp(
        depositID: UUID,
        command: DepositTopUpCommand,
        calendar: Calendar = Calendar(identifier: .gregorian),
        stageHook: StageHook = { _ in }
    ) throws -> DepositOperationResult {
        try execute(stageHook: stageHook) { context in
            try stageHook(.validation)
            try validateAmount(command.amount)
            let operationID = try normalizedOperationID(command.operationID)
            try stageHook(.load)
            let deposit = try loadDeposit(depositID, in: context)
            if let existing = try existingEvents(operationID: operationID, in: context) {
                guard existing.count == 2,
                      existing.contains(where: { $0.account?.id == depositID && $0.type == .transferIn && $0.amount == command.amount }),
                      existing.contains(where: { $0.account?.id == command.sourceAccountID && $0.type == .transferOut && $0.amount == command.amount }) else {
                    throw DepositOperationError.duplicateOperationConflict
                }
                return persistedResult(operationID: operationID, events: existing)
            }
            let meta = try activeMeta(for: deposit, on: command.date)
            guard meta.allowsTopUp else { throw DepositOperationError.topUpNotAllowed }
            let source = try loadAccount(command.sourceAccountID, in: context)
            try validateCounterparty(source, deposit: deposit, amount: command.amount, on: command.date, context: context)

            let transferID = UUID()
            let createdAt = Date()
            try stageHook(.transferOut)
            let out = AccountEvent(
                account: source, date: command.date, createdAt: createdAt, type: .transferOut,
                amount: command.amount, note: command.note, transferID: transferID,
                sourceTransactionID: operationID
            )
            context.insert(out)
            try stageHook(.transferIn)
            let incoming = AccountEvent(
                account: deposit, date: command.date, createdAt: createdAt, type: .transferIn,
                amount: command.amount, note: command.note, transferID: transferID,
                sourceTransactionID: operationID
            )
            context.insert(incoming)
            try rebuildFutureSchedule(
                for: deposit, meta: meta, after: command.date, calendar: calendar,
                context: context, stageHook: stageHook
            )
            invalidate(source, from: command.date, in: context)
            invalidate(deposit, from: command.date, in: context)
            return DepositOperationResult(
                operationID: operationID, eventIDs: [out.id, incoming.id], wasAlreadyPersisted: false
            )
        }
    }

    func withdraw(depositID: UUID, command: DepositTransferCommand) throws -> DepositOperationResult {
        _ = depositID
        _ = command
        throw DepositOperationError.withdrawalUnsupported
    }

    func confirmInterest(
        depositID: UUID,
        command: DepositInterestConfirmationCommand,
        calendar: Calendar = Calendar(identifier: .gregorian),
        stageHook: StageHook = { _ in }
    ) throws -> DepositOperationResult {
        try execute(stageHook: stageHook) { context in
            try stageHook(.validation)
            try validateAmount(command.amount)
            let operationID = try normalizedOperationID(command.operationID)
            try stageHook(.load)
            let deposit = try loadDeposit(depositID, in: context)
            if let existing = try existingEvents(operationID: operationID, in: context) {
                guard existing.count == 1,
                      existing[0].account?.id == depositID,
                      existing[0].type == .interest,
                      existing[0].amount == command.amount,
                      calendar.isDate(existing[0].date, inSameDayAs: command.date) else {
                    throw DepositOperationError.duplicateOperationConflict
                }
                return persistedResult(operationID: operationID, events: existing)
            }
            let meta = try mutableMeta(for: deposit)
            try stageHook(.futureCleanup)
            let events = try events(for: deposit, in: context)
            for event in events where isGenerated(event, accountID: deposit.id)
                && calendar.isDate(event.date, inSameDayAs: command.date) {
                context.delete(event)
            }
            try stageHook(.primaryEvent)
            let confirmed = AccountEvent(
                account: deposit, date: command.date, type: .interest, amount: command.amount,
                note: command.note, sourceTransactionID: operationID
            )
            context.insert(confirmed)
            _ = try DepositCashflowProjector.project(
                events: [confirmed], through: command.date, context: context
            )
            try rebuildFutureSchedule(
                for: deposit, meta: meta, after: command.date, calendar: calendar,
                context: context, stageHook: stageHook
            )
            invalidate(deposit, from: command.date, in: context)
            return DepositOperationResult(
                operationID: operationID, eventIDs: [confirmed.id], wasAlreadyPersisted: false
            )
        }
    }

    func editTerms(
        depositID: UUID,
        command: DepositTermsEditCommand,
        stageHook: StageHook = { _ in }
    ) throws -> DepositOperationResult {
        try execute(stageHook: stageHook) { context in
            try stageHook(.validation)
            try validateTerms(command.meta, openingDate: nil, effectiveDate: command.effectiveDate)
            try stageHook(.load)
            let deposit = try loadDeposit(depositID, in: context)
            _ = try activeMeta(for: deposit, on: command.effectiveDate)
            try validateTerms(command.meta, openingDate: deposit.createdAt, effectiveDate: command.effectiveDate)
            try stageHook(.metadata)
            deposit.depositMeta = command.meta
            try rebuildFutureSchedule(
                for: deposit, meta: command.meta, after: command.effectiveDate,
                calendar: command.calendar, context: context, stageHook: stageHook
            )
            HistoricalValuationRevisionTracker.bump([.financial], on: deposit)
            return DepositOperationResult(operationID: nil, eventIDs: [], wasAlreadyPersisted: false)
        }
    }

    func earlyClose(
        depositID: UUID,
        command: DepositTransferCommand,
        stageHook: StageHook = { _ in }
    ) throws -> DepositOperationResult {
        try close(
            depositID: depositID, command: command, requiresMaturity: false,
            stageHook: stageHook
        )
    }

    func mature(
        depositID: UUID,
        command: DepositTransferCommand,
        stageHook: StageHook = { _ in }
    ) throws -> DepositOperationResult {
        try close(
            depositID: depositID, command: command, requiresMaturity: true,
            stageHook: stageHook
        )
    }

    func rollover(
        depositID: UUID,
        command: DepositRolloverCommand,
        stageHook: StageHook = { _ in }
    ) throws -> DepositOperationResult {
        try execute(stageHook: stageHook) { context in
            try stageHook(.validation)
            let operationID = try normalizedOperationID(command.operationID)
            try stageHook(.load)
            let deposit = try loadDeposit(depositID, in: context)
            if let existing = try existingEvents(operationID: operationID, in: context) {
                guard existing.count == 1, existing[0].account?.id == depositID,
                      existing[0].type == .rollover,
                      existing[0].date == command.date,
                      deposit.depositMeta == command.meta else {
                    throw DepositOperationError.duplicateOperationConflict
                }
                return persistedResult(operationID: operationID, events: existing)
            }
            let oldMeta = try mutableMeta(for: deposit)
            guard let oldTerm = oldMeta.termEnd, oldTerm <= command.date else {
                throw DepositOperationError.notMatured
            }
            try validateTerms(command.meta, openingDate: deposit.createdAt, effectiveDate: command.date)
            guard let newTerm = command.meta.termEnd, newTerm > command.date else {
                throw DepositOperationError.invalidTerms
            }
            try stageHook(.metadata)
            deposit.depositMeta = command.meta
            try stageHook(.primaryEvent)
            let event = AccountEvent(
                account: deposit, date: command.date, type: .rollover,
                sourceTransactionID: operationID
            )
            context.insert(event)
            try rebuildFutureSchedule(
                for: deposit, meta: command.meta, after: command.date,
                calendar: command.calendar, context: context, stageHook: stageHook
            )
            invalidate(deposit, from: command.date, in: context)
            return DepositOperationResult(
                operationID: operationID, eventIDs: [event.id], wasAlreadyPersisted: false
            )
        }
    }

    private func close(
        depositID: UUID,
        command: DepositTransferCommand,
        requiresMaturity: Bool,
        stageHook: StageHook
    ) throws -> DepositOperationResult {
        try execute(stageHook: stageHook) { context in
            try stageHook(.validation)
            let operationID = try normalizedOperationID(command.operationID)
            try stageHook(.load)
            let deposit = try loadDeposit(depositID, in: context)
            if let existing = try existingEvents(operationID: operationID, in: context) {
                guard deposit.archivedAt != nil,
                      existing.contains(where: { $0.account?.id == depositID && $0.type == .transferOut }),
                      existing.contains(where: { $0.account?.id == command.destinationAccountID && $0.type == .transferIn }),
                      existing.allSatisfy({ $0.date == command.date }) else {
                    throw DepositOperationError.duplicateOperationConflict
                }
                return persistedResult(operationID: operationID, events: existing)
            }
            let meta = try activeMeta(for: deposit, on: command.date, allowMatured: requiresMaturity)
            if requiresMaturity {
                guard let termEnd = meta.termEnd, termEnd <= command.date else {
                    throw DepositOperationError.notMatured
                }
            } else {
                guard meta.allowsEarlyClose else { throw DepositOperationError.earlyCloseNotAllowed }
                if let termEnd = meta.termEnd, termEnd <= command.date {
                    throw DepositOperationError.notMatured
                }
            }
            let destination = try loadAccount(command.destinationAccountID, in: context)
            try validateDestination(destination, deposit: deposit)

            try stageHook(.futureCleanup)
            let allEvents = try events(for: deposit, in: context)
            for event in allEvents where isGenerated(event, accountID: deposit.id) && event.date > command.date {
                context.delete(event)
            }
            let confirmedEvents = allEvents.filter { !isGenerated($0, accountID: deposit.id) }
            var balance = AccountBalanceEngine.balanceAt(
                events: confirmedEvents, kind: .deposit, on: command.date
            )
            var eventIDs: [UUID] = []
            if !requiresMaturity,
               let penaltyShare = meta.earlyClosePenalty,
               penaltyShare > 0 {
                let confirmedInterest = confirmedEvents.reduce(Decimal.zero) { result, event in
                    result + (event.type == .interest && event.date <= command.date ? (event.amount ?? 0) : 0)
                }
                let penalty = DepositInterestScheduler.round2(confirmedInterest * penaltyShare)
                if penalty > 0 {
                    try stageHook(.penalty)
                    let fee = AccountEvent(
                        account: deposit, date: command.date, type: .fee, amount: penalty,
                        note: "early_close_penalty", sourceTransactionID: operationID
                    )
                    context.insert(fee)
                    eventIDs.append(fee.id)
                    balance -= penalty
                }
            }
            guard balance >= 0 else { throw DepositOperationError.insufficientFunds }
            if balance > 0 {
                let transferID = UUID()
                let createdAt = Date()
                try stageHook(.transferOut)
                let out = AccountEvent(
                    account: deposit, date: command.date, createdAt: createdAt, type: .transferOut,
                    amount: balance, note: command.note, transferID: transferID,
                    sourceTransactionID: operationID
                )
                context.insert(out)
                try stageHook(.transferIn)
                let incoming = AccountEvent(
                    account: destination, date: command.date, createdAt: createdAt, type: .transferIn,
                    amount: balance, note: command.note, transferID: transferID,
                    sourceTransactionID: operationID
                )
                context.insert(incoming)
                eventIDs.append(contentsOf: [out.id, incoming.id])
            }
            try stageHook(.archive)
            deposit.archivedAt = command.date
            invalidate(deposit, from: command.date, in: context)
            invalidate(destination, from: command.date, in: context)
            return DepositOperationResult(
                operationID: operationID, eventIDs: eventIDs, wasAlreadyPersisted: false
            )
        }
    }

    private func execute(
        stageHook: StageHook,
        body: (ModelContext) throws -> DepositOperationResult
    ) throws -> DepositOperationResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let result = try body(context)
            if result.wasAlreadyPersisted { return result }
            try stageHook(.save)
            try saveBoundary.commit(context, operation: .updateAccount)
            publishCommitted()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    private func rebuildFutureSchedule(
        for deposit: Account,
        meta: DepositMeta,
        after date: Date,
        calendar: Calendar,
        context: ModelContext,
        stageHook: StageHook
    ) throws {
        try stageHook(.futureCleanup)
        let allEvents = try events(for: deposit, in: context)
        for event in allEvents where isGenerated(event, accountID: deposit.id) && event.date > date {
            context.delete(event)
        }
        let confirmedEvents = allEvents.filter { !isGenerated($0, accountID: deposit.id) }
        try stageHook(.schedule)
        let drafts = DepositInterestScheduler.buildFutureSchedule(
            accountID: deposit.id,
            meta: meta,
            openingDate: deposit.createdAt,
            confirmedEvents: confirmedEvents,
            after: date,
            calendar: calendar
        )
        for draft in drafts {
            context.insert(AccountEvent(
                account: deposit, date: draft.date, type: .interest, amount: draft.amount,
                sourceTransactionID: draft.sourceTransactionID
            ))
        }
    }

    private func validateAmount(_ amount: Decimal) throws {
        guard !amount.isNaN, amount > 0 else { throw DepositOperationError.invalidAmount }
    }

    private func validateTerms(
        _ meta: DepositMeta,
        openingDate: Date?,
        effectiveDate: Date
    ) throws {
        guard !meta.rate.isNaN, meta.rate > 0,
              meta.payoutDay.map({ (1...31).contains($0) }) ?? true,
              meta.earlyClosePenalty.map({ $0 >= 0 && $0 <= 1 }) ?? true,
              meta.allowsEarlyClose || meta.earlyClosePenalty == nil,
              meta.termEnd.map({ $0 > effectiveDate }) ?? true,
              openingDate.map({ opening in meta.termEnd.map({ $0 > opening }) ?? true }) ?? true,
              !meta.autoRollover || meta.termEnd != nil,
              !meta.remindEnd || meta.termEnd != nil else {
            throw DepositOperationError.invalidTerms
        }
    }

    private func activeMeta(
        for account: Account,
        on date: Date,
        allowMatured: Bool = false
    ) throws -> DepositMeta {
        let meta = try mutableMeta(for: account)
        guard account.archivedAt == nil, account.deletedAt == nil else {
            throw DepositOperationError.inactiveDeposit
        }
        if !allowMatured, let termEnd = meta.termEnd, termEnd <= date {
            throw DepositOperationError.inactiveDeposit
        }
        return meta
    }

    private func mutableMeta(for account: Account) throws -> DepositMeta {
        guard account.productType == .deposit, account.kind == .deposit else {
            throw DepositOperationError.invalidDeposit
        }
        guard let meta = account.depositMeta else { throw DepositOperationError.missingMetadata }
        return meta
    }

    private func loadDeposit(_ id: UUID, in context: ModelContext) throws -> Account {
        let account = try loadAccount(id, in: context)
        guard account.productType == .deposit, account.kind == .deposit else {
            throw DepositOperationError.invalidDeposit
        }
        return account
    }

    private func loadAccount(_ id: UUID, in context: ModelContext) throws -> Account {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == id })
        guard let account = try context.fetch(descriptor).first else {
            throw DepositOperationError.accountNotFound(id)
        }
        return account
    }

    private func validateCounterparty(
        _ source: Account,
        deposit: Account,
        amount: Decimal,
        on date: Date,
        context: ModelContext
    ) throws {
        try validateDestination(source, deposit: deposit)
        let allowed: Set<AccountProductType> = [.cash, .debitCard, .bankAccount]
        guard allowed.contains(source.productType ?? .unknownLegacy) else {
            throw DepositOperationError.invalidCounterparty
        }
        let balance = AccountBalanceEngine.balanceAt(
            events: try events(for: source, in: context), kind: source.kind, on: date
        )
        guard balance >= amount else { throw DepositOperationError.insufficientFunds }
    }

    private func validateDestination(_ destination: Account, deposit: Account) throws {
        guard destination.id != deposit.id,
              destination.archivedAt == nil,
              destination.deletedAt == nil else {
            throw DepositOperationError.invalidCounterparty
        }
        guard destination.currency.uppercased() == deposit.currency.uppercased() else {
            throw DepositOperationError.currencyMismatch
        }
    }

    private func events(for account: Account, in context: ModelContext) throws -> [AccountEvent] {
        let id = account.id
        return try context.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.account?.id == id }
        ))
    }

    private func existingEvents(operationID: String, in context: ModelContext) throws -> [AccountEvent]? {
        let descriptor = FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == operationID }
        )
        let events = try context.fetch(descriptor)
        return events.isEmpty ? nil : events
    }

    private func persistedResult(operationID: String, events: [AccountEvent]) -> DepositOperationResult {
        DepositOperationResult(
            operationID: operationID,
            eventIDs: events.map(\.id).sorted { $0.uuidString < $1.uuidString },
            wasAlreadyPersisted: true
        )
    }

    private func normalizedOperationID(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !normalized.hasPrefix("deposit-interest:") else {
            throw DepositOperationError.invalidOperationID
        }
        return normalized
    }

    private func isGenerated(_ event: AccountEvent, accountID: UUID) -> Bool {
        event.type == .interest
            && (event.sourceTransactionID?.hasPrefix("deposit-interest:\(accountID.uuidString):") ?? false)
    }

    private func invalidate(_ account: Account, from date: Date, in context: ModelContext) {
        AccountsCoreService(modelContext: context).invalidateSnapshotCache(for: account, from: date)
    }
}
