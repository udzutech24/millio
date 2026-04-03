import Foundation
import Testing
@testable import millio

@Suite("Profile localization")
struct ProfileLocalizationTests {
    private func localizedString(_ key: String, languageCode: String) -> String {
        AppLocalization.string(key, locale: Locale(identifier: languageCode))
    }

    @Test("Profile menu strings are localized for English, Russian, and Simplified Chinese locales")
    func testProfileMenuLocalization() {
        #expect(localizedString("profile.launch_splash.title", languageCode: "en") == "Launch screen")
        #expect(localizedString("profile.launch_splash.title", languageCode: "ru") == "Заставка при запуске")
        #expect(localizedString("profile.launch_splash.title", languageCode: "zh-Hans") == "启动画面")

        #expect(localizedString("profile.launch_splash.mode.always", languageCode: "en") == "Always")
        #expect(localizedString("profile.launch_splash.mode.always", languageCode: "ru") == "Всегда")
        #expect(localizedString("profile.launch_splash.mode.always", languageCode: "zh-Hans") == "始终显示")

        #expect(localizedString("profile.launch_splash.mode.once_per_day", languageCode: "en") == "Once per day")
        #expect(localizedString("profile.launch_splash.mode.once_per_day", languageCode: "ru") == "Раз в день")
        #expect(localizedString("profile.launch_splash.mode.once_per_day", languageCode: "zh-Hans") == "每天一次")

        #expect(localizedString("profile.launch_splash.mode.off", languageCode: "en") == "Off")
        #expect(localizedString("profile.launch_splash.mode.off", languageCode: "ru") == "Выключено")
        #expect(localizedString("profile.launch_splash.mode.off", languageCode: "zh-Hans") == "关闭")

        #expect(localizedString("profile.faq.title", languageCode: "en") == "FAQ")
        #expect(localizedString("profile.faq.title", languageCode: "ru") == "Вопросы и ответы")

        #expect(localizedString("profile.faq.basic", languageCode: "en") == "FAQ for getting started")
        #expect(localizedString("profile.faq.basic", languageCode: "ru") == "Базовые вопросы")

        #expect(localizedString("profile.faq.subtitle", languageCode: "en") == "Quick answers about how Millio works.")
        #expect(localizedString("profile.faq.subtitle", languageCode: "ru") == "Здесь собраны базовые ответы по работе приложения.")

        #expect(localizedString("profile.faq.question_prefix", languageCode: "en") == "Q:")
        #expect(localizedString("profile.faq.question_prefix", languageCode: "ru") == "В:")

        #expect(localizedString("profile.smart_data_reset", languageCode: "en") == "Guided data reset")
        #expect(localizedString("profile.smart_data_reset", languageCode: "ru") == "Пошаговый сброс данных")
    }

