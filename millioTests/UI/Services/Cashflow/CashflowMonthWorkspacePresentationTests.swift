import Foundation
import Testing
@testable import millio

struct CashflowMonthWorkspacePresentationTests {
    @Test("Workspace presentation has deterministic loading/empty/populated/failure states")
    func contentStates() {
        let loading = CashflowMonthWorkspacePresentationBuilder.build(
            isLoading: true, errorMessage: nil, transactionCount: 0,
            lifecycle: .inProgress, selectedFilter: .expense
        )
        #expect(loading.content == .loading)

        let empty = CashflowMonthWorkspacePresentationBuilder.build(
            isLoading: false, errorMessage: nil, transactionCount: 0,
            lifecycle: .inProgress, selectedFilter: .income
        )
        #expect(empty.content == .empty)
        #expect(empty.primaryDestination == .singleEntry(.income))

        let populated = CashflowMonthWorkspacePresentationBuilder.build(
            isLoading: false, errorMessage: nil, transactionCount: 3,
            lifecycle: .readyToClose, selectedFilter: .transfer
        )
        #expect(populated.content == .populated(transactionCount: 3))

        let failed = CashflowMonthWorkspacePresentationBuilder.build(
            isLoading: false, errorMessage: "offline", transactionCount: 3,
            lifecycle: .inProgress, selectedFilter: .expense
        )
        #expect(failed.content == .failed(message: "offline"))
    }

    @Test("Closed month removes every mutation action")
    func closedPolicy() {
        let value = CashflowMonthWorkspacePresentationBuilder.build(
            isLoading: false, errorMessage: nil, transactionCount: 1,
            lifecycle: .closed(closedAt: Date(timeIntervalSince1970: 1)), selectedFilter: .expense
        )
        #expect(!value.canAdd)
        #expect(!value.canImport)
        #expect(value.primaryDestination == nil)
    }

    @Test("Global FAB always routes directly to scoped entry")
    func fabRouting() {
        #expect(CashflowEntryRoutePolicy.destination(forFABAction: .expense) == .singleEntry(.expense))
        #expect(CashflowEntryRoutePolicy.destination(forFABAction: .income) == .singleEntry(.income))
        #expect(CashflowEntryRoutePolicy.destination(forFABAction: .transfer) == .singleEntry(.transfer))
    }

    @Test("Month selection canonicalizes any day to the first day")
    func monthSelectionIsCanonical() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let input = try #require(calendar.date(from: .init(year: 2026, month: 8, day: 12)))
        let canonical = CashflowMonthSelectionPolicy.canonicalMonth(input, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: canonical) == .init(year: 2026, month: 8, day: 1))
        #expect(CashflowMonthSelectionPolicy.offset(canonical, by: -1, calendar: calendar)
            == calendar.date(from: .init(year: 2026, month: 7, day: 1)))
    }

    @Test("Specific month gives Add and Import the same canonical month")
    func selectedMonthIsPreservedForSiblingActions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let selected = try #require(calendar.date(from: .init(year: 2026, month: 8, day: 23)))
        let expected = try #require(calendar.date(from: .init(year: 2026, month: 8, day: 1)))

        let add = CashflowMonthScopePolicy.resolve(
            chartPeriod: .specificMonth, selectedMonth: selected, calendar: calendar
        )
        let importData = CashflowMonthScopePolicy.resolve(
            chartPeriod: .specificMonth, selectedMonth: selected, calendar: calendar
        )

        #expect(add == .ready(month: expected))
        #expect(importData == add)
    }

    @Test("Custom and multi-period scopes require an explicit month")
    func nonMonthlyPeriodsRejectStaleSelectedMonth() {
        for period in ChartPeriod.allCases where period != .specificMonth {
            #expect(
                CashflowMonthScopePolicy.resolve(chartPeriod: period, selectedMonth: .distantPast)
                    == .requiresExplicitMonth
            )
        }
    }
}
