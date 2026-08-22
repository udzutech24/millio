import Foundation

@MainActor
final class ScopeTransitionDiagnostics {
    struct Snapshot: Equatable {
        let requests: Int
        let coalesced: Int
        let cancelled: Int
        let committed: Int
        let rootRebuilds: Int
        let loopWarnings: Int
    }

    private let now: () -> Date
    private let loopWindow: TimeInterval
    private let loopThreshold: Int
    private var recentCommitDates: [Date] = []
    private var requests = 0
    private var coalesced = 0
    private var cancelled = 0
    private var committed = 0
    private var rootRebuilds = 0
    private var loopWarnings = 0

    init(
        now: @escaping () -> Date = Date.init,
        loopWindow: TimeInterval = 5,
        loopThreshold: Int = 2
    ) {
        self.now = now
        self.loopWindow = loopWindow
        self.loopThreshold = loopThreshold
    }

    func requested(generation: UInt, targetKind: String, reason: String) {
        requests += 1
        log("requested", generation: generation, targetKind: targetKind, reason: reason)
    }

    func didCoalesce(generation: UInt, targetKind: String) {
        coalesced += 1
        log("coalesced", generation: generation, targetKind: targetKind, reason: "same_scope")
    }

    func didCancel(generation: UInt, targetKind: String) {
        cancelled += 1
        log("cancelled", generation: generation, targetKind: targetKind, reason: "superseded")
    }

    func didCommit(generation: UInt, targetKind: String) {
        committed += 1
        let current = now()
        recentCommitDates.append(current)
        recentCommitDates.removeAll { current.timeIntervalSince($0) > loopWindow }
        log("committed", generation: generation, targetKind: targetKind, reason: "binding_complete")
        if recentCommitDates.count > loopThreshold {
            loopWarnings += 1
            AppLogger.log(
                .warning,
                category: "ScopeTransition",
                "scope_transition state=loop_warning generation=\(generation) kind=\(targetKind) count=\(recentCommitDates.count)"
            )
        }
    }

    func didRebuildRoot(generation: UInt, targetKind: String) {
        rootRebuilds += 1
        log("root_rebuilt", generation: generation, targetKind: targetKind, reason: "scope_commit")
    }

    func snapshot() -> Snapshot {
        Snapshot(
            requests: requests,
            coalesced: coalesced,
            cancelled: cancelled,
            committed: committed,
            rootRebuilds: rootRebuilds,
            loopWarnings: loopWarnings
        )
    }

    private func log(_ state: String, generation: UInt, targetKind: String, reason: String) {
        AppLogger.log(
            .info,
            category: "ScopeTransition",
            "scope_transition state=\(state) generation=\(generation) kind=\(targetKind) reason=\(reason)"
        )
    }
}

