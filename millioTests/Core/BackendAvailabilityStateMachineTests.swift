import Testing
@testable import millio

struct BackendAvailabilityStateMachineTests {
    @Test("T+5 marks an unresolved backend offline without changing scope-bearing state")
    func deadlineMarksOffline() {
        var machine = BackendAvailabilityStateMachine()

        machine.deadlineElapsed()

        #expect(machine.state == .offline(.probeTimedOut))
    }

    @Test("Success at T+5.1 recovers availability without a reset transition")
    func lateSuccessBecomesOnline() {
        var machine = BackendAvailabilityStateMachine()
        machine.deadlineElapsed()
        machine.probeSucceeded()

        #expect(machine.state == .online)
    }

    @Test("Known probe failures are classified without exposing transport errors to UI")
    func failureClassificationStatesAreRepresentable() {
        for failure in [
            BackendAvailabilityFailure.transport,
            .rateLimited,
            .server,
            .unauthorized,
            .cancelled
        ] {
            var machine = BackendAvailabilityStateMachine()
            machine.probeFailed(failure)
            #expect(machine.state == .offline(failure))
        }
    }
}