    @Test("Rate app copy stays language-specific on profile")
    func testProfileRateAppLocalization() {
        #expect(localizedString("profile.rate_app.block.eyebrow", languageCode: "en") == "Your voice")
        #expect(localizedString("profile.rate_app.block.title", languageCode: "en") == "How do you like Millio?")
        #expect(localizedString("profile.rate_app.block.subtitle", languageCode: "en") == "A short review helps us make Millio better")
        #expect(localizedString("profile.rate_app.summary.idle", languageCode: "en") == "Choose a rating")
        #expect(localizedString("profile.rate_app.dialog.rate.title", languageCode: "en") == "Thank you!")

        #expect(localizedString("profile.rate_app.block.eyebrow", languageCode: "zh-Hans") == "你的声音")
        #expect(localizedString("profile.rate_app.block.title", languageCode: "zh-Hans") == "你觉得 Millio 怎么样？")
        #expect(localizedString("profile.rate_app.block.subtitle", languageCode: "zh-Hans") == "简短的反馈能帮助我们把 Millio 做得更好")
        #expect(localizedString("profile.rate_app.summary.idle", languageCode: "zh-Hans") == "请选择评分")
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

    @Test("Profile root screen strings are localized for Simplified Chinese")
    func testProfileRootLocalizationInSimplifiedChinese() {
        #expect(localizedString("profile.title", languageCode: "zh-Hans") == "个人资料")
        #expect(localizedString("profile.greeting", languageCode: "zh-Hans") == "你好，")
        #expect(localizedString("profile.language", languageCode: "zh-Hans") == "语言")
        #expect(localizedString("profile.currency", languageCode: "zh-Hans") == "货币")
        #expect(localizedString("profile.premium.title", languageCode: "zh-Hans") == "millio PRO")
        #expect(localizedString("profile.premium.details", languageCode: "zh-Hans") == "了解更多")
        #expect(localizedString("profile.backup", languageCode: "zh-Hans") == "备份")
        #expect(localizedString("profile.security", languageCode: "zh-Hans") == "应用安全")
        #expect(localizedString("profile.reminders", languageCode: "zh-Hans") == "提醒")
        #expect(localizedString("profile.status.disabled", languageCode: "zh-Hans") == "已关闭")
        #expect(localizedString("profile.quick_setup", languageCode: "zh-Hans") == "快速设置")
        #expect(localizedString("profile.status.not_completed", languageCode: "zh-Hans") == "未完成")
        #expect(localizedString("profile.section.general", languageCode: "zh-Hans") == "通用")
        #expect(localizedString("profile.section.settings", languageCode: "zh-Hans") == "设置")
        #expect(localizedString("profile.section.experience", languageCode: "zh-Hans") == "使用体验")
        #expect(localizedString("profile.section.support", languageCode: "zh-Hans") == "帮助与工具")
        #expect(localizedString("profile.section.about", languageCode: "zh-Hans") == "关于")
        #expect(localizedString("profile.section.contacts", languageCode: "zh-Hans") == "联系方式")
        #expect(localizedString("profile.section.debug", languageCode: "zh-Hans") == "调试")
        #expect(localizedString("profile.auth.guest.title", languageCode: "zh-Hans") == "访客模式")
        #expect(localizedString("profile.auth.guest.subtitle", languageCode: "zh-Hans") == "现在就开始使用 Millio，稍后再连接你的 Apple 账户。")
        #expect(localizedString("profile.auth.exit_guest", languageCode: "zh-Hans") == "退出访客模式")
        #expect(localizedString("profile.premium_access", languageCode: "zh-Hans") == "PRO 访问权限")
        #expect(localizedString("profile.trial_disabled", languageCode: "zh-Hans") == "禁用试用")
        #expect(localizedString("profile.show_onboarding", languageCode: "zh-Hans") == "显示引导")
    }

    @Test("Profile nested screen strings are localized for Simplified Chinese")
    func testProfileNestedFlowLocalizationInSimplifiedChinese() {
        #expect(localizedString("profile.language.all_languages", languageCode: "zh-Hans") == "所有语言")
        #expect(localizedString("profile.language.navigation_title", languageCode: "zh-Hans") == "语言")
        #expect(localizedString("profile.language.search_placeholder", languageCode: "zh-Hans") == "搜索语言")

        #expect(localizedString("profile.faq.basic", languageCode: "zh-Hans") == "入门常见问题")
        #expect(localizedString("profile.faq.question_prefix", languageCode: "zh-Hans") == "问：")
        #expect(localizedString("profile.faq.subtitle", languageCode: "zh-Hans") == "关于 Millio 如何工作的快速解答。")

        #expect(localizedString("profile.contact.header.title", languageCode: "zh-Hans") == "我们随时为你提供帮助。")
        #expect(localizedString("profile.contact.option.email", languageCode: "zh-Hans") == "电子邮件")
        #expect(localizedString("profile.contact.option.telegram", languageCode: "zh-Hans") == "Telegram")
        #expect(localizedString("profile.contact.option.whatsapp", languageCode: "zh-Hans") == "WhatsApp")

        #expect(localizedString("profile.security.pin", languageCode: "zh-Hans") == "PIN 码")
        #expect(localizedString("profile.security.change_pin", languageCode: "zh-Hans") == "更改 PIN 码")
        #expect(localizedString("profile.security.biometrics_unavailable", languageCode: "zh-Hans") == "此设备不支持生物识别。")
        #expect(localizedString("profile.daily_reminders.summary.kind.expense", languageCode: "zh-Hans") == "支出")
        #expect(localizedString("profile.daily_reminders.summary.kind.selected", languageCode: "zh-Hans") == "所选项目")

        #expect(localizedString("profile.pin_setup.title.create", languageCode: "zh-Hans") == "PIN 码")
        #expect(localizedString("profile.pin_setup.title.change", languageCode: "zh-Hans") == "更改 PIN 码")
        #expect(localizedString("profile.pin_setup.step.verify_current", languageCode: "zh-Hans") == "输入当前 PIN 码")
        #expect(localizedString("profile.pin_setup.step.enter_new", languageCode: "zh-Hans") == "输入新 PIN 码")
        #expect(localizedString("profile.pin_setup.step.confirm_new", languageCode: "zh-Hans") == "再次输入新 PIN 码")
        #expect(localizedString("profile.pin_setup.error.incorrect_current", languageCode: "zh-Hans") == "当前 PIN 码不正确")
        #expect(localizedString("profile.pin_setup.error.mismatch", languageCode: "zh-Hans") == "两次输入的 PIN 码不一致")
        #expect(localizedString("profile.pin_setup.error.save_failed", languageCode: "zh-Hans") == "PIN 码保存失败")

        #expect(localizedString("profile.app_lock.screen.title", languageCode: "zh-Hans") == "请输入 PIN 码")
        #expect(localizedString("profile.app_lock.error.invalid_pin", languageCode: "zh-Hans") == "PIN 码不正确")
        #expect(localizedString("profile.app_lock.button.face_id", languageCode: "zh-Hans") == "使用 Face ID 解锁")
        #expect(localizedString("profile.app_lock.button.touch_id", languageCode: "zh-Hans") == "使用 Touch ID 解锁")
        #expect(localizedString("profile.app_lock.button.biometrics", languageCode: "zh-Hans") == "使用生物识别解锁")
        #expect(localizedString("profile.app_lock.auth.reason", languageCode: "zh-Hans") == "解锁应用数据访问")

        #expect(localizedString("common.cancel", languageCode: "zh-Hans") == "取消")
    }

    @Test("Profile auth helper follows the current app language at runtime")
    func testProfileAuthHelperUsesCurrentAppLanguage() throws {
        AppLanguageTestSupport.withLanguage(.english) {
            #expect(ProfileAuthL10n.guestTitle() == "Guest Mode")
            #expect(ProfileAuthL10n.guestSubtitle() == "Use Millio now and connect your Apple Account later.")
            #expect(ProfileAuthL10n.exitGuestTitle() == "Leave Guest Mode")
        }

        AppLanguageTestSupport.withLanguage(.russian) {
            #expect(ProfileAuthL10n.guestTitle() == "Гостевой режим")
            #expect(ProfileAuthL10n.guestSubtitle() == "Используйте Millio сейчас и подключите Apple ID позже.")
            #expect(ProfileAuthL10n.exitGuestTitle() == "Выйти из гостевого режима")
        }

        AppLanguageTestSupport.withLanguage(.simplifiedChinese) {
            #expect(ProfileAuthL10n.guestTitle() == "访客模式")
            #expect(ProfileAuthL10n.guestSubtitle() == "现在就开始使用 Millio，稍后再连接你的 Apple 账户。")
            #expect(ProfileAuthL10n.exitGuestTitle() == "退出访客模式")
        }
    }

    @Test("Daily reminder summary subject keys are localized for English and Russian")
    func testDailyReminderSummarySubjectLocalization() {
        #expect(localizedString("profile.daily_reminders.summary.kind.expense", languageCode: "en") == "expenses")
        #expect(localizedString("profile.daily_reminders.summary.kind.custom", languageCode: "en") == "custom notes")
        #expect(localizedString("profile.daily_reminders.summary.kind.selected", languageCode: "en") == "selected items")

        #expect(localizedString("profile.daily_reminders.summary.kind.expense", languageCode: "ru") == "расходах")
        #expect(localizedString("profile.daily_reminders.summary.kind.income", languageCode: "ru") == "доходах")
        #expect(localizedString("profile.daily_reminders.summary.kind.custom", languageCode: "ru") == "своих заметках")
        #expect(localizedString("profile.daily_reminders.summary.kind.selected", languageCode: "ru") == "выбранных записях")
    }

    @Test("Backup screen strings are localized for Simplified Chinese")
    func testBackupLocalizationInSimplifiedChinese() {
        #expect(localizedString("backup.screen.title", languageCode: "zh-Hans") == "备份")
        #expect(localizedString("backup.screen.subtitle", languageCode: "zh-Hans") == "保护你的数据、快速恢复，并在高风险改动前保留手动版本")
        #expect(localizedString("backup.actions.create.primary.first", languageCode: "zh-Hans") == "创建第一份备份")
        #expect(localizedString("backup.actions.restore.primary.go", languageCode: "zh-Hans") == "恢复所选备份")
        #expect(localizedString("backup.auto_toggle.title", languageCode: "zh-Hans") == "每日自动备份")
        #expect(localizedString("backup.protection.recommended", languageCode: "zh-Hans") == "推荐")
        #expect(localizedString("backup.restore.confirm.title", languageCode: "zh-Hans") == "恢复这个版本？")
        #expect(localizedString("backup.statusline.ready", languageCode: "zh-Hans") == "已做好恢复准备")
        #expect(localizedString("backup.storage.local", languageCode: "zh-Hans") == "本地")
        #expect(localizedString("backup.versions.title", languageCode: "zh-Hans") == "版本")
    }

    @Test("Primary currency picker strings are localized for Simplified Chinese")
    func testPrimaryCurrencyPickerLocalizationInSimplifiedChinese() {
        #expect(localizedString("converter.currency.add", languageCode: "zh-Hans") == "添加货币")
        #expect(localizedString("converter.currency.search_placeholder", languageCode: "zh-Hans") == "按代码或名称搜索")
        #expect(localizedString("converter.currency.primary", languageCode: "zh-Hans") == "基础货币")
        #expect(localizedString("converter.currency.favorites", languageCode: "zh-Hans") == "收藏")
        #expect(localizedString("converter.currency.all", languageCode: "zh-Hans") == "所有货币")
    }

    @Test("Converter settings and share screens are localized for Simplified Chinese")
    func testConverterSettingsAndShareLocalizationInSimplifiedChinese() {
        #expect(localizedString("converter.common.cancel", languageCode: "zh-Hans") == "取消")
        #expect(localizedString("converter.common.done", languageCode: "zh-Hans") == "完成")
        #expect(localizedString("converter.settings.title", languageCode: "zh-Hans") == "货币换算器")
        #expect(localizedString("converter.settings.last_update", languageCode: "zh-Hans") == "上次更新")
        #expect(localizedString("converter.settings.refresh_rates", languageCode: "zh-Hans") == "刷新汇率")
        #expect(localizedString("converter.settings.widget.preview_title", languageCode: "zh-Hans") == "换算器小组件")
        #expect(localizedString("converter.share.history_title", languageCode: "zh-Hans") == "分享历史")
        #expect(localizedString("converter.share.history_empty", languageCode: "zh-Hans") == "还没有分享的快照")
        #expect(localizedString("converter.share.preview_title", languageCode: "zh-Hans") == "分享快照")
        #expect(localizedString("converter.share.message_placeholder", languageCode: "zh-Hans") == "添加说明：你分享的内容，以及它为什么重要")
    }

    @Test("Converter search placeholder English copy is correct")
    func testConverterSearchPlaceholderEnglishCopy() {
        #expect(localizedString("converter.currency.search_placeholder", languageCode: "en") == "Search by code or name")
    }

    @Test("Currency picker uses locale-aware currency names instead of hardcoded Russian")
    func testCurrencyPickerLocalizedNames() {
        #expect(CurrencySelectionSupport.localizedName(for: "USD", locale: Locale(identifier: "zh-Hans")) == "美元")
        #expect(CurrencySelectionSupport.localizedName(for: "USD", locale: Locale(identifier: "ru")) == "доллар США")
        #expect(CurrencySelectionSupport.localizedName(for: "BTC", locale: Locale(identifier: "zh-Hans")) == "Bitcoin")
    }

    @Test("Primary currency confirmation uses locale-aware currency names")
    func testPrimaryCurrencyConfirmationUsesLocalizedCurrencyName() {
        let chineseContent = PrimaryCurrencyConfirmationContent(
            locale: Locale(identifier: "zh-Hans"),
            pendingCode: "USD"
        )
        let russianContent = PrimaryCurrencyConfirmationContent(
            locale: Locale(identifier: "ru"),
            pendingCode: "USD"
        )

        #expect(chineseContent.currencyName == "美元")
        #expect(russianContent.currencyName == "доллар США")
    }

    @Test("Profile FAQ content and legal titles are available for Simplified Chinese")
    func testProfileFAQContentAndLegalLinksInSimplifiedChinese() {
        let sections = ProfileFAQContent.sections(for: .simplifiedChinese)

        #expect(sections.count == 2)
        #expect(sections.first?.title == "常见问题")
        #expect(sections.first?.items.first?.question == "millio 是什么？")
        #expect(sections.first?.items.first?.answerParagraphs.first == "millio 是一款个人财务应用，可在一个地方管理余额、现金流、汇率转换、贷款和投资。")
        #expect(sections.first?.items[1].note == "任何应用都无法保证 100% 安全。请使用强设备密码，并保持 iOS 为最新版本。")

        let legalLinks = ProfileLegalLinks.make(for: .simplifiedChinese)
        #expect(legalLinks.privacyTitle == "隐私政策")
        #expect(legalLinks.termsTitle == "使用条款（EULA）")
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

    @Test("Backup localization helper resolves Simplified Chinese strings with explicit locale")
    func testBackupLocalizationHelperWithExplicitChineseLocale() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(BackupL10n.tr("backup.screen.title", locale: locale, fallback: "Backup") == "备份")
        #expect(
            BackupL10n.format(
                "backup.versions.count_format",
                locale: locale,
                fallback: "%lld",
                4
            ) == "4"
        )
    }
}
