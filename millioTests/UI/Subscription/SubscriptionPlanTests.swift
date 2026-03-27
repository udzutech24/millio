import CoreGraphics
import Testing
@testable import millio

struct SubscriptionPlanTests {
    private func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat, epsilon: CGFloat = 0.0001) -> Bool {
        abs(lhs - rhs) < epsilon
    }

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

    @Test("Экран подписки не раздувает нижний отступ при показе CTA")
    func subscriptionLayoutKeepsCompactBottomPaddingWithCTA() {
        let subscribedPadding = SubscriptionLayoutPolicy.scrollContentBottomPadding(isSubscribed: true)
        let unsubscribedPadding = SubscriptionLayoutPolicy.scrollContentBottomPadding(isSubscribed: false)

        #expect(subscribedPadding == SubscriptionLayoutPolicy.contentBottomPadding)
        #expect(unsubscribedPadding == SubscriptionLayoutPolicy.contentBottomPadding)
        #expect(unsubscribedPadding == subscribedPadding)
    }

    @Test("Нижние константы подписки собраны в одном layout policy")
    func subscriptionLayoutUsesSharedSpacingConstants() {
        #expect(SubscriptionLayoutPolicy.horizontalPadding == 20)
        #expect(SubscriptionLayoutPolicy.topContentPadding == 12)
        #expect(SubscriptionLayoutPolicy.contentBottomPadding == 24)
        #expect(SubscriptionLayoutPolicy.ctaHorizontalPadding == 20)
        #expect(SubscriptionLayoutPolicy.ctaTopPadding == 10)
        #expect(SubscriptionLayoutPolicy.ctaBottomPadding == 8)
    }

    @Test("Hero подписки остается компактным и держит безопасный зазор до плана")
    func subscriptionLayoutMetricsKeepHeroCompact() {
        let compact = SubscriptionLayoutPolicy.metrics(containerSize: CGSize(width: 320, height: 740))
        let regular = SubscriptionLayoutPolicy.metrics(containerSize: CGSize(width: 393, height: 852))
        let large = SubscriptionLayoutPolicy.metrics(containerSize: CGSize(width: 430, height: 932))

        #expect(approximatelyEqual(compact.heroHeight, 136))
        #expect(approximatelyEqual(regular.heroHeight, 146))
        #expect(approximatelyEqual(large.heroHeight, 156))
        #expect(compact.heroHeight < regular.heroHeight)
        #expect(large.heroHeight > regular.heroHeight)
        #expect(compact.topSectionSpacing == 24)
        #expect(regular.topSectionSpacing == 28)
    }
}
