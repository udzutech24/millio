import Foundation

enum ConverterL10n {
    static let shareSheetDefaultSubject = String(localized: "converter.share.default_subject")
    static let sharePreviewTitle = String(localized: "converter.share.preview_title")
    static let shareMessagePlaceholder = String(localized: "converter.share.message_placeholder")
    static let sendButton = String(localized: "converter.share.send")
    static let historyTitle = String(localized: "converter.share.history_title")
    static let historyEmpty = String(localized: "converter.share.history_empty")
    static let shareHistoryAccessibility = String(localized: "converter.accessibility.share_history")
    static let removeCurrencyAccessibility = String(localized: "converter.accessibility.remove_currency")
    static let addCurrencyAccessibility = String(localized: "converter.accessibility.add_currency")
    static let shareAccessibility = String(localized: "converter.accessibility.share")
    static let settingsAccessibility = String(localized: "converter.accessibility.settings")

    static let addCurrencyTitle = String(localized: "converter.currency.add")
    static let replaceCurrencyTitle = String(localized: "converter.currency.replace")
    static let addCurrencyPlaceholder = String(localized: "converter.currency.add")
    static let copyValue = String(localized: "converter.currency.copy_value")
    static let delete = String(localized: "converter.common.delete")

    static let settingsTitle = String(localized: "converter.settings.title")
    static let settingsDone = String(localized: "converter.common.done")
    static let sectionRate = String(localized: "converter.settings.section_rate")
    static let sectionPrecision = String(localized: "converter.settings.section_precision")
    static let sectionFeel = String(localized: "converter.settings.section_feel")
    static let rateSource = String(localized: "converter.settings.rate_source")
    static let lastUpdate = String(localized: "converter.settings.last_update")
    static let refreshRates = String(localized: "converter.settings.refresh_rates")
    static let refreshingRates = String(localized: "converter.settings.refreshing_rates")
    static let fractionDigits = String(localized: "converter.settings.fraction_digits")
    static let haptics = String(localized: "converter.settings.haptics")

    static let cancel = String(localized: "converter.common.cancel")
    static let close = String(localized: "converter.common.close")

    static let sharePromoTitle = String(localized: "converter.share.promo_title")
    static let sharePromoSubtitle = String(localized: "converter.share.promo_subtitle")
    static let sharePromoBrand = String(localized: "converter.share.promo_brand")

    static let noInternetError = String(localized: "converter.error.no_internet")
    static let timeoutError = String(localized: "converter.error.timeout")
    static let genericUpdateError = String(localized: "converter.error.update_failed")

    static let currencySearchPlaceholder = String(localized: "converter.currency.search_placeholder")
    static let favoritesSection = String(localized: "converter.currency.favorites")
    static let allCurrenciesSection = String(localized: "converter.currency.all")
    static let primaryCurrencySection = String(localized: "converter.currency.primary")

    static let shareFallbackTitle = String(localized: "converter.share.fallback_title")
    static let shareFallbackMessage = String(localized: "converter.share.fallback_message")

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
}
