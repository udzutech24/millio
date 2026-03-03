import Foundation
import Testing
@testable import millio

struct ProfileLegalLinksTests {
    @Test("Profile legal links use Russian URLs and titles for russian language")
    func testRussianLanguageLinks() {
        let links = ProfileLegalLinks.make(for: .russian, fallbackLocale: Locale(identifier: "en_US"))

        #expect(links.privacyURL.absoluteString == "https://millio.udzutech.com/?lang=ru&page=privacy")
        #expect(links.termsURL.absoluteString == "https://millio.udzutech.com/?lang=ru&page=terms")
        #expect(links.privacyTitle == "Политика конфиденциальности")
        #expect(links.termsTitle == "Пользовательское соглашение")
    }

    @Test("Profile legal links use English URLs and titles for english language")
    func testEnglishLanguageLinks() {
        let links = ProfileLegalLinks.make(for: .english, fallbackLocale: Locale(identifier: "ru_RU"))

        #expect(links.privacyURL.absoluteString == "https://millio.udzutech.com/?lang=en&page=privacy")
        #expect(links.termsURL.absoluteString == "https://millio.udzutech.com/?lang=en&page=terms")
        #expect(links.privacyTitle == "Privacy Policy")
        #expect(links.termsTitle == "Terms of Use")
    }

    @Test("Profile legal links use locale fallback for system language")
    func testSystemLanguageLocaleFallback() {
        let russianSystemLinks = ProfileLegalLinks.make(for: .system, fallbackLocale: Locale(identifier: "ru_RU"))
        let englishSystemLinks = ProfileLegalLinks.make(for: .system, fallbackLocale: Locale(identifier: "en_US"))

        #expect(russianSystemLinks.privacyURL.absoluteString == "https://millio.udzutech.com/?lang=ru&page=privacy")
        #expect(russianSystemLinks.termsURL.absoluteString == "https://millio.udzutech.com/?lang=ru&page=terms")
        #expect(englishSystemLinks.privacyURL.absoluteString == "https://millio.udzutech.com/?lang=en&page=privacy")
        #expect(englishSystemLinks.termsURL.absoluteString == "https://millio.udzutech.com/?lang=en&page=terms")
    }
}
