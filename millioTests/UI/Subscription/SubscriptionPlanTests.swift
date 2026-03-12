import Testing
@testable import millio

struct SubscriptionPlanTests {
    @Test("Годовой план маппится в yearly product id")
    func yearlyPlanMapsToYearlyProductID() {
        let monthly = "com.app.monthly"
        let yearly = "com.app.yearly"

        #expect(SubscriptionPlan.yearly.productID(monthlyID: monthly, yearlyID: yearly) == yearly)
    }

    @Test("Месячный план маппится в monthly product id")
    func monthlyPlanMapsToMonthlyProductID() {
        let monthly = "com.app.monthly"
        let yearly = "com.app.yearly"

        #expect(SubscriptionPlan.monthly.productID(monthlyID: monthly, yearlyID: yearly) == monthly)
    }

    @Test("Fallback цены для планов заданы для offline состояния")
    func plansHaveFallbackPrices() {
        #expect(!SubscriptionPlan.yearly.fallbackTotalPrice.isEmpty)
        #expect(!SubscriptionPlan.monthly.fallbackTotalPrice.isEmpty)
    }
}
