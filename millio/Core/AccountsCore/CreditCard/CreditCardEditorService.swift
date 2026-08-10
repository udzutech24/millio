import Foundation
import SwiftData

enum CreditCardEditorError: Error, Equatable {
    case readOnly
    case invalidName
    case invalidLast4
    case invalidCreditLimit
    case invalidStatementDay
    case invalidDueDay
    case invalidMinimumPayment
    case invalidGracePeriod
}

struct CreditCardEditCommand {
    let name: String
    let group: AccountGroup?
    let note: String?
    let includeInTotal: Bool
    let bank: String?
    let last4: String?
    let creditLimit: Decimal
    let statementDay: Int?
    let dueDay: Int?
    let minPayment: Decimal?
    let graceDays: Int?
}

enum CreditCardEditPolicy {
    static func normalizedLast4(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count == 4, trimmed.allSatisfy(\.isNumber) else {
            throw CreditCardEditorError.invalidLast4
        }
        return trimmed
    }

    static func validate(_ command: CreditCardEditCommand) throws -> CardMeta {
        guard !command.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CreditCardEditorError.invalidName
        }
        guard command.creditLimit > 0 else { throw CreditCardEditorError.invalidCreditLimit }
        guard command.statementDay.map({ (1...31).contains($0) }) ?? true else {
            throw CreditCardEditorError.invalidStatementDay
        }
        guard command.dueDay.map({ (1...31).contains($0) }) ?? true else {
            throw CreditCardEditorError.invalidDueDay
        }
        guard command.minPayment.map({ $0 > 0 }) ?? true else {
            throw CreditCardEditorError.invalidMinimumPayment
        }
        guard command.graceDays.map({ (1...365).contains($0) }) ?? true else {
            throw CreditCardEditorError.invalidGracePeriod
        }
        return CardMeta(
            bank: normalizedOptional(command.bank),
            last4: try normalizedLast4(command.last4),
            creditLimit: command.creditLimit,
            statementDay: command.statementDay,
            dueDay: command.dueDay,
            minPayment: command.minPayment,
            graceDays: command.graceDays,
            overdraftLimit: nil
        )
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
struct CreditCardEditorService {
    let modelContext: ModelContext
    var saveOperation: (ModelContext) throws -> Void = { try $0.save() }

    func update(account: Account, command: CreditCardEditCommand) throws {
        guard !modelContext.hasChanges else { throw AccountsCoreServiceError.dirtyContext }
        guard account.productType == .creditCard else { throw AccountsCoreServiceError.missingProductIdentity }
        guard account.archivedAt == nil, account.deletedAt == nil else { throw CreditCardEditorError.readOnly }
        let metadata = try CreditCardEditPolicy.validate(command)
        try ProductDefinitionCatalog.validateStoredIdentity(
            .creditCard,
            kindRaw: account.kindRaw,
            metadata: .init(card: metadata),
            migrationReason: nil
        )

        account.name = command.name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.group = command.group
        let note = command.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        account.note = note.isEmpty ? nil : note
        account.includeInTotal = command.includeInTotal
        account.cardMeta = metadata
        HistoricalValuationRevisionTracker.bump([.accountSet, .financial], on: account)
        do {
            try saveOperation(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
