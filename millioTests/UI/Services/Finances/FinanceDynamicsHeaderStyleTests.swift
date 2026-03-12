import Testing
import CoreGraphics
@testable import millio

struct FinanceDynamicsHeaderStyleTests {
    @Test("Карточка-сводка в деталях продуктов использует единые размеры")
    func summaryCardUsesSharedDimensions() {
        #expect(FinanceDynamicsHeaderStyle.summaryCardCornerRadius == 16)
        #expect(FinanceDynamicsHeaderStyle.summaryCardHeight == 88)
    }

    @Test("Типографика summary-хедера фиксирована для всех продуктов")
    func summaryCardUsesSharedTypography() {
        #expect(FinanceDynamicsHeaderStyle.summaryTitleFontSize == 12)
        #expect(FinanceDynamicsHeaderStyle.summaryAmountFontSize == 24)
    }
}
