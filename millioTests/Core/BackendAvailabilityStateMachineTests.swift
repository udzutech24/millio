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

    @Test("Automatic availability retries use bounded backoff")
    func retryPolicyCapsDelayForPersistentFailure() {
        #expect(BackendAvailabilityRetryPolicy.delay(for: 1) == .seconds(5))
        #expect(BackendAvailabilityRetryPolicy.delay(for: 2) == .seconds(15))
        #expect(BackendAvailabilityRetryPolicy.delay(for: 3) == .seconds(30))
        #expect(BackendAvailabilityRetryPolicy.delay(for: 4) == .seconds(60))
        #expect(BackendAvailabilityRetryPolicy.delay(for: 99) == .seconds(60))
    }
}
