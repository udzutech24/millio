import CoreGraphics
import Testing
@testable import millio

@Suite
struct AuthWelcomeLayoutPolicyTests {
    @Test("Короткие экраны получают компактный layout без лишней вертикали")
    func compactMetricsForShortScreens() {
        let metrics = AuthWelcomeLayoutPolicy.metrics(containerSize: CGSize(width: 320, height: 568))

        #expect(metrics.horizontalPadding == 16)
        #expect(metrics.sectionSpacing == 16)
        #expect(metrics.cardPaddingTop == 18)
        #expect(metrics.heroTitleScale == 0.78)
        #expect(metrics.primaryButtonHeight == 48)
        #expect(metrics.secondaryButtonHeight == 46)
    }

    @Test("Средние экраны используют промежуточный layout")
    func mediumMetricsForRegularPhones() {
        let metrics = AuthWelcomeLayoutPolicy.metrics(containerSize: CGSize(width: 375, height: 812))

        #expect(metrics.horizontalPadding == 20)
        #expect(metrics.sectionSpacing == 24)
        #expect(metrics.heroTitleScale == 1)
        #expect(metrics.primaryButtonHeight == 52)
    }

    @Test("Узкие экраны с умеренной высотой тоже ужимаются")
    func narrowMediumHeightUsesAdaptiveMetrics() {
        let metrics = AuthWelcomeLayoutPolicy.metrics(containerSize: CGSize(width: 320, height: 740))

        #expect(metrics.horizontalPadding == 16)
        #expect(metrics.cardCornerRadius == 24)
        #expect(metrics.subtitleScale == 0.94)
    }
}
