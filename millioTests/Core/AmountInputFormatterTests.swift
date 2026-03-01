import Testing
@testable import millio

struct AmountInputFormatterTests {
    @Test("sanitize normalizes grouping, decimal separator, and fraction length")
    func sanitizeNormalizesInput() {
        let sanitized = AmountInputFormatter.sanitize(" 00 11 111,2399abc")
        #expect(sanitized == "11111.23")
    }

    @Test("display formats with space grouping and dot decimal separator")
    func displayFormatsGrouping() {
        let displayed = AmountInputFormatter.display("11111.2")
        #expect(displayed == "11 111.2")
    }

    @Test("display preserves trailing decimal separator while typing")
    func displayPreservesTrailingSeparator() {
        let displayed = AmountInputFormatter.display("1234.")
        #expect(displayed == "1 234.")
    }

    @Test("display groups long integer input immediately")
    func displayGroupsLongIntegerInput() {
        let displayed = AmountInputFormatter.display("2222222")
        #expect(displayed == "2 222 222")
    }

    @Test("parse accepts both comma and dot decimal separators")
    func parseAcceptsCommaAndDot() {
        let parsedComma = AmountInputFormatter.parse("11 111,25")
        let parsedDot = AmountInputFormatter.parse("11 111.25")

        #expect(parsedComma != nil)
        #expect(parsedDot != nil)
        #expect(abs((parsedComma ?? 0) - 11111.25) < 0.000_001)
        #expect(abs((parsedDot ?? 0) - 11111.25) < 0.000_001)
    }
}
