import Foundation

enum ConverterL10n {
    static var sharePromoBrand: String { "millio" }

    static var shareSheetDefaultSubject: String { String(localized: "converter.share.default_subject") }
    static var sharePreviewTitle: String { String(localized: "converter.share.preview_title") }
    static var shareMessagePlaceholder: String { String(localized: "converter.share.message_placeholder") }
    static var sendButton: String { String(localized: "converter.share.send") }
    static var historyTitle: String { String(localized: "converter.share.history_title") }
    static var historyEmpty: String { String(localized: "converter.share.history_empty") }
    static var shareHistoryAccessibility: String { String(localized: "converter.accessibility.share_history") }
    static var removeCurrencyAccessibility: String { String(localized: "converter.accessibility.remove_currency") }
    static var addCurrencyAccessibility: String { String(localized: "converter.accessibility.add_currency") }
    static var shareAccessibility: String { String(localized: "converter.accessibility.share") }
    static var settingsAccessibility: String { String(localized: "converter.accessibility.settings") }

    static var addCurrencyTitle: String { String(localized: "converter.currency.add") }
    static var replaceCurrencyTitle: String { String(localized: "converter.currency.replace") }
    static var addCurrencyPlaceholder: String { String(localized: "converter.currency.add") }
    static var copyValue: String { String(localized: "converter.currency.copy_value") }
    static var delete: String { String(localized: "converter.common.delete") }

    static var settingsTitle: String { String(localized: "converter.settings.title") }
    static var settingsDone: String { String(localized: "converter.common.done") }
    static var sectionRate: String { String(localized: "converter.settings.section_rate") }
    static var sectionPrecision: String { String(localized: "converter.settings.section_precision") }
    static var sectionFeel: String { String(localized: "converter.settings.section_feel") }
    static var sectionWidget: String { String(localized: "converter.settings.section_widget") }
    static var rateSource: String { String(localized: "converter.settings.rate_source") }
    static var lastUpdate: String { String(localized: "converter.settings.last_update") }
    static var refreshRates: String { String(localized: "converter.settings.refresh_rates") }
    static var refreshingRates: String { String(localized: "converter.settings.refreshing_rates") }
    static var fractionDigits: String { String(localized: "converter.settings.fraction_digits") }
    static var haptics: String { String(localized: "converter.settings.haptics") }
    static var widgetPreviewTitle: String { String(localized: "converter.settings.widget.preview_title") }
    static var widgetPreviewSubtitle: String { String(localized: "converter.settings.widget.preview_subtitle") }
    static var widgetHowToTitle: String { String(localized: "converter.settings.widget.how_to_title") }
    static var widgetStepOpenJiggle: String { String(localized: "converter.settings.widget.step_open_jiggle") }
    static var widgetStepFindMillio: String { String(localized: "converter.settings.widget.step_find_millio") }
    static var widgetStepAddWidget: String { String(localized: "converter.settings.widget.step_add_widget") }

    static var cancel: String { String(localized: "converter.common.cancel") }
    static var close: String { String(localized: "converter.common.close") }

    static var noInternetError: String { String(localized: "converter.error.no_internet") }
    static var timeoutError: String { String(localized: "converter.error.timeout") }
    static var genericUpdateError: String { String(localized: "converter.error.update_failed") }

    static var currencySearchPlaceholder: String { String(localized: "converter.currency.search_placeholder") }
    static var favoritesSection: String { String(localized: "converter.currency.favorites") }
    static var allCurrenciesSection: String { String(localized: "converter.currency.all") }
    static var primaryCurrencySection: String { String(localized: "converter.currency.primary") }

    static var shareFallbackTitle: String { String(localized: "converter.share.fallback_title") }
    static var shareFallbackMessage: String { String(localized: "converter.share.fallback_message") }

    static func shareNote(_ note: String) -> String {
        String(format: String(localized: "converter.share.note_format"), note)
    }

    static func shareTitle(index: Int) -> String {
        String(format: String(localized: "converter.share.title_format"), index)
    }

    static func serverError(source: String) -> String {
        String(format: String(localized: "converter.error.server"), source)
    }

    static func parseError(source: String) -> String {
        String(format: String(localized: "converter.error.parse"), source)
    }

    static func baseSummary(input: String, code: String) -> String {
        String(format: String(localized: "converter.share.base_summary_format"), input, code)
    }

    static func sharePromoSubtitle(locale: Locale) -> String {
        text(
            locale: locale,
            ru: "Управляйте всеми финансами в одном месте",
            en: "Manage all your finances in one place"
        )
    }

    static func shareMetaLine(dateString: String, baseSummary: String, locale: Locale) -> String {
        let separator = text(locale: locale, ru: "Обновлено", en: "Updated")
        return "\(separator) \(dateString)  •  \(baseSummary)"
    }

    static func text(locale: Locale, ru: String, en: String) -> String {
        let languageCode = locale.identifier
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased() ?? ""
        return languageCode == "ru" ? ru : en
    }
}
