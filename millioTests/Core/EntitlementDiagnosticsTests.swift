import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct EntitlementDiagnosticsTests {
    @Test("Диагностика monetization points показывает все основные premium-гейты")
    func testDiagnosticsContainExpectedEntries() {
        let appState = AppState()
        appState.applySubscriptionSnapshot(
            SubscriptionSnapshot(
                status: .notSubscribed,
                expirationDate: nil,
                isTrialActive: false,
                hasDebugPremiumOverride: false,
                hasTrialDisabledOverride: false
            )
        )

        let items = EntitlementDiagnostics.items(for: appState)

        #expect(items.count == 6)
        #expect(items.map(\.id).contains("converter.crypto"))
        #expect(items.map(\.id).contains("finances.trackedTickers"))
        #expect(items.map(\.id).contains("cashback.screenshot"))
        #expect(items.first(where: { $0.id == "converter.crypto" })?.isPremiumActive == false)
    }

    @Test("Диагностика учитывает premium override")
    func testDiagnosticsReflectPremiumAccess() {
        let appState = AppState()
        appState.applySubscriptionSnapshot(
            SubscriptionSnapshot(
                status: .notSubscribed,
                expirationDate: nil,
                isTrialActive: false,
                hasDebugPremiumOverride: true,
                hasTrialDisabledOverride: false
            )
        )

        let items = EntitlementDiagnostics.items(for: appState)

        #expect(items.allSatisfy { $0.isPremiumActive })
    }
}
