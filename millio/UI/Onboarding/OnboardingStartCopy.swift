import Foundation

enum OnboardingStartCopy {
    static func badge(locale: Locale) -> String {
        QuickSetupLocalization.text(locale: locale, ru: "ПУСКОВОЙ ПРОТОКОЛ", en: "STARTUP PROTOCOL")
    }

    static func title(locale: Locale) -> String {
        QuickSetupLocalization.text(locale: locale, ru: "Инициализация рабочего профиля", en: "Initialize your working profile")
    }

    static func subtitle(locale: Locale) -> String {
        QuickSetupLocalization.text(
            locale: locale,
            ru: "Система зафиксирует язык, валютный контур, категории расходов и режим резервного хранения",
            en: "The system will lock language, currency scope, expense categories, and backup mode"
        )
    }

    static func primaryAction(locale: Locale) -> String {
        QuickSetupLocalization.text(locale: locale, ru: "Запустить быструю настройку", en: "Start quick setup")
    }

    static func secondaryAction(locale: Locale) -> String {
        QuickSetupLocalization.text(locale: locale, ru: "Пропустить и перейти в систему", en: "Skip and enter workspace")
    }

    static func checkpoints(locale: Locale) -> [String] {
        QuickSetupLocalization.isRussian(locale) ? russianCheckpoints : englishCheckpoints
    }

    private static let russianCheckpoints: [String] = [
        "Рабочий язык и расчетные валюты",
        "Стартовые категории для учета расходов",
        "Режим хранения и резервного копирования"
    ]

    private static let englishCheckpoints: [String] = [
        "Working language and settlement currencies",
        "Initial categories for expense tracking",
        "Storage and backup operating mode"
    ]
}
