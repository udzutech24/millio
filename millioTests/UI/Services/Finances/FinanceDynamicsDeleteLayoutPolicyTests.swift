import Testing
@testable import millio

struct FinanceDynamicsDeleteLayoutPolicyTests {
    @Test("Удаление счета внизу показывается для обычного single-account экрана")
    func showsRegularDeleteFooterWhenNoMarketInvestment() {
        #expect(
            FinanceDynamicsDeleteLayoutPolicy.showsDeleteFooter(
                isSingleAccountMode: true,
                hasInitialAccount: true,
                hasMarketInvestment: false
            ) == true
        )
    }

    @Test("Удаление инструмента внизу показывается для single-account экрана акции или крипты")
    func showsMarketDeleteFooterWhenMarketInvestmentExists() {
        #expect(
            FinanceDynamicsDeleteLayoutPolicy.showsMarketDeleteFooter(
                isSingleAccountMode: true,
                hasInitialAccount: true,
                hasMarketInvestment: true
            ) == true
        )
    }

    @Test("Обычный и market-footers взаимоисключающие")
    func deleteFootersDoNotOverlap() {
        #expect(
            FinanceDynamicsDeleteLayoutPolicy.showsDeleteFooter(
                isSingleAccountMode: true,
                hasInitialAccount: true,
                hasMarketInvestment: true
            ) == false
        )
        #expect(
            FinanceDynamicsDeleteLayoutPolicy.showsMarketDeleteFooter(
                isSingleAccountMode: true,
                hasInitialAccount: true,
                hasMarketInvestment: false
            ) == false
        )
    }
}
