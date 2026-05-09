//
//  BackupLocalization.swift
//  millio
//

import Foundation

enum BackupL10n {
    private static var locale: Locale {
        AppLocalization.currentAppLocale
    }

    static func tr(_ key: String, fallback: String) -> String {
        tr(key, locale: locale, fallback: fallback)
    }

    static func tr(_ key: String, locale: Locale, fallback: String) -> String {
        let localized = AppLocalization.string(key, locale: locale, fallback: nil)
        if localized != key {
            return localized
        }

        if let inline = BackupInlineCatalog.text(for: key, locale: locale) {
            return inline
        }

        return fallback
    }

    static func format(_ key: String, fallback: String, _ args: CVarArg...) -> String {
        String(format: tr(key, locale: locale, fallback: fallback), locale: locale, arguments: args)
    }

    static func format(_ key: String, locale: Locale, fallback: String, _ args: CVarArg...) -> String {
        String(format: tr(key, locale: locale, fallback: fallback), locale: locale, arguments: args)
    }

    static func hasInlineTranslation(for key: String) -> Bool {
        BackupInlineCatalog.contains(key)
    }
}

private enum BackupInlineCatalog {
    struct Entry {
        let en: String
        let ru: String
        let zhHans: String

        func resolve(in locale: Locale) -> String {
            switch LocalizationSupport.effectiveLanguage(for: locale) {
            case Language.russian.rawValue:
                return ru
            case Language.simplifiedChinese.rawValue:
                return zhHans
            default:
                return en
            }
        }
    }

