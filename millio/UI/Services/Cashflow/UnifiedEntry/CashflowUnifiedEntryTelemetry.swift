import Foundation
import OSLog

/// Privacy-safe Instruments boundaries for the Unified Entry performance work.
/// Metadata is deliberately limited to enum values and aggregate counts.
enum CashflowUnifiedEntryTelemetry {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.millio.app"
    static let category = "CashflowUnifiedEntry"
    static let tabTransitionName: StaticString = "TabTransition"
    static let monthlySnapshotName: StaticString = "MonthlySnapshotLoad"
    static let tabTransitionSettlingNanoseconds: UInt64 = 250_000_000

    private static let log = OSLog(subsystem: subsystem, category: category)

    static func beginTabTransition(from: CashflowSheetTab, to: CashflowSheetTab) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: tabTransitionName,
            signpostID: id,
            "from=%{public}ld to=%{public}ld",
            from.rawValue,
            to.rawValue
        )
        return id
    }

    static func endTabTransition(_ id: OSSignpostID, selectedTab: CashflowSheetTab) {
        os_signpost(
            .end,
            log: log,
            name: tabTransitionName,
            signpostID: id,
            "selected=%{public}ld",
            selectedTab.rawValue
        )
    }

    static func beginMonthlySnapshot(kind: CashflowCategoryKind) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(
            .begin,
            log: log,
            name: monthlySnapshotName,
            signpostID: id,
            "kind=%{public}ld",
            kind == .income ? 1 : 0
        )
        return id
    }

    static func endMonthlySnapshot(
        _ id: OSSignpostID,
        categoryCount: Int,
        wasCancelled: Bool
    ) {
        os_signpost(
            .end,
            log: log,
            name: monthlySnapshotName,
            signpostID: id,
            "categories=%{public}ld cancelled=%{public}d",
            categoryCount,
            wasCancelled
        )
    }
}
