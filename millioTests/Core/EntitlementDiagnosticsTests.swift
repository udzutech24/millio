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
        let ids = items.map(\.id)

        #expect(items.count == 9)
        #expect(ids == [
            "converter.crypto",
            "finances.market_assets",
            "finances.tracked_tickers",
            "finances.products",
            "finances.charts",
            "cashflow.chart",
            "cashback.cards",
            "cashback.categories",
            "cashback.screenshot"
        ])
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
