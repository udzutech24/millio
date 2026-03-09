import Testing
@testable import millio

struct CurrencySelectionSupportCryptoTests {
    @Test("CurrencySelectionSupport.allCodes(includeCrypto:) includes crypto only when requested")
    func testAllCodesIncludeCryptoToggle() {
        let fiatOnly = CurrencySelectionSupport.allCodes(includeCrypto: false)
        #expect(!fiatOnly.contains("BTC"))
        #expect(!fiatOnly.contains("ETH"))

        let withCrypto = CurrencySelectionSupport.allCodes(includeCrypto: true)
        #expect(withCrypto.contains("BTC"))
        #expect(withCrypto.contains("ETH"))
    }

    @Test("CurrencySelectionSupport.isCrypto matches common codes")
    func testIsCrypto() {
        #expect(CurrencySelectionSupport.isCrypto("BTC"))
        #expect(CurrencySelectionSupport.isCrypto("eth"))
        #expect(!CurrencySelectionSupport.isCrypto("USD"))
    }
}