    // Backup is mid-migration to the shared string catalog. Keep all screen-specific
    // fallback copy centralized here so missing catalog entries cannot silently fall
    // back to English on Russian or Chinese devices.
    private static let entries: [String: Entry] = [
        "backup.auto-restore.title": .init(
            en: "Restoring Data",
            ru: "Восстанавливаем данные",
            zhHans: "正在恢复数据"
        ),
        "backup.auto-restore.subtitle": .init(
            en: "Restoring from backup of %@",
            ru: "Восстанавливаем резервную копию от %@",
            zhHans: "正在恢复 %@ 的备份"
        ),
        "backup.actions.create.subtitle.busy": .init(
            en: "Another backup task is running",
            ru: "Уже идёт другая операция с копией",
            zhHans: "另一项备份操作正在进行"
        ),
        "backup.dashboard.storage.title.icloud": .init(
            en: "Saved in iCloud",
            ru: "Сохранено в iCloud",
            zhHans: "已保存到 iCloud"
        ),
        "backup.dashboard.storage.title.local": .init(
            en: "Only on this device",
            ru: "Только на этом iPhone",
            zhHans: "仅在这台 iPhone 上"
        ),
        "backup.dashboard.storage.title.unavailable": .init(
            en: "iCloud unavailable",
            ru: "iCloud недоступен",
            zhHans: "iCloud 不可用"
        ),
        "backup.dashboard.subtitle.almost": .init(
            en: "Save one backup now so restore is ready if anything goes wrong",
            ru: "Сохраните первую копию сейчас, чтобы потом можно было восстановиться",
            zhHans: "现在先保存第一份备份，这样出问题时就能恢复"
        ),
        "backup.dashboard.subtitle.off": .init(
            en: "Turn on backup to keep a recovery copy in iCloud",
            ru: "Включите резервное копирование, чтобы держать копию для восстановления в iCloud",
            zhHans: "开启备份后，iCloud 中会保留一份可恢复的副本"
        ),
        "backup.dashboard.title.almost": .init(
            en: "Create your first backup",
            ru: "Создайте первую копию",
            zhHans: "创建第一份备份"
        ),
        "backup.dashboard.title.off": .init(
            en: "Your data is only local",
            ru: "Данные пока только локально",
            zhHans: "你的数据目前只在本机"
        ),
        "backup.hint.confirm_passphrase": .init(
            en: "Tap Done to confirm the passphrase",
            ru: "Нажмите «Готово», чтобы подтвердить кодовую фразу",
            zhHans: "点按“完成”以确认口令短语"
        ),
        "backup.hint.enable_backup": .init(
            en: "Enable backup",
            ru: "Включите резервное копирование",
            zhHans: "请先开启备份"
        ),
        "backup.hint.enter_passphrase": .init(
            en: "Enter a passphrase",
            ru: "Введите кодовую фразу",
            zhHans: "请输入口令短语"
        ),
        "backup.hint.passphrase_mismatch": .init(
            en: "Passphrases do not match",
            ru: "Кодовые фразы не совпадают",
            zhHans: "两次输入的口令短语不一致"
        ),
        "backup.hint.select_restore_version": .init(
            en: "Select a version to restore",
            ru: "Выберите версию для восстановления",
            zhHans: "请选择要恢复的版本"
        ),
        "backup.passphrase.confirm_placeholder": .init(
            en: "Repeat passphrase",
            ru: "Повторите кодовую фразу",
            zhHans: "再次输入口令短语"
        ),
        "backup.passphrase.edit": .init(
            en: "Edit",
            ru: "Изменить",
            zhHans: "编辑"
        ),
        "backup.passphrase.helper.edit": .init(
            en: "Choose a phrase you can type again later on another device",
            ru: "Придумайте фразу, которую сможете ввести позже на другом устройстве",
            zhHans: "请设置一条以后在另一台设备上也能再次输入的口令短语"
        ),
        "backup.passphrase.helper.saved": .init(
            en: "Saved locally for convenience, keep your own copy somewhere safe",
            ru: "Локально сохранена для удобства, но свою копию всё равно держите отдельно",
            zhHans: "已为方便保存在本机，但你仍应自行另存一份"
        ),
        "backup.passphrase.hint.invalid": .init(
            en: "Both fields should match",
            ru: "Оба поля должны совпадать",
            zhHans: "两个输入框的内容必须一致"
        ),
        "backup.passphrase.hint.valid": .init(
            en: "Looks good, this will be used for backup and restore",
            ru: "Подходит, эта фраза будет использоваться для резервного копирования и восстановления",
            zhHans: "可以，这条口令短语将用于备份和恢复"
        ),
        "backup.passphrase.placeholder": .init(
            en: "Passphrase",
            ru: "Кодовая фраза",
            zhHans: "口令短语"
        ),
        "backup.passphrase.save": .init(
            en: "Save passphrase",
            ru: "Сохранить кодовую фразу",
            zhHans: "保存口令短语"
        ),
        "backup.passphrase.section.subtitle.confirmed": .init(
            en: "Ready for backup and restore",
            ru: "Всё готово для копирования и восстановления",
            zhHans: "已可用于备份和恢复"
        ),
        "backup.passphrase.section.subtitle.input": .init(
            en: "Create it once, then reuse it",
            ru: "Создайте один раз и используйте дальше",
            zhHans: "创建一次，之后重复使用"
        ),
        "backup.passphrase.section.title": .init(
            en: "Your passphrase",
            ru: "Ваша кодовая фраза",
            zhHans: "你的口令短语"
        ),
        "backup.passphrase.summary.subtitle": .init(
            en: "Used for backup and restore, change it only if needed",
            ru: "Используется для копирования и восстановления, меняйте только при необходимости",
            zhHans: "用于备份和恢复，仅在确有需要时再修改"
        ),
        "backup.passphrase.summary.title": .init(
            en: "Saved",
            ru: "Сохранена",
            zhHans: "已保存"
        ),
        "backup.protection.summary.passphrase_pending": .init(
            en: "Finish passphrase setup to use portable restore",
            ru: "Завершите настройку кодовой фразы, чтобы восстанавливать на другом устройстве",
            zhHans: "完成口令短语设置后，才能在其他设备上恢复"
        ),
        "backup.readiness.backup_enabled.detail.off": .init(
            en: "Turn backup on",
            ru: "Включите резервное копирование",
            zhHans: "请先开启备份"
        ),
        "backup.readiness.backup_enabled.detail.on": .init(
            en: "Millio can create and refresh backups",
            ru: "Millio может создавать и обновлять копии",
            zhHans: "Millio 已可创建并更新备份"
        ),
        "backup.readiness.backup_enabled.title": .init(
            en: "Backup is enabled",
            ru: "Резервное копирование включено",
            zhHans: "备份已开启"
        ),
        "backup.readiness.has_pinned.detail.off": .init(
            en: "Save one before a risky change or update",
            ru: "Сохраните ручную версию перед рискованным изменением или обновлением",
            zhHans: "在高风险改动或更新前，先手动保存一份版本"
        ),
        "backup.readiness.has_pinned.detail.on": .init(
            en: "You saved a version that stays until you delete it",
            ru: "У вас уже есть ручная версия, она останется, пока вы её не удалите",
            zhHans: "你已经保存了一份手动版本，它会一直保留直到你删除"
        ),
        "backup.readiness.has_pinned.title": .init(
            en: "Manual version exists",
            ru: "Есть ручная версия",
            zhHans: "已有手动版本"
        ),
        "backup.readiness.has_recent.detail.off": .init(
            en: "Create your first backup now",
            ru: "Создайте первую копию сейчас",
            zhHans: "现在创建第一份备份"
        ),
        "backup.readiness.has_recent.detail.on": .init(
            en: "You already have something to restore from",
            ru: "У вас уже есть копия для восстановления",
            zhHans: "你已经有可用于恢复的备份"
        ),
        "backup.readiness.has_recent.title": .init(
            en: "A backup exists",
            ru: "Копия уже есть",
            zhHans: "已有备份"
        ),
        "backup.readiness.icloud.detail.off": .init(
            en: "Check iCloud sign-in and Millio access",
            ru: "Проверьте вход в iCloud и доступ для Millio",
            zhHans: "请检查 iCloud 登录状态和 Millio 的访问权限"
        ),
        "backup.readiness.icloud.detail.on": .init(
            en: "Saving and restore are available now",
            ru: "Сохранение и восстановление уже доступны",
            zhHans: "现在已经可以保存和恢复"
        ),
        "backup.readiness.icloud.title": .init(
            en: "iCloud is available",
            ru: "iCloud доступен",
            zhHans: "iCloud 可用"
        ),
        "backup.readiness.protection.detail.device": .init(
            en: "Restore is tied to this iPhone",
            ru: "Восстановление привязано к этому iPhone",
            zhHans: "恢复仅限这台 iPhone"
        ),
        "backup.readiness.protection.detail.passphrase": .init(
            en: "Portable restore with your passphrase",
            ru: "Переносимое восстановление по вашей кодовой фразе",
            zhHans: "可使用你的口令短语在其他设备上恢复"
        ),
        "backup.readiness.protection.title": .init(
            en: "Recovery method is chosen",
            ru: "Способ восстановления выбран",
            zhHans: "恢复方式已选定"
        ),
        "backup.restore.empty.title.icloud_unavailable": .init(
            en: "iCloud is unavailable",
            ru: "iCloud недоступен",
            zhHans: "iCloud 不可用"
        ),
        "backup.restore.empty.title.not_found": .init(
            en: "Backup not found",
            ru: "Резервная копия не найдена",
            zhHans: "未找到备份"
        ),
        "backup.restore.confirm.title": .init(
            en: "Continue Without Restoring?",
            ru: "Продолжить без восстановления?",
            zhHans: "确定不恢复吗？"
        ),
        "backup.restore.confirm.action": .init(
            en: "Continue Without Restoring",
            ru: "Продолжить без восстановления",
            zhHans: "继续且不恢复"
        ),
        "backup.restore.confirm.cancel": .init(
            en: "Cancel",
            ru: "Отмена",
            zhHans: "取消"
        ),
        "backup.restore.confirm.message": .init(
            en: "Local data will remain as is.",
            ru: "Локальные данные останутся как есть.",
            zhHans: "本地数据将保持不变。"
        ),
        "backup.restore.header.title": .init(
            en: "Restore",
            ru: "Восстановление",
            zhHans: "恢复"
        ),
        "backup.restore.header.subtitle": .init(
            en: "Select a backup. Restoring will replace your current local data.",
            ru: "Выберите копию. Восстановление заменит текущие локальные данные.",
            zhHans: "选择备份。恢复操作将替换当前本地数据。"
        ),
        "backup.restore.progress.title": .init(
            en: "Restoring Data",
            ru: "Восстанавливаем данные",
            zhHans: "正在恢复数据"
        ),
        "backup.restore.progress.subtitle": .init(
            en: "Please wait, the database will be replaced with the selected backup.",
            ru: "Подождите, база будет заменена выбранной копией.",
            zhHans: "请稍候，数据库将被所选备份替换。"
        ),
        "backup.restore.version.pinned": .init(
            en: "Saved Version",
            ru: "Сохраненная версия",
            zhHans: "已保存版本"
        ),
        "backup.restore.version.latest": .init(
            en: "Latest Backup",
            ru: "Последняя копия",
            zhHans: "最新备份"
        ),
        "backup.restore.metric.date": .init(
            en: "Date",
            ru: "Дата",
            zhHans: "日期"
        ),
        "backup.restore.metric.size": .init(
            en: "Size",
            ru: "Размер",
            zhHans: "大小"
        ),
        "backup.restore.warning.replace": .init(
            en: "Local data will be completely replaced.",
            ru: "Локальные данные будут полностью заменены.",
            zhHans: "本地数据将被完全替换。"
        ),
        "backup.restore.action.pick_another": .init(
            en: "Select Another Backup",
            ru: "Выбрать другую копию",
            zhHans: "选择其他备份"
        ),
        "backup.restore.passphrase.placeholder": .init(
            en: "Passphrase (if any)",
            ru: "Кодовая фраза (если есть)",
            zhHans: "口令短语（如有）"
        ),
        "backup.restore.slide.title": .init(
            en: "Restore From Backup",
            ru: "Восстановить из копии",
            zhHans: "从备份恢复"
        ),
        "backup.restore.slide.subtitle": .init(
            en: "Slide to replace local data",
            ru: "Сдвиньте, чтобы заменить локальные данные",
            zhHans: "滑动以替换本地数据"
        ),
        "backup.restore.slide.loading.title": .init(
            en: "Restoring data...",
            ru: "Восстанавливаем данные...",
            zhHans: "正在恢复数据..."
        ),
        "backup.restore.slide.loading.subtitle": .init(
            en: "Don't close the app while replacing",
            ru: "Не закрывайте приложение, пока идет замена",
            zhHans: "替换完成前请勿关闭应用"
        ),
        "backup.restore.action.skip": .init(
            en: "Continue Without Restoring",
            ru: "Продолжить без восстановления",
            zhHans: "继续且不恢复"
        ),
        "backup.restore.lookup.timedout": .init(
            en: "Still Searching",
            ru: "Поиск еще идет",
            zhHans: "正在搜索中"
        ),
        "backup.restore.empty.status.not_found": .init(
            en: "Backup Not Found",
            ru: "Копия не найдена",
            zhHans: "未找到备份"
        ),
        "backup.restore.action.retry": .init(
            en: "Retry Search",
            ru: "Повторить поиск",
            zhHans: "重试搜索"
        ),
        "backup.restore.action.short": .init(
            en: "Restore this version",
            ru: "Восстановить эту версию",
            zhHans: "恢复此版本"
        ),
        "backup.restore.success.title": .init(
            en: "Data Restored",
            ru: "Данные восстановлены",
            zhHans: "数据已恢复"
        ),
        "backup.restore.success.message": .init(
            en: "Your data has been restored and will appear in the app shortly",
            ru: "Ваши данные восстановлены и скоро отобразятся в приложении",
            zhHans: "您的数据已恢复，稍后将显示在应用中"
        ),
        "common.done": .init(
            en: "Done",
            ru: "Готово",
            zhHans: "完成"
        )
    ]

    static func text(for key: String, locale: Locale) -> String? {
        entries[key]?.resolve(in: locale)
    }

    static func contains(_ key: String) -> Bool {
        entries[key] != nil
    }
}
