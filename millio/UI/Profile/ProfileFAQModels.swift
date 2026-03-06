//
//  ProfileFAQModels.swift
//  millio
//
//  Created by Codex on 06.03.2026.
//

import Foundation

struct ProfileFAQSection: Identifiable, Hashable {
    let id: String
    let title: String
    let items: [ProfileFAQItem]
}

struct ProfileFAQItem: Identifiable, Hashable {
    let id: String
    let question: String
    let answerParagraphs: [String]
    let note: String?
}

enum ProfileFAQContent {
    // Keep all FAQ text in one place to simplify support updates.
    static func sections(for selectedLanguage: Language) -> [ProfileFAQSection] {
        switch effectiveLanguage(from: selectedLanguage) {
        case .russian:
            return russianSections
        case .english, .system:
            return englishSections
        }
    }

    private static func effectiveLanguage(from selectedLanguage: Language) -> Language {
        if selectedLanguage != .system {
            return selectedLanguage
        }
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return code == "ru" ? .russian : .english
    }

    private static let englishSections: [ProfileFAQSection] = [
        ProfileFAQSection(
            id: "general",
            title: "General",
            items: [
                ProfileFAQItem(
                    id: "what-is-millio",
                    question: "What is millio?",
                    answerParagraphs: [
                        "millio is a personal finance app that helps you manage balances, cashflow, currency conversion, credits, and investments in one place.",
                        "The app focuses on fast daily use: quick add, clear dashboards, and simple controls."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "is-my-data-safe",
                    question: "Is my data safe?",
                    answerParagraphs: [
                        "Your local data is stored on your device. You can also enable cloud backup in Settings.",
                        "For additional protection, use App Lock with PIN and biometrics."
                    ],
                    note: "No app can guarantee 100% security. Use a strong device passcode and keep system updates enabled."
                ),
                ProfileFAQItem(
                    id: "change-language-currency",
                    question: "How can I change app language and primary currency?",
                    answerParagraphs: [
                        "Open Profile > General and select Language or Currency.",
                        "Primary currency affects default values across the app."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "backup-restore",
                    question: "How do backup and restore work?",
                    answerParagraphs: [
                        "Open Profile > Settings > Backup to enable automatic backups and check backup status.",
                        "If you move to a new device, use Restore flow on first launch or from settings-related screens when available."
                    ],
                    note: nil
                )
            ]
        ),
        ProfileFAQSection(
            id: "billing",
            title: "Subscription",
            items: [
                ProfileFAQItem(
                    id: "what-is-pro",
                    question: "What is included in PRO?",
                    answerParagraphs: [
                        "PRO unlocks advanced features and removes free-tier limits for selected modules.",
                        "You can review current PRO details on the subscription screen."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "manage-subscription",
                    question: "How can I manage or cancel my subscription?",
                    answerParagraphs: [
                        "Subscription management is handled by Apple ID settings on your device.",
                        "In the app, open Profile and tap the Premium card to check status."
                    ],
                    note: nil
                )
            ]
        )
    ]

    private static let russianSections: [ProfileFAQSection] = [
        ProfileFAQSection(
            id: "general",
            title: "Общее",
            items: [
                ProfileFAQItem(
                    id: "what-is-millio",
                    question: "Что такое millio?",
                    answerParagraphs: [
                        "millio — это приложение для личных финансов: балансы, cashflow, конвертер валют, кредиты и инвестиции в одном месте.",
                        "Фокус на повседневном использовании: быстрые действия, понятные экраны и минимум лишних шагов."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "is-my-data-safe",
                    question: "Безопасны ли мои данные?",
                    answerParagraphs: [
                        "Локальные данные хранятся на устройстве. Также можно включить облачный бэкап в Настройках.",
                        "Для дополнительной защиты включите блокировку приложения PIN-кодом и биометрией."
                    ],
                    note: "Абсолютной защиты не бывает. Используйте надежный код устройства и своевременно обновляйте iOS."
                ),
                ProfileFAQItem(
                    id: "change-language-currency",
                    question: "Как изменить язык приложения и основную валюту?",
                    answerParagraphs: [
                        "Откройте Профиль > Основные и выберите Язык или Валюту.",
                        "Основная валюта используется как значение по умолчанию в разных модулях."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "backup-restore",
                    question: "Как работают бэкап и восстановление?",
                    answerParagraphs: [
                        "Откройте Профиль > Настройки > Backup, чтобы включить резервное копирование и проверить статус.",
                        "При переходе на новое устройство используйте сценарий восстановления на старте или из соответствующих экранов настроек."
                    ],
                    note: nil
                )
            ]
        ),
        ProfileFAQSection(
            id: "billing",
            title: "Подписка",
            items: [
                ProfileFAQItem(
                    id: "what-is-pro",
                    question: "Что входит в PRO?",
                    answerParagraphs: [
                        "PRO открывает расширенные функции и снимает ограничения бесплатного тарифа в отдельных модулях.",
                        "Актуальный список возможностей смотрите на экране подписки."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "manage-subscription",
                    question: "Как управлять или отменить подписку?",
                    answerParagraphs: [
                        "Управление подпиской выполняется в настройках Apple ID на устройстве.",
                        "В приложении откройте Профиль и нажмите карточку Premium, чтобы проверить статус."
                    ],
                    note: nil
                )
            ]
        )
    ]
}
