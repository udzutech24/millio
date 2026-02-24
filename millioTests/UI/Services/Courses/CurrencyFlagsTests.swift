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

    @Test("assetName использует fallback xx если флаг валюты не найден")
    func assetNameFallsBackToXX() {
        #expect(CurrencyFlags.assetName(for: "ZZZ") == "xx")
    }
}
