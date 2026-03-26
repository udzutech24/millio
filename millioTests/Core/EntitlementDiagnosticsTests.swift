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

        #expect(items.count == 6)
        #expect(ids == [
            "finances.products",
            "finances.charts",
            "cashflow.chart",
            "cashflow.expense_screenshot_import",
            "cashback.categories",
            "cashback.screenshot"
        ])
        #expect(items.first(where: { $0.id == "cashflow.expense_screenshot_import" })?.isPremiumActive == false)
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
