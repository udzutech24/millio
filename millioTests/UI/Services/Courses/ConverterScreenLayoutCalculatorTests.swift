import Testing
import CoreGraphics
@testable import millio

struct ConverterScreenLayoutCalculatorTests {
    @Test("Tall screen lowers keypad closer to bottom safe area")
    func tallScreenLayoutUsesSmallerBottomPadding() {
        let layout = ConverterScreenLayoutCalculator.makeLayout(totalHeight: 932, bottomSafeArea: 34)

        #expect(layout.contentGap == 28)
        #expect(layout.bottomPadding == 22)
        #expect(layout.keyHeight >= 52)
        #expect(layout.keyHeight <= 80)
    }

    @Test("Compact screen keeps minimum stable tap targets")
    func compactScreenLayoutRespectsMinimumHeights() {
        let layout = ConverterScreenLayoutCalculator.makeLayout(totalHeight: 780, bottomSafeArea: 34)

        #expect(layout.contentGap == 24)
        #expect(layout.rowHeight >= 56)
        #expect(layout.keyHeight >= 52)
        #expect(layout.listBlockHeight >= 280)
        #expect(layout.keypadBlockHeight >= 200)
    }
}
