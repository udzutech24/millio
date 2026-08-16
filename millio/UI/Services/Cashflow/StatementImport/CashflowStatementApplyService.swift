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

typealias CashflowStatementApplyError = CashflowStatementStagingError

struct CashflowStatementApplyResult: Equatable {
    let insertedFingerprints: Set<String>
    let skippedFingerprints: Set<String>
}

@MainActor
final class CashflowStatementApplyService {
    static let importSource = CashflowStatementStagingService.importSource
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func apply(_ operations: [CashflowApprovedStatementOperation]) throws -> CashflowStatementApplyResult {
        let result = try CashflowStatementStagingService(modelContext: modelContext).stage(
            operations,
            duplicatePolicy: .skipAnyExisting
        )
        do {
            try modelContext.save()
            return result
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
