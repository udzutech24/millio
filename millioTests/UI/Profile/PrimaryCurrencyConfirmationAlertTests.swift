import Foundation
import Testing
@testable import millio

@Suite("Primary currency confirmation alert")
struct PrimaryCurrencyConfirmationAlertTests {
    @Test("Russian copy matches product wording and has no trailing period")
    func russianCopy() {
        let content = PrimaryCurrencyConfirmationContent(
            locale: Locale(identifier: "ru_RU"),
            pendingCode: "USD"
        )

        #expect(content.title == "Изменить основную валюту?")
        #expect(content.confirmTitle == "Изменить на USD")
        #expect(content.cancelTitle == "Отмена")
        #expect(content.badgeTitle == "Новая основная валюта")
        #expect(content.currencyName == "доллар США")
        #expect(content.message.hasSuffix(".") == false)
        #expect(content.message == "Это обновит основную валюту приложения и валюты отображения, которые следуют за основной валютой")
    }

    @Test("English copy formats target currency and has no trailing period")
    func englishCopy() {
        let content = PrimaryCurrencyConfirmationContent(
            locale: Locale(identifier: "en_US"),
            pendingCode: "EUR"
        )

        #expect(content.title == "Change primary currency?")
        #expect(content.confirmTitle == "Change to EUR")
        #expect(content.cancelTitle == "Cancel")
        #expect(content.badgeTitle == "New primary currency")
        #expect(content.currencyName == "Euro")
        #expect(content.message.hasSuffix(".") == false)
        #expect(content.message == "This updates the app primary currency and display currencies that follow the primary currency")
    }
}
