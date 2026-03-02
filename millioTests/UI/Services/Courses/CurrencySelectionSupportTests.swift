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

    @Test("Нормализация поиска игнорирует диакритику и регистр")
    func normalizationIgnoresDiacriticsAndCase() {
        let normalized = CurrencySelectionSupport.normalizedSearchToken("  ÉvRo  ")
        #expect(normalized == "evro")
    }
}
