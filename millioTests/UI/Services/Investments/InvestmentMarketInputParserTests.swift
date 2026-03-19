import Testing
@testable import millio

struct InvestmentMarketInputParserTests {
    @Test("empty market quantity is treated as zero")
    func emptyQuantityDefaultsToZero() {
        #expect(InvestmentMarketInputParser.quantity(from: "") == 0)
        #expect(InvestmentMarketInputParser.quantity(from: "   ") == 0)
    }

    @Test("market quantity preserves parsed numeric value")
    func quantityParsesDecimalInput() {
        let quantity = InvestmentMarketInputParser.quantity(from: "0,25")
        #expect(quantity != nil)
        #expect(abs((quantity ?? 0) - 0.25) < 0.000_001)
    }

    @Test("invalid market quantity stays invalid")
    func invalidQuantityReturnsNil() {
        #expect(InvestmentMarketInputParser.quantity(from: "abc") == nil)
    }
}
