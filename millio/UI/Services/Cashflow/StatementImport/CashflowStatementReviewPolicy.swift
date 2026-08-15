import Foundation

enum CashflowStatementReviewDisposition: Equatable {
    case included(CashflowCategoryKind)
    case excludedInternalTransfer
    case excludedExternalTransfer
    case excludedDuplicate
    case excludedTechnical
    case excludedByUser

    var isIncluded: Bool {
        if case .included = self { return true }
        return false
    }

    var kind: CashflowCategoryKind? {
        if case .included(let kind) = self { return kind }
        return nil
    }
}

enum CashflowStatementReviewDispositionPolicy {
    static func initial(
        for operation: CashflowStatementPreviewDTO.Operation,
        isLocalDuplicate: Bool
    ) -> CashflowStatementReviewDisposition {
        if isLocalDuplicate || operation.reviewReasons.contains("duplicate") { return .excludedDuplicate }
        if operation.type == "technical" { return .excludedTechnical }
        if operation.type == "transfer_internal" { return .excludedInternalTransfer }
        if operation.type == "transfer_external" { return .excludedExternalTransfer }
        return .included((operation.validatedAmount ?? 0) > 0 ? .income : .expense)
    }

    static func canReclassify(_ operation: CashflowStatementPreviewDTO.Operation) -> Bool {
        operation.type == "transfer_external"
    }
}

enum CashflowStatementReviewFilter: String, CaseIterable, Identifiable {
    case needsAttention
    case categories
    case all
    var id: String { rawValue }
}

struct CashflowStatementReviewRow: Identifiable, Equatable {
    let operation: CashflowStatementPreviewDTO.Operation
    let fingerprintOverride: String?
    let disposition: CashflowStatementReviewDisposition
    let categoryRaw: String
    let needsAttention: Bool
    let currencyOverride: String?

    init(
        operation: CashflowStatementPreviewDTO.Operation,
        fingerprintOverride: String? = nil,
        disposition: CashflowStatementReviewDisposition,
        categoryRaw: String,
        needsAttention: Bool,
        currencyOverride: String? = nil
    ) {
        self.operation = operation
        self.fingerprintOverride = fingerprintOverride
        self.disposition = disposition
        self.categoryRaw = categoryRaw
        self.needsAttention = needsAttention
        self.currencyOverride = currencyOverride
    }

    var id: String { fingerprintOverride ?? operation.fingerprint }
    var currency: String { currencyOverride ?? operation.currency }
    var amount: Decimal { operation.validatedAmount ?? 0 }
}

struct CashflowStatementReviewGroupKey: Hashable {
    let kind: CashflowCategoryKind
    let categoryRaw: String
    let currency: String
}

struct CashflowStatementReviewGroup: Identifiable, Equatable {
    let key: CashflowStatementReviewGroupKey
    let rows: [CashflowStatementReviewRow]
    let amount: Decimal
    var id: CashflowStatementReviewGroupKey { key }
}

enum CashflowStatementReviewPresentationBuilder {
    static func rows(_ rows: [CashflowStatementReviewRow], filter: CashflowStatementReviewFilter) -> [CashflowStatementReviewRow] {
        switch filter {
        case .needsAttention: rows.filter { $0.needsAttention || !$0.disposition.isIncluded }
        case .categories, .all: rows
        }
    }

    static func groups(rows: [CashflowStatementReviewRow]) -> [CashflowStatementReviewGroup] {
        let included = rows.filter(\.disposition.isIncluded)
        let grouped = Dictionary(grouping: included) { row in
            CashflowStatementReviewGroupKey(
                kind: row.disposition.kind ?? .expense,
                categoryRaw: row.categoryRaw,
                currency: row.currency
            )
        }
        return grouped.map { key, values in
            .init(key: key, rows: values, amount: values.reduce(0) { $0 + $1.amount })
        }.sorted { $0.key.categoryRaw < $1.key.categoryRaw }
    }
}

struct CashflowStatementConfirmationSummary: Equatable {
    let includedCount: Int
    let excludedCount: Int
    let reclassifiedCount: Int
    let totalsByCurrency: [String: Decimal]

    init(rows: [CashflowStatementReviewRow]) {
        includedCount = rows.count(where: { $0.disposition.isIncluded })
        excludedCount = rows.count - includedCount
        reclassifiedCount = rows.count(where: {
            $0.operation.type == "transfer_external" && $0.disposition.isIncluded
        })
        totalsByCurrency = rows.filter(\.disposition.isIncluded).reduce(into: [:]) { result, row in
            result[row.currency, default: 0] += row.amount
        }
    }
}

enum CashflowStatementAccountSelectionPolicy {
    static func options(
        cards: [Card],
        newCoreAccounts: [Account],
        statementCurrencies: Set<String>
    ) -> [CashflowSelectableAccount] {
        let normalizedCurrencies = Set(statementCurrencies.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        })
        return CashflowSelectableAccountResolver.options(
            cards: cards,
            investments: [],
            linkedInvestmentIDs: [],
            transactionType: .expense,
            currency: "",
            newCoreAccounts: newCoreAccounts
        ).filter { option in
            normalizedCurrencies.isEmpty || normalizedCurrencies.contains(option.currency.uppercased())
        }
    }

    static func isValid(_ accountID: String, in options: [CashflowSelectableAccount]) -> Bool {
        options.contains { $0.cardID == accountID }
    }
}
