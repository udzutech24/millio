import Foundation
import SwiftData

enum CashflowStatementDuplicatePolicy: Equatable {
    /// Existing Cashflow import behavior: a bank fingerprint already present in the store is skipped.
    case skipAnyExisting
    /// Account onboarding must not silently steal a row already attributed elsewhere.
    case requireMatchingAccount(String)
}

enum CashflowStatementStagingError: Error, Equatable {
    case invalidOperation
    case duplicateFingerprint
    case closedMonth
    case attributionConflict(String)
}

/// Persistence-neutral statement writer. It validates and inserts into a caller-owned context but
/// never saves, rolls back, publishes category learning or refreshes UI caches.
@MainActor
struct CashflowStatementStagingService {
    static let importSource = "bank_statement_v1"

    let modelContext: ModelContext
    private let mutationPolicy: CashflowMonthMutationPolicy

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.mutationPolicy = CashflowMonthMutationPolicy(modelContext: modelContext)
    }

    func stage(
        _ operations: [CashflowApprovedStatementOperation],
        duplicatePolicy: CashflowStatementDuplicatePolicy
    ) throws -> CashflowStatementApplyResult {
        let fingerprints = operations.map(\.fingerprint)
        guard Set(fingerprints).count == fingerprints.count else {
            throw CashflowStatementStagingError.duplicateFingerprint
        }
        guard operations.allSatisfy(Self.isValid) else {
            throw CashflowStatementStagingError.invalidOperation
        }
        for operation in operations {
            do {
                try mutationPolicy.validate(.statementApply, date: operation.date)
            } catch {
                throw CashflowStatementStagingError.closedMonth
            }
        }

        let existing = try modelContext.fetch(FetchDescriptor<CashflowTransaction>())
        var existingByFingerprint: [String: [CashflowTransaction]] = [:]
        for transaction in existing {
            guard transaction.importSourceRaw == Self.importSource,
                  let fingerprint = transaction.importReferenceKey else { continue }
            existingByFingerprint[fingerprint, default: []].append(transaction)
        }

        var inserted: Set<String> = []
        var skipped: Set<String> = []
        for operation in operations {
            let matches = existingByFingerprint[operation.fingerprint, default: []]
            if !matches.isEmpty {
                if case .requireMatchingAccount(let accountID) = duplicatePolicy,
                   matches.contains(where: { $0.cardID != accountID }) {
                    throw CashflowStatementStagingError.attributionConflict(operation.fingerprint)
                }
                skipped.insert(operation.fingerprint)
                continue
            }

            let transaction = CashflowTransaction(
                transactionType: operation.type,
                amount: abs(NSDecimalNumber(decimal: operation.amount).doubleValue),
                currency: operation.currency.uppercased(),
                transactionDate: operation.date,
                cardID: operation.accountID,
                incomeCategoryRaw: operation.type == .income ? operation.categoryRaw : nil,
                expenseCategoryRaw: operation.type == .expense ? operation.categoryRaw : nil,
                note: operation.note,
                importSourceRaw: Self.importSource,
                importReferenceKey: operation.fingerprint,
                affectsCardBalance: false,
                affectsCashflowTotals: true
            )
            transaction.uniqueID = "\(Self.importSource):\(operation.fingerprint)"
            modelContext.insert(transaction)
            inserted.insert(operation.fingerprint)
        }

        return .init(insertedFingerprints: inserted, skippedFingerprints: skipped)
    }

    private static func isValid(_ operation: CashflowApprovedStatementOperation) -> Bool {
        !operation.fingerprint.isEmpty
            && operation.amount != 0
            && operation.currency.trimmingCharacters(in: .whitespacesAndNewlines).count == 3
            && !operation.categoryRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && operation.type != .transfer
    }
}
