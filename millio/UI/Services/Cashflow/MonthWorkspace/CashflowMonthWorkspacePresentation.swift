import Foundation

enum CashflowMonthFilter: String, CaseIterable, Identifiable {
    case expense
    case income
    case transfer

    var id: String { rawValue }

    var transactionType: CashflowTransactionType {
        switch self {
        case .expense: .expense
        case .income: .income
        case .transfer: .transfer
        }
    }
}

enum CashflowMonthLifecyclePresentation: Equatable {
    case inProgress
    case needsReview(reasons: [String])
    case readyToClose
    case closed(closedAt: Date)
}

enum CashflowMonthWorkspaceContentState: Equatable {
    case loading
    case empty
    case populated(transactionCount: Int)
    case failed(message: String)
}

enum CashflowMonthWorkspaceDestination: Hashable {
    case singleEntry(CashflowTransactionType)
    case importHub
    case history
    case budget
    case planned
    case categorySettings
    case monthClosure
}

struct CashflowMonthWorkspacePresentation: Equatable {
    let content: CashflowMonthWorkspaceContentState
    let lifecycle: CashflowMonthLifecyclePresentation
    let canAdd: Bool
    let canImport: Bool
    let primaryDestination: CashflowMonthWorkspaceDestination?
}

enum CashflowMonthWorkspacePresentationBuilder {
    static func build(
        isLoading: Bool,
        errorMessage: String?,
        transactionCount: Int,
        lifecycle: CashflowMonthLifecyclePresentation,
        selectedFilter: CashflowMonthFilter
    ) -> CashflowMonthWorkspacePresentation {
        let content: CashflowMonthWorkspaceContentState
        if isLoading {
            content = .loading
        } else if let errorMessage {
            content = .failed(message: errorMessage)
        } else if transactionCount == 0 {
            content = .empty
        } else {
            content = .populated(transactionCount: transactionCount)
        }

        let isClosed: Bool
        if case .closed = lifecycle { isClosed = true } else { isClosed = false }

        return CashflowMonthWorkspacePresentation(
            content: content,
            lifecycle: lifecycle,
            canAdd: !isClosed,
            canImport: !isClosed,
            primaryDestination: isClosed ? nil : .singleEntry(selectedFilter.transactionType)
        )
    }
}

enum CashflowEntryRoutePolicy {
    /// Global FAB stays a direct single-entry route; the month workspace is never inserted.
    static func destination(forFABAction action: FABAction) -> CashflowMonthWorkspaceDestination {
        switch action {
        case .income: .singleEntry(.income)
        case .expense: .singleEntry(.expense)
        case .transfer: .singleEntry(.transfer)
        }
    }
}
