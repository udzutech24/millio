import Foundation

enum ConverterL10n {
    static var sharePromoBrand: String { "millio" }
    static var locale: Locale { AppLocalization.currentAppLocale }
    static var decimalSeparator: String { locale.decimalSeparator ?? "," }
    private static let shareUpdatedPrefixValues: [String: String] = [
        "en": "Updated",
        "ru": "Обновлено",
        "zh-Hans": "已更新"
    ]

    private static func tr(_ key: String, locale: Locale? = nil, fallback: String? = nil) -> String {
        AppLocalization.string(key, locale: locale ?? self.locale, fallback: fallback)
    }

    private static func formatted(
        _ key: String,
        locale: Locale? = nil,
        fallback: String? = nil,
        _ arguments: CVarArg...
    ) -> String {
        let resolvedLocale = locale ?? self.locale
        let format = tr(key, locale: resolvedLocale, fallback: fallback)
        return String(format: format, locale: resolvedLocale, arguments: arguments)
    }

    private static func localizedValue(
        _ values: [String: String],
        locale: Locale,
        fallback: String
    ) -> String {
        for candidate in AppLocalization.preferredLanguageCandidates(from: locale) {
            if let resolved = values[candidate] {
                return resolved
            }
        }
        return fallback
    }

    static var shareSheetDefaultSubject: String { tr("converter.share.default_subject") }
    static var sharePreviewTitle: String { tr("converter.share.preview_title") }
    static var shareMessagePlaceholder: String { tr("converter.share.message_placeholder") }
    static var sendButton: String { tr("converter.share.send") }
    static var historyTitle: String { tr("converter.share.history_title") }
    static var historyEmpty: String { tr("converter.share.history_empty") }
    static var shareHistoryAccessibility: String { tr("converter.accessibility.share_history") }
    static var removeCurrencyAccessibility: String { tr("converter.accessibility.remove_currency") }
    static var addCurrencyAccessibility: String { tr("converter.accessibility.add_currency") }
    static var shareAccessibility: String { tr("converter.accessibility.share") }
    static var settingsAccessibility: String { tr("converter.accessibility.settings") }
    static var addCurrencyTitle: String { tr("converter.currency.add", fallback: "Add currency") }
    static var replaceCurrencyTitle: String { tr("converter.currency.replace", fallback: "Replace currency") }
    static var addCurrencyPlaceholder: String { tr("converter.currency.add", fallback: "Add currency") }
    static var copyValue: String { tr("converter.currency.copy_value", fallback: "Copy value") }
    static var delete: String { tr("converter.common.delete") }

    static var settingsTitle: String { tr("converter.settings.title") }
    static var settingsDone: String { tr("converter.common.done") }
    static var sectionRate: String { tr("converter.settings.section_rate") }
    static var sectionPrecision: String { tr("converter.settings.section_precision") }
    static var sectionFeel: String { tr("converter.settings.section_feel") }
    static var sectionWidget: String { tr("converter.settings.section_widget") }
    static var rateSource: String { tr("converter.settings.rate_source") }
    static var lastUpdate: String { tr("converter.settings.last_update") }
    static var refreshRates: String { tr("converter.settings.refresh_rates") }
    static var refreshingRates: String { tr("converter.settings.refreshing_rates") }
    static var fractionDigits: String { tr("converter.settings.fraction_digits") }
    static var haptics: String { tr("converter.settings.haptics") }
    static var widgetPreviewTitle: String { tr("converter.settings.widget.preview_title") }
    static var widgetPreviewSubtitle: String { tr("converter.settings.widget.preview_subtitle") }
    static var widgetHowToTitle: String { tr("converter.settings.widget.how_to_title") }
    static var widgetStepOpenJiggle: String { tr("converter.settings.widget.step_open_jiggle") }
    static var widgetStepFindMillio: String { tr("converter.settings.widget.step_find_millio") }
    static var widgetStepAddWidget: String { tr("converter.settings.widget.step_add_widget") }

    static var cancel: String { tr("converter.common.cancel") }
    static var close: String { tr("converter.common.close") }

    static var noInternetError: String { tr("converter.error.no_internet") }
    static var timeoutError: String { tr("converter.error.timeout") }
    static var genericUpdateError: String { tr("converter.error.update_failed") }

    static var currencySearchPlaceholder: String {
        tr("converter.currency.search_placeholder", fallback: "Search by code or name")
    }
    static var favoritesSection: String { tr("converter.currency.favorites", fallback: "Favorites") }
    static var allCurrenciesSection: String { tr("converter.currency.all", fallback: "All currencies") }
    static var primaryCurrencySection: String { tr("converter.currency.primary", fallback: "Primary currency") }

    static var shareFallbackTitle: String { tr("converter.share.fallback_title") }
    static var shareFallbackMessage: String { tr("converter.share.fallback_message") }
    static func sharePromoTitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        tr(
            "converter.share.promo_title",
            locale: locale,
            fallback: "Smarter money decisions, faster"
        )
    }
    static func sharePromoSubtitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        tr(
            "converter.share.promo_subtitle",
            locale: locale,
            fallback: "Built with Millio"
        )
    }
    static func shareUpdatedPrefix(locale: Locale = AppLocalization.currentAppLocale) -> String {
        localizedValue(shareUpdatedPrefixValues, locale: locale, fallback: "Updated")
    }
    static func rateSourceTitle(_ source: RateSource, locale: Locale = AppLocalization.currentAppLocale) -> String {
        tr(
            "converter.rate_source.\(source.rawValue).title",
            locale: locale,
            fallback: source.rawValue.capitalized
        )
    }
    static func rateSourceSubtitle(_ source: RateSource, locale: Locale = AppLocalization.currentAppLocale) -> String {
        tr(
            "converter.rate_source.\(source.rawValue).subtitle",
            locale: locale,
            fallback: ""
        )
    }

    static func shareNote(_ note: String) -> String {
        formatted("converter.share.note_format", fallback: "Note: %@", note)
    }

    static func shareTitle(index: Int) -> String {
        formatted("converter.share.title_format", fallback: "Share %d", index)
    }

    static func serverError(source: String) -> String {
        formatted("converter.error.server", fallback: "Server error from %@", source)
    }

    static func parseError(source: String) -> String {
        formatted("converter.error.parse", fallback: "Could not parse rates from %@", source)
    }

    static func baseSummary(input: String, code: String) -> String {
        formatted("converter.share.base_summary_format", fallback: "Base: %@ %@", input, code)
    }

    static func shareMetaLine(dateString: String, baseSummary: String, locale: Locale) -> String {
        "\(shareUpdatedPrefix(locale: locale)) \(dateString)  •  \(baseSummary)"
    }

    static func shareTimestamp(for date: Date, locale: Locale = AppLocalization.currentAppLocale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "dd MMM • HH:mm"
        return formatter.string(from: date)
    }

    static func decimalNumberString(
        from value: Double,
        maxFractionDigits: Int,
        locale: Locale = AppLocalization.currentAppLocale
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.decimalSeparator = locale.decimalSeparator ?? ","
        return formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.\(maxFractionDigits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
