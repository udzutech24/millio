import Foundation

enum CashflowStatementExclusionReason: Equatable {
    case duplicate
    case transfer
    case technical

    static func resolve(_ operation: CashflowStatementPreviewDTO.Operation) -> Self? {
        if operation.reviewReasons.contains("duplicate") { return .duplicate }
        if operation.type.hasPrefix("transfer_") { return .transfer }
        if operation.type == "technical" { return .technical }
        return nil
    }

    var title: String {
        switch self {
        case .duplicate: CashflowMonthWorkspaceLocalization.excludedDuplicate
        case .transfer: CashflowMonthWorkspaceLocalization.excludedTransfer
        case .technical: CashflowMonthWorkspaceLocalization.excludedTechnical
        }
    }
}

struct CashflowStatementReviewSummary: Equatable {
    let total: Int
    let included: Int
    let excluded: Int
    let duplicates: Int
    let transfers: Int
    let technical: Int

    init(preview: CashflowStatementPreviewDTO, includedFingerprints: Set<String>) {
        total = preview.operations.count
        included = preview.operations.count { includedFingerprints.contains($0.fingerprint) }
        excluded = total - included
        duplicates = preview.operations.count { CashflowStatementExclusionReason.resolve($0) == .duplicate }
        transfers = preview.operations.count { CashflowStatementExclusionReason.resolve($0) == .transfer }
        technical = preview.operations.count { CashflowStatementExclusionReason.resolve($0) == .technical }
    }
}

struct CashflowStatementCategoryBreakdownItem: Identifiable, Equatable {
    let categoryRaw: String
    let title: String
    let icon: String
    let transactionCount: Int
    let amount: Decimal
    let currency: String

    var id: String { categoryRaw }
}

enum CashflowStatementCategoryBreakdown {
    static func make(
        preview: CashflowStatementPreviewDTO,
        includedFingerprints: Set<String>,
        categoryByFingerprint: [String: String],
        categoryOptionsByRawValue: [String: CashflowCategoryOption]
    ) -> [CashflowStatementCategoryBreakdownItem] {
        struct Aggregate { var count = 0; var amount: Decimal = 0; var currency = "" }
        var grouped: [String: Aggregate] = [:]

        for operation in preview.operations where includedFingerprints.contains(operation.fingerprint) {
            guard let amount = operation.validatedAmount else { continue }
            let categoryRaw = categoryByFingerprint[operation.fingerprint] ?? "other"
            var aggregate = grouped[categoryRaw, default: Aggregate()]
            aggregate.count += 1
            aggregate.amount += amount
            aggregate.currency = operation.currency
            grouped[categoryRaw] = aggregate
        }

        return grouped.map { categoryRaw, aggregate in
            let option = categoryOptionsByRawValue[categoryRaw]
            return CashflowStatementCategoryBreakdownItem(
                categoryRaw: categoryRaw,
                title: option?.displayName ?? categoryRaw,
                icon: option?.icon ?? "tag",
                transactionCount: aggregate.count,
                amount: aggregate.amount,
                currency: aggregate.currency
            )
        }
        .sorted { lhs, rhs in
            if abs(lhs.amount) != abs(rhs.amount) { return abs(lhs.amount) > abs(rhs.amount) }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}
