import Testing
@testable import millio

struct CurrencySelectionSupportTests {

    @Test("Поиск находит валюту по русскому имени")
    func matchesRussianName() {
        #expect(CurrencySelectionSupport.matchesSearchQuery(code: "USD", query: "доллар"))
    }

    @Test("Поиск находит валюту по английскому имени")
    func matchesEnglishName() {
        #expect(CurrencySelectionSupport.matchesSearchQuery(code: "USD", query: "dollar"))
    }

    @Test("Поиск находит валюту по алиасу")
    func matchesAlias() {
        #expect(CurrencySelectionSupport.matchesSearchQuery(code: "USD", query: "бакс"))
    }

    @Test("Поиск находит валюту по стране на русском")
    func matchesRussianCountryName() {
        #expect(CurrencySelectionSupport.matchesSearchQuery(code: "RUB", query: "россия"))
    }

    @Test("Поиск находит валюту по стране на английском")
    func matchesEnglishCountryName() {
        #expect(CurrencySelectionSupport.matchesSearchQuery(code: "TRY", query: "turkey"))
    }

    @Test("Поиск находит валюту по английскому полному названию")
    func matchesEnglishFullCurrencyName() {
        #expect(CurrencySelectionSupport.matchesSearchQuery(code: "TRY", query: "turkish lira"))
    }

    @Test("Поиск находит валюту по английскому полному названию для рубля")
    func matchesEnglishFullCurrencyNameForRuble() {
        #expect(CurrencySelectionSupport.matchesSearchQuery(code: "RUB", query: "russian ruble"))
    }

    @Test("Нормализация поиска игнорирует диакритику и регистр")
    func normalizationIgnoresDiacriticsAndCase() {
        let normalized = CurrencySelectionSupport.normalizedSearchToken("  ÉvRo  ")
        #expect(normalized == "evro")
    }
}
