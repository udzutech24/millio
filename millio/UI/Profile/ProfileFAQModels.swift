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
        case .simplifiedChinese:
            return simplifiedChineseSections
        case .german:
            return germanSections
        case .spanish:
            return spanishSections
        case .english, .system, .turkish, .french:
            return englishSections
        }
    }

    private static func effectiveLanguage(from selectedLanguage: Language) -> Language {
        LocalizationSupport.resolvedLanguage(for: selectedLanguage, fallbackLocale: .current)
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
                        "In the app, open Profile and tap the PRO card to check status."
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
                        "millio — это приложение для личных финансов: балансы, Кэшфлоу, конвертер валют, кредиты и инвестиции в одном месте.",
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
                        "В приложении откройте Профиль и нажмите карточку PRO, чтобы проверить статус."
                    ],
                    note: nil
                )
            ]
        )
    ]

    private static let germanSections: [ProfileFAQSection] = [
        ProfileFAQSection(
            id: "general",
            title: "Allgemein",
            items: [
                ProfileFAQItem(
                    id: "what-is-millio",
                    question: "Was ist millio?",
                    answerParagraphs: [
                        "millio ist eine App für persönliche Finanzen: Kontostände, Cashflow, Währungsumrechnung, Kredite und Investitionen – alles an einem Ort.",
                        "Der Fokus liegt auf dem täglichen Einsatz: schnelles Hinzufügen, übersichtliche Dashboards und einfache Bedienung."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "is-my-data-safe",
                    question: "Sind meine Daten sicher?",
                    answerParagraphs: [
                        "Deine lokalen Daten werden auf deinem Gerät gespeichert. Du kannst auch ein Cloud-Backup in den Einstellungen aktivieren.",
                        "Für zusätzlichen Schutz aktiviere die App-Sperre mit PIN und Biometrie."
                    ],
                    note: "Keine App kann 100 % Sicherheit garantieren. Nutze einen sicheren Gerätecode und halte dein System aktuell."
                ),
                ProfileFAQItem(
                    id: "change-language-currency",
                    question: "Wie kann ich die App-Sprache und Hauptwährung ändern?",
                    answerParagraphs: [
                        "Öffne Profil > Allgemein und wähle Sprache oder Währung.",
                        "Die Hauptwährung beeinflusst Standardwerte in der gesamten App."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "backup-restore",
                    question: "Wie funktionieren Backup und Wiederherstellung?",
                    answerParagraphs: [
                        "Öffne Profil > Einstellungen > Backup, um automatische Backups zu aktivieren und den Status einzusehen.",
                        "Beim Wechsel auf ein neues Gerät nutze den Wiederherstellungsvorgang beim ersten Start oder über die entsprechenden Einstellungen."
                    ],
                    note: nil
                )
            ]
        ),
        ProfileFAQSection(
            id: "billing",
            title: "Abonnement",
            items: [
                ProfileFAQItem(
                    id: "what-is-pro",
                    question: "Was ist in PRO enthalten?",
                    answerParagraphs: [
                        "PRO schaltet erweiterte Funktionen frei und hebt die Einschränkungen des kostenlosen Tarifs für ausgewählte Module auf.",
                        "Die aktuellen PRO-Funktionen findest du auf dem Abonnement-Bildschirm."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "manage-subscription",
                    question: "Wie kann ich mein Abonnement verwalten oder kündigen?",
                    answerParagraphs: [
                        "Die Abonnementverwaltung erfolgt über die Apple-ID-Einstellungen auf deinem Gerät.",
                        "In der App öffne Profil und tippe auf die PRO-Karte, um den Status zu prüfen."
                    ],
                    note: nil
                )
            ]
        )
    ]

    private static let spanishSections: [ProfileFAQSection] = [
        ProfileFAQSection(
            id: "general",
            title: "General",
            items: [
                ProfileFAQItem(
                    id: "what-is-millio",
                    question: "¿Qué es millio?",
                    answerParagraphs: [
                        "millio es una aplicación de finanzas personales que te ayuda a gestionar saldos, flujos de caja, conversión de divisas, créditos e inversiones en un solo lugar.",
                        "La app está pensada para el uso diario: añadir transacciones rápidamente, paneles claros y controles sencillos."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "is-my-data-safe",
                    question: "¿Están seguros mis datos?",
                    answerParagraphs: [
                        "Tus datos locales se almacenan en tu dispositivo. También puedes activar la copia de seguridad en la nube desde Ajustes.",
                        "Para mayor protección, usa el bloqueo de la app con PIN y biometría."
                    ],
                    note: "Ninguna app puede garantizar el 100% de seguridad. Usa un código de dispositivo seguro y mantén las actualizaciones del sistema activadas."
                ),
                ProfileFAQItem(
                    id: "change-language-currency",
                    question: "¿Cómo puedo cambiar el idioma y la moneda principal?",
                    answerParagraphs: [
                        "Abre Perfil > General y selecciona Idioma o Moneda.",
                        "La moneda principal afecta a los valores predeterminados de toda la app."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "backup-restore",
                    question: "¿Cómo funcionan la copia de seguridad y la restauración?",
                    answerParagraphs: [
                        "Abre Perfil > Ajustes > Copia de seguridad para activar las copias automáticas y consultar el estado.",
                        "Si cambias de dispositivo, usa el flujo de restauración en el primer inicio o desde los ajustes correspondientes."
                    ],
                    note: nil
                )
            ]
        ),
        ProfileFAQSection(
            id: "billing",
            title: "Suscripción",
            items: [
                ProfileFAQItem(
                    id: "what-is-pro",
                    question: "¿Qué incluye PRO?",
                    answerParagraphs: [
                        "PRO desbloquea funciones avanzadas y elimina los límites del plan gratuito en los módulos seleccionados.",
                        "Puedes consultar los detalles actuales de PRO en la pantalla de suscripción."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "manage-subscription",
                    question: "¿Cómo puedo gestionar o cancelar mi suscripción?",
                    answerParagraphs: [
                        "La gestión de la suscripción se realiza desde los ajustes del Apple ID en tu dispositivo.",
                        "En la app, abre Perfil y toca la tarjeta PRO para ver el estado."
                    ],
                    note: nil
                )
            ]
        )
    ]

    private static let simplifiedChineseSections: [ProfileFAQSection] = [
        ProfileFAQSection(
            id: "general",
            title: "常见问题",
            items: [
                ProfileFAQItem(
                    id: "what-is-millio",
                    question: "millio 是什么？",
                    answerParagraphs: [
                        "millio 是一款个人财务应用，可在一个地方管理余额、现金流、汇率转换、贷款和投资。",
                        "应用强调日常使用效率：快速添加、清晰概览、简单操作。"
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "is-my-data-safe",
                    question: "我的数据安全吗？",
                    answerParagraphs: [
                        "本地数据存储在你的设备上。你也可以在设置中启用云备份。",
                        "如需额外保护，可启用 PIN 码和生物识别的应用锁。"
                    ],
                    note: "任何应用都无法保证 100% 安全。请使用强设备密码，并保持 iOS 为最新版本。"
                ),
                ProfileFAQItem(
                    id: "change-language-currency",
                    question: "如何更改应用语言和基础货币？",
                    answerParagraphs: [
                        "打开“个人资料”>“通用”，然后选择“语言”或“货币”。",
                        "基础货币会影响应用中多个模块的默认值。"
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "backup-restore",
                    question: "备份和恢复如何工作？",
                    answerParagraphs: [
                        "打开“个人资料”>“设置”>“备份”，启用自动备份并查看备份状态。",
                        "更换新设备时，可在首次启动时或在相关设置页面中使用恢复流程。"
                    ],
                    note: nil
                )
            ]
        ),
        ProfileFAQSection(
            id: "billing",
            title: "订阅",
            items: [
                ProfileFAQItem(
                    id: "what-is-pro",
                    question: "PRO 包含什么内容？",
                    answerParagraphs: [
                        "PRO 解锁高级功能，并移除部分模块免费版的限制。",
                        "你可以在订阅页面查看当前 PRO 权益。"
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "manage-subscription",
                    question: "如何管理或取消订阅？",
                    answerParagraphs: [
                        "订阅管理由设备上的 Apple ID 设置负责。",
                        "在应用中打开“个人资料”，点击 PRO 卡片即可查看状态。"
                    ],
                    note: nil
                )
            ]
        )
    ]
}
