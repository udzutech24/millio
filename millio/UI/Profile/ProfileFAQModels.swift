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
                ),
                ProfileFAQItem(
                    id: "home-screen-widget",
                    question: "Is there a home screen widget?",
                    answerParagraphs: [
                        "Yes. millio includes a free home screen widget showing live exchange rates.",
                        "Add it via the iOS widget gallery: long-press on the home screen, tap +, and search for millio."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "custom-icons",
                    question: "Can I change the app icon?",
                    answerParagraphs: [
                        "Yes. millio offers a selection of custom app icons.",
                        "Open Profile > Appearance to choose your preferred look."
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
                        "PRO includes: AI import from bank screenshots, Finance & Dynamics charts, unlimited cashback categories, and unlimited financial products.",
                        "To subscribe or check your plan status, open Profile and tap the PRO card."
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
                ),
                ProfileFAQItem(
                    id: "home-screen-widget",
                    question: "Есть ли виджет на экран «Домой»?",
                    answerParagraphs: [
                        "Да. millio включает бесплатный виджет с живыми курсами валют для экрана «Домой».",
                        "Добавьте через галерею виджетов iOS: удерживайте экран «Домой», нажмите +, найдите millio."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "custom-icons",
                    question: "Можно ли сменить иконку приложения?",
                    answerParagraphs: [
                        "Да. millio предлагает несколько вариантов иконок на выбор.",
                        "Откройте Профиль > Внешний вид и выберите подходящий стиль."
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
                        "PRO включает: AI-импорт транзакций из скриншотов банка, графики Finances и Dynamics, неограниченные категории кэшбэка и финансовые продукты.",
                        "Чтобы оформить подписку или проверить статус, откройте Профиль и нажмите карточку PRO."
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
                ),
                ProfileFAQItem(
                    id: "home-screen-widget",
                    question: "Gibt es ein Home-Screen-Widget?",
                    answerParagraphs: [
                        "Ja. millio enthält ein kostenloses Widget mit Live-Wechselkursen für den Home-Screen.",
                        "Füge es über die iOS-Widget-Galerie hinzu: Home-Screen gedrückt halten, + tippen, millio suchen."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "custom-icons",
                    question: "Kann ich das App-Symbol ändern?",
                    answerParagraphs: [
                        "Ja. millio bietet mehrere App-Icons zur Auswahl.",
                        "Öffne Profil > Darstellung und wähle deinen bevorzugten Stil."
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
                        "PRO umfasst: KI-Import aus Bank-Screenshots, Finance- & Dynamics-Diagramme, unbegrenzte Cashback-Kategorien und unbegrenzte Finanzprodukte.",
                        "Zum Abonnieren oder Prüfen deines Status öffne Profil und tippe auf die PRO-Karte."
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
                ),
                ProfileFAQItem(
                    id: "home-screen-widget",
                    question: "¿Hay un widget para la pantalla de inicio?",
                    answerParagraphs: [
                        "Sí. millio incluye un widget gratuito con tipos de cambio en tiempo real para la pantalla de inicio.",
                        "Añádelo desde la galería de widgets de iOS: mantén pulsada la pantalla de inicio, toca + y busca millio."
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "custom-icons",
                    question: "¿Puedo cambiar el icono de la app?",
                    answerParagraphs: [
                        "Sí. millio ofrece varios iconos de app para elegir.",
                        "Abre Perfil > Apariencia y selecciona el estilo que prefieras."
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
                        "PRO incluye: importación con IA desde capturas de pantalla bancarias, gráficos Finances y Dynamics, categorías de cashback ilimitadas y productos financieros ilimitados.",
                        "Para suscribirte o revisar tu plan, abre Perfil y toca la tarjeta PRO."
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
                        "打开「个人资料」>「通用」，然后选择「语言」或「货币」。",
                        "基础货币会影响应用中多个模块的默认值。"
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: 「backup-restore」,
                    question: 「备份和恢复如何工作？」,
                    answerParagraphs: [
                        「打开」个人资料」>」设置」>」备份」，启用自动备份并查看备份状态。」,
                        「更换新设备时，可在首次启动时或在相关设置页面中使用恢复流程。」
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: 「home-screen-widget」,
                    question: 「有主屏幕小组件吗？」,
                    answerParagraphs: [
                        「有。millio 提供免费的实时汇率主屏幕小组件。」,
                        「通过 iOS 小组件库添加：长按主屏幕，点击 +，搜索 millio。」
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: 「custom-icons」,
                    question: 「可以更换应用图标吗？」,
                    answerParagraphs: [
                        「可以。millio 提供多款应用图标供选择。」,
                        「打开」个人资料」>」外观」，选择你喜欢的风格。」
                    ],
                    note: nil
                )
            ]
        ),
        ProfileFAQSection(
            id: 「billing」,
            title: 「订阅」,
            items: [
                ProfileFAQItem(
                    id: 「what-is-pro」,
                    question: 「PRO 包含什么内容？」,
                    answerParagraphs: [
                        「PRO 包含：AI 银行截图导入、Finances 与 Dynamics 图表、无限返现类别及无限金融产品。」,
                        「如需订阅或查看计划状态，打开」个人资料」并点击 PRO 卡片。」
                    ],
                    note: nil
                ),
                ProfileFAQItem(
                    id: "manage-subscription",
                    question: "如何管理或取消订阅？",
                    answerParagraphs: [
                        "订阅管理由设备上的 Apple ID 设置负责。",
                        "在应用中打开「个人资料」，点击 PRO 卡片即可查看状态。"
                    ],
                    note: nil
                )
            ]
        )
    ]
}
