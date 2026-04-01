import Foundation
import Testing
@testable import millio

struct ProfileLegalLinksTests {
    @Test("Profile legal links use Russian URLs and titles for russian language")
    func testRussianLanguageLinks() {
        let links = ProfileLegalLinks.make(for: .russian, fallbackLocale: Locale(identifier: "en_US"))

        #expect(links.privacyURL.absoluteString == "https://millio.udzutech.com/?lang=ru&page=privacy")
        #expect(links.termsURL.absoluteString == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        #expect(links.privacyTitle == "Политика конфиденциальности")
        #expect(links.termsTitle == "Условия использования (EULA)")
    }

    @Test("Profile legal links use English URLs and titles for english language")
    func testEnglishLanguageLinks() {
        let links = ProfileLegalLinks.make(for: .english, fallbackLocale: Locale(identifier: "ru_RU"))

        #expect(links.privacyURL.absoluteString == "https://millio.udzutech.com/?lang=en&page=privacy")
        #expect(links.termsURL.absoluteString == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        #expect(links.privacyTitle == "Privacy Policy")
        #expect(links.termsTitle == "Terms of Use (EULA)")
    }

    @Test("Profile legal links use Simplified Chinese titles for chinese language")
    func testSimplifiedChineseLanguageLinks() {
        let links = ProfileLegalLinks.make(for: .simplifiedChinese, fallbackLocale: Locale(identifier: "en_US"))

        #expect(links.privacyURL.absoluteString == "https://millio.udzutech.com/?lang=en&page=privacy")
        #expect(links.termsURL.absoluteString == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        #expect(links.privacyTitle == "隐私政策")
        #expect(links.termsTitle == "使用条款（EULA）")
    }

    @Test("Profile legal links use locale fallback for system language")
    func testSystemLanguageLocaleFallback() {
        let russianSystemLinks = ProfileLegalLinks.make(for: .system, fallbackLocale: Locale(identifier: "ru_RU"))
        let englishSystemLinks = ProfileLegalLinks.make(for: .system, fallbackLocale: Locale(identifier: "en_US"))
        let chineseSystemLinks = ProfileLegalLinks.make(for: .system, fallbackLocale: Locale(identifier: "zh_Hans_CN"))

        #expect(russianSystemLinks.privacyURL.absoluteString == "https://millio.udzutech.com/?lang=ru&page=privacy")
        #expect(russianSystemLinks.termsURL.absoluteString == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        #expect(englishSystemLinks.privacyURL.absoluteString == "https://millio.udzutech.com/?lang=en&page=privacy")
        #expect(englishSystemLinks.termsURL.absoluteString == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
        #expect(chineseSystemLinks.privacyURL.absoluteString == "https://millio.udzutech.com/?lang=en&page=privacy")
        #expect(chineseSystemLinks.privacyTitle == "隐私政策")
        #expect(chineseSystemLinks.termsTitle == "使用条款（EULA）")
    }
}
