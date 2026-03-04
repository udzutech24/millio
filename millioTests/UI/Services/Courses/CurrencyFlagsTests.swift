import Testing
@testable import millio

struct CurrencyFlagsTests {

    @Test("assetName резолвит иконку флага для популярных валют")
    func assetNameResolvesPopularCurrencies() {
        #expect(CurrencyFlags.assetName(for: "USD") == "us")
        #expect(CurrencyFlags.assetName(for: "RUB") == "ru")
        #expect(CurrencyFlags.assetName(for: "EUR") == "eu")
        #expect(CurrencyFlags.assetName(for: "KZT") == "kz")
    }

    @Test("assetName не возвращает флаг для криптовалют")
    func assetNameSkipsCrypto() {
        #expect(CurrencyFlags.assetName(for: "BTC") == nil)
    }

    @Test("assetName возвращает nil если иконка флага отсутствует")
    func assetNameReturnsNilForUnknownCurrency() {
        #expect(CurrencyFlags.assetName(for: "ZZZ") == nil)
    }

    @Test("flag для CNY строится корректно даже без ассета")
    func cnyEmojiFallback() {
        #expect(CurrencyFlags.flag(for: "CNY") == "🇨🇳")
    }
}
