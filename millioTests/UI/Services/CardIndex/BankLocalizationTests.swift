import Foundation
import Testing
@testable import millio

struct BankLocalizationTests {
    @Test("Bank.displayName локализуется для EN/RU")
    func bankDisplayNameIsLocalizedForEnglishAndRussian() {
        #expect(AppLocalization.string("finances.bank.other", locale: Locale(identifier: "en")) == "Other")
        #expect(AppLocalization.string("finances.bank.other", locale: Locale(identifier: "ru")) == "Другой")

        #expect(Bank.other.displayName != "finances.bank.other")
    }
}

