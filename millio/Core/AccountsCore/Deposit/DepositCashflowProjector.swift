import Foundation
import SwiftData

enum DepositCashflowProjectionDiagnostic: Equatable {
    case missingSourceID(eventID: UUID)
    case duplicateSourceEvent(sourceID: String)
    case duplicateCashflowRow(sourceID: String)
}

struct DepositCashflowProjectionReport: Equatable {
    var insertedCount = 0
    var diagnostics: [DepositCashflowProjectionDiagnostic] = []
}

/// Purely policy-driven projection from confirmed deposit interest into Cashflow.
/// Scheduler estimates are never eligible, regardless of whether their date has passed.
@MainActor
enum DepositCashflowProjector {
    static let importSource = "accountsCoreDepositInterest"

    static func project(
        events: [AccountEvent],
        through date: Date,
        context: ModelContext
    ) throws -> DepositCashflowProjectionReport {
        let eligible = events.filter {
            $0.type == .interest
                && $0.date <= date
                && $0.account?.kind == .deposit
                && !isGenerated($0)
        }
        let grouped = Dictionary(grouping: eligible) { $0.sourceTransactionID ?? "" }
        let existing = try context.fetch(FetchDescriptor<CashflowTransaction>())
            .filter { $0.importSourceRaw == importSource }
        let existingGroups = Dictionary(grouping: existing) { $0.importReferenceKey ?? "" }
        var report = DepositCashflowProjectionReport()

        for (sourceID, sourceEvents) in grouped.sorted(by: { $0.key < $1.key }) {
            guard !sourceID.isEmpty else {
                report.diagnostics.append(contentsOf: sourceEvents.map { .missingSourceID(eventID: $0.id) })
                continue
            }
            guard sourceEvents.count == 1 else {
                report.diagnostics.append(.duplicateSourceEvent(sourceID: sourceID))
                continue
            }
            let rows = existingGroups[sourceID] ?? []
            guard rows.count <= 1 else {
                report.diagnostics.append(.duplicateCashflowRow(sourceID: sourceID))
                continue
            }
            guard rows.isEmpty else { continue }
            let event = sourceEvents[0]
            guard let account = event.account, let amount = event.amount, amount > 0 else { continue }
            try CashflowMonthMutationPolicy(modelContext: context).validate(.scheduledApply, date: event.date)
            context.insert(CashflowTransaction(
                transactionType: .income,
                amount: NSDecimalNumber(decimal: amount).doubleValue,
                currency: account.currency,
                transactionDate: event.date,
                incomeCategory: .interest,
                note: account.name.isEmpty ? nil : account.name,
                importSourceRaw: importSource,
                importReferenceKey: sourceID,
                affectsCardBalance: false
            ))
            report.insertedCount += 1
        }
        return report
    }

    private static func isGenerated(_ event: AccountEvent) -> Bool {
        guard let accountID = event.account?.id else { return false }
        return DepositConfirmedBalanceResolver.isGeneratedInterest(event, accountID: accountID)
    }
}
