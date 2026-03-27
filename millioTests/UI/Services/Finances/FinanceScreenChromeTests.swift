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

    @Test("Refresh action sheet использует отдельную финансовую палитру и стабильный радиус")
    func refreshSheetChromeStaysStable() {
        #expect(FinanceScreenChrome.actionSheetCornerRadius == 24)
    }

    @Test("Refresh overlay actions остаются предсказуемыми для UI")
    func refreshOverlayActionsStayMapped() {
        #expect(FinanceRefreshAction.allCases.count == 2)
        #expect(FinanceRefreshAction.quotes.titleKey == "finances.main.refresh_quotes")
        #expect(FinanceRefreshAction.quotes.iconName == "dollarsign.arrow.circlepath")
        #expect(FinanceRefreshAction.stocks.titleKey == "finances.main.refresh_stocks")
        #expect(FinanceRefreshAction.stocks.iconName == "chart.line.uptrend.xyaxis.circle")
    }
}
