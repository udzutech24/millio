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
        #expect(localizedString("profile.launch_splash.title", languageCode: "en") == "Launch screen")
        #expect(localizedString("profile.launch_splash.title", languageCode: "ru") == "Заставка при запуске")

        #expect(localizedString("profile.launch_splash.mode.always", languageCode: "en") == "Always")
        #expect(localizedString("profile.launch_splash.mode.always", languageCode: "ru") == "Всегда")

        #expect(localizedString("profile.launch_splash.mode.once_per_day", languageCode: "en") == "Once per day")
        #expect(localizedString("profile.launch_splash.mode.once_per_day", languageCode: "ru") == "Раз в день")

        #expect(localizedString("profile.launch_splash.mode.off", languageCode: "en") == "Off")
        #expect(localizedString("profile.launch_splash.mode.off", languageCode: "ru") == "Выключено")

        #expect(localizedString("profile.faq.title", languageCode: "en") == "FAQ")
        #expect(localizedString("profile.faq.title", languageCode: "ru") == "Вопросы и ответы")

        #expect(localizedString("profile.faq.basic", languageCode: "en") == "FAQ for getting started")
        #expect(localizedString("profile.faq.basic", languageCode: "ru") == "Базовые вопросы")

        #expect(localizedString("profile.faq.subtitle", languageCode: "en") == "Quick answers about how Millio works.")
        #expect(localizedString("profile.faq.subtitle", languageCode: "ru") == "Здесь собраны базовые ответы по работе приложения.")

        #expect(localizedString("profile.faq.question_prefix", languageCode: "en") == "Q:")
        #expect(localizedString("profile.faq.question_prefix", languageCode: "ru") == "В:")

        #expect(localizedString("profile.smart_data_reset", languageCode: "en") == "Guided data reset")
        #expect(localizedString("profile.smart_data_reset", languageCode: "ru") == "Умный сброс")
    }

    @Test("Profile premium status strings are localized for English and Russian locales")
    func testProfilePremiumLocalization() {
        #expect(localizedString("profile.premium.status.free", languageCode: "en") == "Plan: Free")
        #expect(localizedString("profile.premium.status.free", languageCode: "ru") == "Текущий режим: Free")

        #expect(localizedString("profile.premium.status.trial", languageCode: "en") == "Plan: Trial")
        #expect(localizedString("profile.premium.status.trial", languageCode: "ru") == "Текущий режим: Триал")

        #expect(localizedString("profile.premium.status.subscription", languageCode: "en") == "Plan: Subscription")
        #expect(localizedString("profile.premium.status.subscription", languageCode: "ru") == "Текущий режим: Подписка")

        #expect(localizedString("profile.premium.status.debug", languageCode: "en") == "Plan: Debug Premium")
        #expect(localizedString("profile.premium.status.debug", languageCode: "ru") == "Текущий режим: Debug premium")

        #expect(localizedString("profile.premium.diagnostics.title", languageCode: "en") == "Premium diagnostics")
        #expect(localizedString("profile.premium.diagnostics.title", languageCode: "ru") == "Диагностика PRO")

        #expect(localizedString("profile.premium.diagnostics.summary", languageCode: "en") == "%ld/%ld active")
        #expect(localizedString("profile.premium.diagnostics.summary", languageCode: "ru") == "%ld/%ld активно")

        #expect(localizedString("profile.premium.diagnostics.current_access", languageCode: "en") == "Current entitlement")
        #expect(localizedString("profile.premium.diagnostics.current_access", languageCode: "ru") == "Текущий доступ")

        #expect(localizedString("profile.premium.diagnostics.effective_premium", languageCode: "en") == "Premium enabled")
        #expect(localizedString("profile.premium.diagnostics.effective_premium", languageCode: "ru") == "Эффективный premium")

        #expect(localizedString("profile.premium.diagnostics.stored_status", languageCode: "en") == "Stored entitlement")
        #expect(localizedString("profile.premium.diagnostics.stored_status", languageCode: "ru") == "Сохранённый статус")

        #expect(localizedString("profile.premium.diagnostics.trial", languageCode: "en") == "Trial")
        #expect(localizedString("profile.premium.diagnostics.trial", languageCode: "ru") == "Триал")

        #expect(localizedString("profile.premium.diagnostics.trial_disabled", languageCode: "en") == "Trial disabled by override")
        #expect(localizedString("profile.premium.diagnostics.trial_disabled", languageCode: "ru") == "Триал отключен (override)")

        #expect(localizedString("profile.premium.diagnostics.expiration", languageCode: "en") == "Expires on")
        #expect(localizedString("profile.premium.diagnostics.expiration", languageCode: "ru") == "Истекает")

        #expect(localizedString("profile.premium.diagnostics.behavior", languageCode: "en") == "Premium impact by feature")
        #expect(localizedString("profile.premium.diagnostics.behavior", languageCode: "ru") == "Где premium меняет поведение")

        #expect(localizedString("profile.premium.diagnostics.status.not_subscribed", languageCode: "en") == "No active subscription")
        #expect(localizedString("profile.premium.diagnostics.status.not_subscribed", languageCode: "ru") == "Нет подписки")
    }

    @Test("Profile auth strings are localized with product-grade wording")
    func testProfileAuthLocalization() {
        #expect(localizedString("profile.auth.connected", languageCode: "en") == "Signed in with Apple")
        #expect(localizedString("profile.auth.connected", languageCode: "ru") == "Вход через Apple ID")

        #expect(localizedString("profile.auth.connected.subtitle", languageCode: "en") == "Account sync is enabled for this account. iCloud backup uses the current Apple account on this device.")
        #expect(localizedString("profile.auth.connected.subtitle", languageCode: "ru") == "Для этого аккаунта включена синхронизация. Резервные копии iCloud используют текущий Apple ID на этом устройстве.")

        #expect(localizedString("profile.auth.details", languageCode: "en") == "View details")
        #expect(localizedString("profile.auth.details", languageCode: "ru") == "Подробнее")

        #expect(localizedString("profile.auth.email_missing", languageCode: "en") == "No email provided")
        #expect(localizedString("profile.auth.email_missing", languageCode: "ru") == "Email не указан")

        #expect(localizedString("profile.auth.guest.title", languageCode: "en") == "Guest Mode")
        #expect(localizedString("profile.auth.guest.subtitle", languageCode: "en") == "Use Millio now and connect your Apple Account later.")
        #expect(localizedString("profile.auth.exit_guest", languageCode: "en") == "Leave Guest Mode")

        #expect(localizedString("profile.auth.last_login", languageCode: "en") == "Last sign-in")
        #expect(localizedString("profile.auth.logout", languageCode: "en") == "Sign out")

        #expect(localizedString("profile.auth.not_signed_in", languageCode: "en") == "Not signed in")
        #expect(localizedString("profile.auth.not_signed_in.subtitle", languageCode: "en") == "Sign in with Apple to enable account sync. iCloud backup works separately.")
    }

    @Test("Backup screen key strings are localized and do not end with a period")
    func testBackupScreenLocalizationWithoutTrailingPeriod() {
        let keys = [
            "backup.screen.subtitle",
            "backup.dashboard.subtitle.last_backup_format",
            "backup.dashboard.trust.detail.passphrase",
            "backup.actions.create.subtitle.safety",
            "backup.actions.auto_schedule.note",
            "backup.limit.reached.message",
            "backup.statusline.ready"
        ]

        for key in keys {
            let en = localizedString(key, languageCode: "en")
            let ru = localizedString(key, languageCode: "ru")
            #expect(en != key, "Missing English localization for \(key)")
            #expect(ru != key, "Missing Russian localization for \(key)")
            #expect(en.hasSuffix(".") == false, "English text for \(key) should not end with a period")
            #expect(ru.hasSuffix(".") == false, "Russian text for \(key) should not end with a period")
        }
    }
}
