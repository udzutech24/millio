import Foundation
import SwiftData

enum AccountProductTransitionStage: String, CaseIterable {
    case validation, sourceMutation, targetGraph, operationMarker, save
}

enum AccountProductTransitionError: Error, Equatable {
    case missingSource
    case sourceArchived
    case blocked(AccountProductTransitionBlockedReason)
    case duplicateOperationConflict
    case injectedFailure(AccountProductTransitionStage)
}

struct AccountProductCorrectionCommand {
    let operationID: String
    let sourceID: UUID
    let target: AccountProductType
    let targetMetadata: AccountProductMetadata
    let effectiveDate: Date
}

struct AccountProductConversionCommand {
    let operationID: String
    let sourceID: UUID
    let targetID: UUID
    let target: AccountProductType
    let targetMetadata: AccountProductMetadata
    let effectiveDate: Date
}

@MainActor
final class AccountProductTransitionCoordinator {
    typealias StageHook = (AccountProductTransitionStage) throws -> Void
    private static let correctionPrefix = "product-correction:"
    private static let conversionPrefix = "product-conversion:"
    private let container: ModelContainer
    private let saveBoundary: AccountsCoreSaveBoundary

    init(modelContext: ModelContext, saveOperation: @escaping AccountsCoreSaveBoundary.SaveOperation = { try $0.save() }) {
        container = modelContext.container
        saveBoundary = AccountsCoreSaveBoundary(saveOperation: saveOperation)
    }

    func correct(_ command: AccountProductCorrectionCommand, stageHook: StageHook = { _ in }) throws {
        try execute(stageHook: stageHook) { context in
            try stageHook(.validation)
            let source = try fetchAccount(command.sourceID, in: context)
            if let existing = try marker(Self.correctionPrefix + command.operationID, in: context) {
                guard existing.account?.id == source.id,
                      existing.note == command.target.rawValue else { throw AccountProductTransitionError.duplicateOperationConflict }
                return
            }
            guard source.archivedAt == nil, source.deletedAt == nil else { throw AccountProductTransitionError.sourceArchived }
            let events = source.events ?? []
            let decision = AccountProductTransitionPolicy.classify(
                source: source.productType ?? .unknownLegacy, sourceKind: source.kind,
                sourceMetadata: .init(account: source), target: command.target,
                targetMetadata: command.targetMetadata, events: .make(events: events)
            )
            guard decision == .inPlaceCorrection else { throw blocked(decision) }
            try stageHook(.sourceMutation)
            apply(command.targetMetadata, target: command.target, to: source)
            HistoricalValuationRevisionTracker.bump([.accountSet, .financial, .events], on: source)
            try stageHook(.operationMarker)
            context.insert(AccountEvent(
                account: source, date: command.effectiveDate, type: .adjustment, amount: 0,
                note: command.target.rawValue,
                sourceTransactionID: Self.correctionPrefix + command.operationID
            ))
        }
    }

    func convert(_ command: AccountProductConversionCommand, stageHook: StageHook = { _ in }) throws {
        try execute(stageHook: stageHook) { context in
            try stageHook(.validation)
            let source = try fetchAccount(command.sourceID, in: context)
            let operationKey = Self.conversionPrefix + command.operationID
            if let existing = try marker(operationKey, in: context) {
                guard existing.account?.id == command.targetID,
                      existing.note == command.sourceID.uuidString else { throw AccountProductTransitionError.duplicateOperationConflict }
                return
            }
            guard source.archivedAt == nil, source.deletedAt == nil else { throw AccountProductTransitionError.sourceArchived }
            let decision = AccountProductTransitionPolicy.classify(
                source: source.productType ?? .unknownLegacy, sourceKind: source.kind,
                sourceMetadata: .init(account: source), target: command.target,
                targetMetadata: command.targetMetadata,
                events: .make(events: source.events ?? [])
            )
            guard decision == .replacementConversion else { throw blocked(decision) }
            let replayEvents = (source.events ?? []).filter { event in
                guard source.productType == .deposit else { return true }
                return event.sourceTransactionID?.hasPrefix("deposit-interest:\(source.id.uuidString):") != true
            }
            let balance = AccountBalanceEngine.balanceAt(
                events: replayEvents, kind: source.kind, on: command.effectiveDate
            )
            try stageHook(.sourceMutation)
            source.archivedAt = command.effectiveDate
            HistoricalValuationRevisionTracker.bump([.accountSet, .financial], on: source)
            try stageHook(.targetGraph)
            let graph = try AccountProductGraphBuilder.build(.init(
                accountID: command.targetID, productType: command.target, name: source.name,
                currency: source.currency, openingBalance: balance, includeInTotal: source.includeInTotal,
                order: source.order, groupID: source.group?.id, metadata: command.targetMetadata,
                note: source.note, date: command.effectiveDate
            ), in: context)
            try stageHook(.operationMarker)
            graph.openingEvent.sourceTransactionID = operationKey
            graph.openingEvent.note = command.sourceID.uuidString
        }
    }

    private func execute(stageHook: StageHook, mutation: (ModelContext) throws -> Void) throws {
        let context = ModelContext(container); context.autosaveEnabled = false
        do {
            try mutation(context)
            try stageHook(.save)
            try saveBoundary.commit(context, operation: .updateAccount)
        } catch { context.rollback(); throw error }
    }

    private func fetchAccount(_ id: UUID, in context: ModelContext) throws -> Account {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
        guard let account = try context.fetch(descriptor).first else { throw AccountProductTransitionError.missingSource }
        return account
    }

    private func marker(_ key: String, in context: ModelContext) throws -> AccountEvent? {
        let descriptor = FetchDescriptor<AccountEvent>(predicate: #Predicate { $0.sourceTransactionID == key })
        return try context.fetch(descriptor).first
    }

    private func blocked(_ decision: AccountProductTransitionKind) -> AccountProductTransitionError {
        if case let .blocked(reason) = decision { return .blocked(reason) }
        return .blocked(.unsupportedConversion)
    }

    private func apply(_ metadata: AccountProductMetadata, target: AccountProductType, to account: Account) {
        account.productType = target
        account.kind = ProductDefinitionCatalog.definition(for: target).canonicalKind!
        account.cardMeta = metadata.card; account.depositMeta = metadata.deposit
        account.loanMeta = metadata.loan; account.debtMeta = metadata.debt
        account.marketMeta = metadata.market; account.manualAssetMeta = metadata.manualAsset
    }
}
