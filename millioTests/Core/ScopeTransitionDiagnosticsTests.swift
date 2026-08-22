import Foundation
import Testing
@testable import millio

@MainActor
struct ScopeTransitionDiagnosticsTests {
    @Test("One expected scope commit and root rebuild is not a loop")
    func normalTransition() {
        let diagnostics = ScopeTransitionDiagnostics()
        diagnostics.requested(generation: 1, targetKind: "authenticated", reason: "auth_resolution")
        diagnostics.didCommit(generation: 1, targetKind: "authenticated")
        diagnostics.didRebuildRoot(generation: 1, targetKind: "authenticated")

        #expect(diagnostics.snapshot() == .init(
            requests: 1,
            coalesced: 0,
            cancelled: 0,
            committed: 1,
            rootRebuilds: 1,
            loopWarnings: 0
        ))
    }

    @Test("Repeated commits in a bounded window are classified as a loop")
    func repeatedTransitionsWarn() {
        let diagnostics = ScopeTransitionDiagnostics(loopThreshold: 2)
        diagnostics.didCommit(generation: 1, targetKind: "authenticated")
        diagnostics.didCommit(generation: 2, targetKind: "guest")
        diagnostics.didCommit(generation: 3, targetKind: "authenticated")

        #expect(diagnostics.snapshot().loopWarnings == 1)
    }
}

