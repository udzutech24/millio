import Foundation
import SwiftData

struct CashflowApprovedStatementOperation {
    let fingerprint: String
    let date: Date
    let amount: Decimal
    let currency: String
    let type: CashflowTransactionType
    let categoryRaw: String
    /// Optional attribution only. Statement imports never mutate the account balance.
    let accountID: String?
    let note: String?
}

enum CashflowStatementApplyError: Error, Equatable { case invalidOperation, duplicateFingerprint, closedMonth }

struct CashflowStatementApplyResult: Equatable {
    let insertedFingerprints: Set<String>
    let skippedFingerprints: Set<String>
}

@MainActor
final class CashflowStatementApplyService {
    static let importSource = "bank_statement_v1"
    private let modelContext: ModelContext
    private let mutationPolicy: CashflowMonthMutationPolicy

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.mutationPolicy = CashflowMonthMutationPolicy(modelContext: modelContext)
    }

    @discardableResult
    func apply(_ operations: [CashflowApprovedStatementOperation]) throws -> CashflowStatementApplyResult {
        let fingerprints = operations.map(\.fingerprint)
        guard Set(fingerprints).count == fingerprints.count else { throw CashflowStatementApplyError.duplicateFingerprint }
        guard operations.allSatisfy({ !$0.fingerprint.isEmpty && $0.amount != 0 && !$0.currency.isEmpty && $0.type != .transfer }) else {
            throw CashflowStatementApplyError.invalidOperation
        }
        for operation in operations {
            do { try mutationPolicy.validate(.statementApply, date: operation.date) }
            catch { throw CashflowStatementApplyError.closedMonth }
        }

        let existing = (try? modelContext.fetch(FetchDescriptor<CashflowTransaction>())) ?? []
        let existingFingerprints = Set(existing.compactMap { transaction in
            transaction.importSourceRaw == Self.importSource ? transaction.importReferenceKey : nil
        })
        let newOperations = operations.filter { !existingFingerprints.contains($0.fingerprint) }

        for operation in newOperations {
            let amount = NSDecimalNumber(decimal: operation.amount).doubleValue
            let transaction = CashflowTransaction(
                transactionType: operation.type,
                amount: abs(amount),
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
            modelContext.insert(transaction)
        }
        do {
            try modelContext.save()
            let inserted = Set(newOperations.map(\.fingerprint))
            return CashflowStatementApplyResult(
                insertedFingerprints: inserted,
                skippedFingerprints: Set(fingerprints).subtracting(inserted)
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
