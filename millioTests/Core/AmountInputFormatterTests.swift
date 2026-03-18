import Testing
@testable import millio

struct AmountInputFormatterTests {
    @Test("sanitize normalizes grouping, decimal separator, and fraction length")
    func sanitizeNormalizesInput() {
        let sanitized = AmountInputFormatter.sanitize(" 00 11 111,2399abc")
        #expect(sanitized == "11111.23")
    }

    @Test("sanitize removes a leading zero during integer typing")
    func sanitizeRemovesLeadingZeroForIntegerTyping() {
        let sanitized = AmountInputFormatter.sanitize("01")
        #expect(sanitized == "1")
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

    @Test("display preserves trailing fractional zeros while typing")
    func displayPreservesTrailingFractionalZeros() {
        let displayed = AmountInputFormatter.display(
            "0.000",
            maxFractionDigits: AmountInputFormatter.marketQuantityFractionDigits
        )
        #expect(displayed == "0.000")
    }

    @Test("display preserves grouped integer part with trailing fractional zeros")
    func displayPreservesGroupedIntegerPartAndFractionalZeros() {
        let displayed = AmountInputFormatter.display("1234.00")
        #expect(displayed == "1 234.00")
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

    @Test("integerInput applies grouping immediately for plain digits")
    func integerInputFormatsPlainDigits() {
        let formatted = AmountInputFormatter.integerInput("33333")
        #expect(formatted == "33 333")
    }

    @Test("integerInput normalizes already-formatted input without drift")
    func integerInputIsStableForFormattedText() {
        let formatted = AmountInputFormatter.integerInput("22 223")
        #expect(formatted == "22 223")
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

    @Test("plainString returns empty for zero amount")
    func plainStringHidesZeroValue() {
        let plain = AmountInputFormatter.plainString(from: 0)
        #expect(plain.isEmpty)
    }

    @Test("plainString preserves custom precision for non-zero amount")
    func plainStringSupportsCustomPrecision() {
        let plain = AmountInputFormatter.plainString(from: 1234.56789123, maxFractionDigits: 8)
        #expect(plain == "1234.56789123")
    }

    @Test("sanitize preserves extended market quantity precision")
    func sanitizeSupportsExtendedMarketQuantityPrecision() {
        let sanitized = AmountInputFormatter.sanitize(
            "0,0000002214567",
            maxFractionDigits: AmountInputFormatter.marketQuantityFractionDigits
        )
        #expect(sanitized == "0.000000221456")
    }

    @Test("parse preserves extended market quantity precision")
    func parseSupportsExtendedMarketQuantityPrecision() {
        let parsed = AmountInputFormatter.parse(
            "0,000000221456",
            maxFractionDigits: AmountInputFormatter.marketQuantityFractionDigits
        )
        #expect(parsed != nil)
        #expect(abs((parsed ?? 0) - 0.000000221456) < 0.0000000000001)
    }
}
