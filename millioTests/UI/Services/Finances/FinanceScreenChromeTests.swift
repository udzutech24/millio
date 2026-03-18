import CoreGraphics
import Testing
@testable import millio

struct FinanceScreenChromeTests {
    @Test("Главный экран финансов использует тот же chrome-радиус, что и обновленная стилистика динамики")
    func chromeMetricsStayAligned() {
        #expect(FinanceScreenChrome.heroCornerRadius == 24)
        #expect(FinanceScreenChrome.sectionCornerRadius == 20)
        #expect(FinanceScreenChrome.groupRowCornerRadius == 20)
        #expect(FinanceScreenChrome.controlCornerRadius == 12)
    }

    @Test("Контролы и FAB используют согласованные размеры")
    func chromeControlMetricsStayStable() {
        #expect(FinanceScreenChrome.headerControlSide == 36)
        #expect(FinanceScreenChrome.fabDiameter == 56)
        #expect(FinanceScreenChrome.fabIconSize == 20)
    }
}
