import Foundation
import Testing
@testable import millio

@Suite("Debug menu access policy")
struct DebugMenuAccessPolicyTests {
    @Test("Validates the correct password")
    func testPasswordValidation() {
        #expect(DebugMenuAccessPolicy.validate(password: "mil26") == true)
        #expect(DebugMenuAccessPolicy.validate(password: " mil26 ") == true)
        #expect(DebugMenuAccessPolicy.validate(password: "") == false)
        #expect(DebugMenuAccessPolicy.validate(password: "mil25") == false)
        #expect(DebugMenuAccessPolicy.validate(password: "MIL26") == false)
    }

    @Test("MultiTapGate triggers on target count within window")
    func testMultiTapGateTriggers() {
        var gate = MultiTapGate(
            targetCount: DebugMenuAccessPolicy.unlockTapCount,
            resetInterval: DebugMenuAccessPolicy.unlockTapResetInterval
        )

        let start = Date(timeIntervalSince1970: 1_000)
        for i in 0..<(DebugMenuAccessPolicy.unlockTapCount - 1) {
            let triggered = gate.registerTap(at: start.addingTimeInterval(TimeInterval(i) * 0.5))
            #expect(triggered == false)
        }

        let didTrigger = gate.registerTap(at: start.addingTimeInterval(1.6))
        #expect(didTrigger == true)
        #expect(gate.tapCount == 0)
    }

    @Test("MultiTapGate resets when taps are too far apart")
    func testMultiTapGateResetsByTime() {
        var gate = MultiTapGate(targetCount: 4, resetInterval: 1.0)

        let start = Date(timeIntervalSince1970: 2_000)
        #expect(gate.registerTap(at: start) == false)
        #expect(gate.tapCount == 1)

        // Exceed reset interval -> count resets before incrementing.
        #expect(gate.registerTap(at: start.addingTimeInterval(1.01)) == false)
        #expect(gate.tapCount == 1)
    }

    @Test("AppState loads debug menu unlock from SettingsManager on init")
    @MainActor
    func testAppStateLoadsDebugMenuUnlockFlag() {
        let key = "debugMenuUnlocked"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        SettingsManager.shared.isDebugMenuUnlocked = true
        let appState = AppState()
        #expect(appState.isDebugMenuUnlocked == true)
    }
}
