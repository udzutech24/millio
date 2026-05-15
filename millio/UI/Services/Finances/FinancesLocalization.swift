//
//  FinancesLocalization.swift
//  millio
//

import Foundation

enum FinancesL10n {
    static func tr(_ key: String) -> String {
        AppLocalization.string(key, locale: AppLocalization.currentAppLocale)
    }

    static func tr(_ key: String, locale: Locale) -> String {
        AppLocalization.string(key, locale: locale)
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        let locale = AppLocalization.currentAppLocale
        return String(format: tr(key), locale: locale, arguments: args)
    }

    static func format(_ key: String, locale: Locale, _ args: CVarArg...) -> String {
        String(format: tr(key, locale: locale), locale: locale, arguments: args)
    }

}
