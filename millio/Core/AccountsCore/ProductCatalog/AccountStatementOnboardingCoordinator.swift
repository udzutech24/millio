import CryptoKit
import Foundation
import SwiftData

enum AccountStatementBalanceConfirmation: Equatable {
    case bankDeclared(amount: Decimal, currency: String, asOf: Date, source: String)
    case manual(amount: Decimal, currency: String, asOf: Date)

    var amount: Decimal {
        switch self {
        case .bankDeclared(let amount, _, _, _), .manual(let amount, _, _): amount
        }
    }

    var currency: String {
        switch self {
        case .bankDeclared(_, let currency, _, _), .manual(_, let currency, _): currency
        }
    }

    var asOf: Date {
        switch self {
        case .bankDeclared(_, _, let asOf, _), .manual(_, _, let asOf): asOf
        }
    }
}

struct AccountStatementOnboardingCommand {
    let create: CreateProductCommand
    let operations: [CashflowApprovedStatementOperation]
    let balanceConfirmation: AccountStatementBalanceConfirmation
    let statementPeriodFrom: Date
    let statementPeriodTo: Date
    let onboardingID: String
}

struct AccountStatementOnboardingResult: Equatable {
    let accountID: UUID
    let insertedFingerprints: Set<String>
    let skippedFingerprints: Set<String>
    let wasAlreadyApplied: Bool
}

enum AccountStatementOnboardingStage: String, CaseIterable {
    case validation
    case existingCheck
    case accountGraph
    case statementRows
}

enum AccountStatementOnboardingError: Error, Equatable {
    case invalidOnboardingID
    case unsupportedProduct
    case invalidStatementPeriod
    case operationOutsideStatementPeriod
    case currencyMismatch
    case balanceMismatch
    case operationAccountMismatch
    case invalidOperation
    case duplicateFingerprint
    case closedMonth
    case attributionConflict(String)
    case idempotencyConflict
    case injectedFailure(AccountStatementOnboardingStage)
}

/// Creates the account anchor and reviewed Cashflow projections in the factory's disposable
/// context. The synchronous `@MainActor` boundary serializes local interactive writers; stable IDs
/// and a payload marker make retries converge without adding a SwiftData schema solely for this flow.
@MainActor
final class AccountStatementOnboardingCoordinator {
    typealias StageHook = (AccountStatementOnboardingStage) throws -> Void

    private let modelContext: ModelContext
    private let factory: AccountProductFactory
    private let calendar: Calendar

    init(
        modelContext: ModelContext,
        calendar: Calendar = .autoupdatingCurrent,
        saveOperation: @escaping AccountsCoreSaveBoundary.SaveOperation = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.factory = AccountProductFactory(modelContext: modelContext, saveOperation: saveOperation)
        self.calendar = calendar
    }

    func apply(
        _ command: AccountStatementOnboardingCommand,
        stageHook: StageHook = { _ in }
    ) throws -> AccountStatementOnboardingResult {
        try stageHook(.validation)
        let normalizedID = command.onboardingID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { throw AccountStatementOnboardingError.invalidOnboardingID }
        try validate(command)

        let markerKey = "statement-onboarding:\(normalizedID)"
        let payloadDigest = try Self.payloadDigest(command)
        try stageHook(.existingCheck)
        if let existing = try existingResult(
            markerKey: markerKey,
            payloadDigest: payloadDigest,
            command: command
        ) {
            return existing
        }

        var stagedResult = CashflowStatementApplyResult(
            insertedFingerprints: [],
            skippedFingerprints: []
        )
        let accountID = try factory.create(command.create) { graph, context in
            try stageHook(.accountGraph)
            graph.openingEvent.id = Self.deterministicUUID("\(markerKey):opening")
            graph.openingEvent.sourceTransactionID = markerKey
            graph.openingEvent.note = payloadDigest

            try stageHook(.statementRows)
            do {
                stagedResult = try CashflowStatementStagingService(modelContext: context).stage(
                    command.operations,
                    duplicatePolicy: .requireMatchingAccount(command.create.accountID.uuidString)
                )
            } catch let error as CashflowStatementStagingError {
                throw Self.map(error)
            }
        }

        return .init(
            accountID: accountID,
            insertedFingerprints: stagedResult.insertedFingerprints,
            skippedFingerprints: stagedResult.skippedFingerprints,
            wasAlreadyApplied: false
        )
    }

