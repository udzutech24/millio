import Foundation
import Testing
@testable import millio

@Suite("Profile localization")
struct ProfileLocalizationTests {
    private func localizedString(_ key: String, languageCode: String) -> String {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            Issue.record("Missing \(languageCode).lproj in app bundle")
            return key
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    @Test("Profile menu strings are localized for English and Russian locales")
    func testProfileMenuLocalization() {
        #expect(localizedString("profile.launch_splash.title", languageCode: "en") == "Launch splash")
        #expect(localizedString("profile.launch_splash.title", languageCode: "ru") == "Заставка при запуске")

        #expect(localizedString("profile.launch_splash.mode.always", languageCode: "en") == "Always")
        #expect(localizedString("profile.launch_splash.mode.always", languageCode: "ru") == "Всегда")

        #expect(localizedString("profile.launch_splash.mode.once_per_day", languageCode: "en") == "Once per day")
        #expect(localizedString("profile.launch_splash.mode.once_per_day", languageCode: "ru") == "Раз в день")

        #expect(localizedString("profile.launch_splash.mode.off", languageCode: "en") == "Off")
        #expect(localizedString("profile.launch_splash.mode.off", languageCode: "ru") == "Выключено")

        #expect(localizedString("profile.faq.title", languageCode: "en") == "FAQ")
        #expect(localizedString("profile.faq.title", languageCode: "ru") == "Вопросы и ответы")

        #expect(localizedString("profile.faq.basic", languageCode: "en") == "Basic FAQ")
        #expect(localizedString("profile.faq.basic", languageCode: "ru") == "Базовые вопросы")

        #expect(localizedString("profile.faq.subtitle", languageCode: "en") == "This FAQ provides basic answers about how the app works.")
        #expect(localizedString("profile.faq.subtitle", languageCode: "ru") == "Здесь собраны базовые ответы по работе приложения.")

        #expect(localizedString("profile.faq.question_prefix", languageCode: "en") == "Q:")
        #expect(localizedString("profile.faq.question_prefix", languageCode: "ru") == "В:")

        #expect(localizedString("profile.smart_data_reset", languageCode: "en") == "Smart data reset")
        #expect(localizedString("profile.smart_data_reset", languageCode: "ru") == "Умный сброс данных")
    }

    @Test("Profile premium status strings are localized for English and Russian locales")
    func testProfilePremiumLocalization() {
        #expect(localizedString("profile.premium.status.free", languageCode: "en") == "Current mode: Free")
        #expect(localizedString("profile.premium.status.free", languageCode: "ru") == "Текущий режим: Free")

        #expect(localizedString("profile.premium.status.trial", languageCode: "en") == "Current mode: Trial")
        #expect(localizedString("profile.premium.status.trial", languageCode: "ru") == "Текущий режим: Триал")

        #expect(localizedString("profile.premium.status.subscription", languageCode: "en") == "Current mode: Subscription")
        #expect(localizedString("profile.premium.status.subscription", languageCode: "ru") == "Текущий режим: Подписка")

        #expect(localizedString("profile.premium.status.debug", languageCode: "en") == "Current mode: Debug premium")
        #expect(localizedString("profile.premium.status.debug", languageCode: "ru") == "Текущий режим: Debug premium")

        #expect(localizedString("profile.premium.diagnostics.title", languageCode: "en") == "PRO diagnostics")
        #expect(localizedString("profile.premium.diagnostics.title", languageCode: "ru") == "Диагностика PRO")

        #expect(localizedString("profile.premium.diagnostics.summary", languageCode: "en") == "%ld/%ld active")
        #expect(localizedString("profile.premium.diagnostics.summary", languageCode: "ru") == "%ld/%ld активно")

        #expect(localizedString("profile.premium.diagnostics.current_access", languageCode: "en") == "Current access")
        #expect(localizedString("profile.premium.diagnostics.current_access", languageCode: "ru") == "Текущий доступ")

        #expect(localizedString("profile.premium.diagnostics.effective_premium", languageCode: "en") == "Effective premium")
        #expect(localizedString("profile.premium.diagnostics.effective_premium", languageCode: "ru") == "Эффективный premium")

        #expect(localizedString("profile.premium.diagnostics.stored_status", languageCode: "en") == "Stored status")
        #expect(localizedString("profile.premium.diagnostics.stored_status", languageCode: "ru") == "Сохранённый статус")

        #expect(localizedString("profile.premium.diagnostics.trial", languageCode: "en") == "Trial")
        #expect(localizedString("profile.premium.diagnostics.trial", languageCode: "ru") == "Триал")

        #expect(localizedString("profile.premium.diagnostics.trial_disabled", languageCode: "en") == "Trial disabled (override)")
        #expect(localizedString("profile.premium.diagnostics.trial_disabled", languageCode: "ru") == "Триал отключен (override)")

        #expect(localizedString("profile.premium.diagnostics.expiration", languageCode: "en") == "Expiration")
        #expect(localizedString("profile.premium.diagnostics.expiration", languageCode: "ru") == "Истекает")

        #expect(localizedString("profile.premium.diagnostics.behavior", languageCode: "en") == "Where premium changes behavior")
        #expect(localizedString("profile.premium.diagnostics.behavior", languageCode: "ru") == "Где premium меняет поведение")

        #expect(localizedString("profile.premium.diagnostics.status.not_subscribed", languageCode: "en") == "Not subscribed")
        #expect(localizedString("profile.premium.diagnostics.status.not_subscribed", languageCode: "ru") == "Нет подписки")
    }
}
