import Testing
@testable import millio

@Suite("Profile premium display mode")
struct ProfilePremiumDisplayModeTests {
    @Test("Free access keeps promotional premium card")
    func promotionalModeForFreeAccess() {
        #expect(ProfilePremiumDisplayMode.resolve(for: .free) == .promotional)
    }

    @Test("Trial access keeps compact row with trial status")
    func compactTrialMode() {
        #expect(ProfilePremiumDisplayMode.resolve(for: .trial) == .compact(.trial))
    }

    @Test("Paid and debug premium collapse to compact settings row with enabled state")
    func compactModeForActivePremiumAccess() {
        #expect(ProfilePremiumDisplayMode.resolve(for: .subscription) == .compact(.enabled))
        #expect(ProfilePremiumDisplayMode.resolve(for: .debug) == .compact(.enabled))
    }
}