    private func validate(_ command: AccountStatementOnboardingCommand) throws {
        guard command.create.productType == .debitCard || command.create.productType == .bankAccount else {
            throw AccountStatementOnboardingError.unsupportedProduct
        }
        guard command.statementPeriodFrom <= command.statementPeriodTo,
              calendar.isDate(command.statementPeriodFrom, equalTo: command.statementPeriodTo, toGranularity: .month) else {
            throw AccountStatementOnboardingError.invalidStatementPeriod
        }
        guard command.operations.allSatisfy({
            $0.date >= command.statementPeriodFrom && $0.date <= command.statementPeriodTo
        }) else {
            throw AccountStatementOnboardingError.operationOutsideStatementPeriod
        }

        let currency = command.create.currency.uppercased()
        guard command.balanceConfirmation.currency.uppercased() == currency,
              command.operations.allSatisfy({ $0.currency.uppercased() == currency }) else {
            throw AccountStatementOnboardingError.currencyMismatch
        }
        guard command.balanceConfirmation.amount == command.create.openingBalance,
              calendar.isDate(command.balanceConfirmation.asOf, inSameDayAs: command.create.date) else {
            throw AccountStatementOnboardingError.balanceMismatch
        }
        guard command.operations.allSatisfy({ $0.accountID == command.create.accountID.uuidString }) else {
            throw AccountStatementOnboardingError.operationAccountMismatch
        }
    }

    private func existingResult(
        markerKey: String,
        payloadDigest: String,
        command: AccountStatementOnboardingCommand
    ) throws -> AccountStatementOnboardingResult? {
        let markers = try modelContext.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate { $0.sourceTransactionID == markerKey }
        ))
        guard !markers.isEmpty else { return nil }
        guard markers.count == 1,
              let marker = markers.first,
              marker.note == payloadDigest,
              marker.type == .openingBalance,
              marker.account?.id == command.create.accountID else {
            throw AccountStatementOnboardingError.idempotencyConflict
        }

        let requested = Set(command.operations.map(\.fingerprint))
        let imported = try modelContext.fetch(FetchDescriptor<CashflowTransaction>()).filter {
            $0.importSourceRaw == CashflowStatementStagingService.importSource
                && $0.cardID == command.create.accountID.uuidString
                && $0.importReferenceKey.map(requested.contains) == true
        }
        guard Set(imported.compactMap(\.importReferenceKey)) == requested else {
            throw AccountStatementOnboardingError.idempotencyConflict
        }
        return .init(
            accountID: command.create.accountID,
            insertedFingerprints: [],
            skippedFingerprints: requested,
            wasAlreadyApplied: true
        )
    }

    private static func map(_ error: CashflowStatementStagingError) -> AccountStatementOnboardingError {
        switch error {
        case .invalidOperation: .invalidOperation
        case .duplicateFingerprint: .duplicateFingerprint
        case .closedMonth: .closedMonth
        case .attributionConflict(let fingerprint): .attributionConflict(fingerprint)
        }
    }

    private static func payloadDigest(_ command: AccountStatementOnboardingCommand) throws -> String {
        struct Payload: Encodable {
            struct Operation: Encodable {
                let fingerprint: String
                let date: TimeInterval
                let amount: String
                let currency: String
                let type: String
                let category: String
                let accountID: String?
            }
            let accountID: String
            let productType: String
            let name: String
            let currency: String
            let openingBalance: String
            let includeInTotal: Bool
            let order: Int
            let groupID: String?
            let note: String?
            let date: TimeInterval
            let card: CardMeta?
            let balanceKind: String
            let balanceAmount: String
            let balanceCurrency: String
            let balanceDate: TimeInterval
            let balanceSource: String?
            let periodFrom: TimeInterval
            let periodTo: TimeInterval
            let operations: [Operation]
        }

        let balanceKind: String
        let balanceSource: String?
        switch command.balanceConfirmation {
        case .bankDeclared(_, _, _, let source):
            balanceKind = "bank_declared"
            balanceSource = source
        case .manual:
            balanceKind = "manual"
            balanceSource = nil
        }
        let payload = Payload(
            accountID: command.create.accountID.uuidString,
            productType: command.create.productType.rawValue,
            name: command.create.name,
            currency: command.create.currency.uppercased(),
            openingBalance: NSDecimalNumber(decimal: command.create.openingBalance).stringValue,
            includeInTotal: command.create.includeInTotal,
            order: command.create.order,
            groupID: command.create.groupID?.uuidString,
            note: command.create.note,
            date: command.create.date.timeIntervalSince1970,
            card: command.create.metadata.card,
            balanceKind: balanceKind,
            balanceAmount: NSDecimalNumber(decimal: command.balanceConfirmation.amount).stringValue,
            balanceCurrency: command.balanceConfirmation.currency.uppercased(),
            balanceDate: command.balanceConfirmation.asOf.timeIntervalSince1970,
            balanceSource: balanceSource,
            periodFrom: command.statementPeriodFrom.timeIntervalSince1970,
            periodTo: command.statementPeriodTo.timeIntervalSince1970,
            operations: command.operations.map {
                .init(
                    fingerprint: $0.fingerprint,
                    date: $0.date.timeIntervalSince1970,
                    amount: NSDecimalNumber(decimal: $0.amount).stringValue,
                    currency: $0.currency.uppercased(),
                    type: $0.type.rawValue,
                    category: $0.categoryRaw,
                    accountID: $0.accountID
                )
            }.sorted { $0.fingerprint < $1.fingerprint }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(payload)).map { String(format: "%02x", $0) }.joined()
    }

    private static func deterministicUUID(_ value: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let tuple: uuid_t = (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: tuple)
    }
}
