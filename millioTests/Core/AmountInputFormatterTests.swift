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

    @Test("display groups four-digit integer input")
    func displayGroupsFourDigitIntegerInput() {
        let displayed = AmountInputFormatter.display("2222", maxFractionDigits: 0)
        #expect(displayed == "2 222")
    }

    @Test("sanitize removes fraction when integer-only mode is used")
    func sanitizeDropsFractionInIntegerMode() {
        let sanitized = AmountInputFormatter.sanitize("12 345,67", maxFractionDigits: 0)
        #expect(sanitized == "12345")
    }

    @Test("display ignores decimal part in integer-only mode")
    func displayIntegerOnlyMode() {
        let displayed = AmountInputFormatter.display("12 345,67", maxFractionDigits: 0)
        #expect(displayed == "12 345")
    }

    @Test("integer input keeps raw value and shows grouping while typing")
    func integerTypingShowsGrouping() {
        let sanitized = AmountInputFormatter.sanitize("33333", maxFractionDigits: 0)
        let displayed = AmountInputFormatter.display(sanitized, maxFractionDigits: 0)

        #expect(sanitized == "33333")
        #expect(displayed == "33 333")
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
