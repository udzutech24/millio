import Foundation

enum CashflowNavigationSurface: Hashable {
    case dashboard
    case monthOperations
    case periodControl
    case chart
    case budgetCard
    case operationsContent
    case contextualActions
    case overflow
    case currencySettings
    case operationEditor
    case importHub
    case history
    case budgetEditor
    case expandedChart
}

enum CashflowDestination: CaseIterable, Hashable {
    case period
    case expandedChart
    case expenseBudget
    case incomeBudget
    case operations
    case addOperation
    case importData
    case currency
}

/// Single source of truth for Cashflow route ownership. UI surfaces may render a
/// destination only when this policy assigns it to that surface.
enum CashflowNavigationPolicy {
    static let ownerByDestination: [CashflowDestination: CashflowNavigationSurface] = [
        .period: .periodControl,
        .expandedChart: .chart,
        .expenseBudget: .budgetCard,
        .incomeBudget: .budgetCard,
        .operations: .operationsContent,
        .addOperation: .contextualActions,
        .importData: .contextualActions,
        .currency: .overflow
    ]

    static let routeGraph: [CashflowNavigationSurface: Set<CashflowNavigationSurface>] = [
        .dashboard: [.monthOperations, .periodControl, .chart, .budgetCard, .operationsContent, .contextualActions, .overflow],
        .monthOperations: [.operationEditor, .importHub],
        .periodControl: [],
        .chart: [.expandedChart],
        .budgetCard: [.budgetEditor],
        .operationsContent: [.monthOperations, .history],
        .contextualActions: [.operationEditor, .importHub],
        .overflow: [.currencySettings],
        .currencySettings: [],
        .operationEditor: [],
        .importHub: [],
        .history: [],
        .budgetEditor: [],
        .expandedChart: []
    ]

    static func isAcyclic() -> Bool {
        var visiting = Set<CashflowNavigationSurface>()
        var visited = Set<CashflowNavigationSurface>()

        func visit(_ node: CashflowNavigationSurface) -> Bool {
            if visiting.contains(node) { return false }
            if visited.contains(node) { return true }
            visiting.insert(node)
            for destination in routeGraph[node, default: []] where !visit(destination) {
                return false
            }
            visiting.remove(node)
            visited.insert(node)
            return true
        }

        return routeGraph.keys.allSatisfy(visit)
    }
}

enum CashflowMonthScopedAction: Equatable {
    case addOperation
    case importData
    case operations
}

enum CashflowMonthScopeResolution: Equatable {
    case ready(month: Date)
    case requiresExplicitMonth
}

enum CashflowMonthScopePolicy {
    static func resolve(
        chartPeriod: ChartPeriod,
        selectedMonth: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> CashflowMonthScopeResolution {
        guard chartPeriod == .specificMonth else { return .requiresExplicitMonth }
        return .ready(month: CashflowMonthSelectionPolicy.canonicalMonth(selectedMonth, calendar: calendar))
    }
}
