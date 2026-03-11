//
//  FinancesLocalization.swift
//  millio
//

import Foundation

enum FinancesL10n {
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: args)
    }

    static func text(locale: Locale, ru: String, en: String) -> String {
        let languageCode = locale.identifier
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased() ?? ""
        return languageCode == "ru" ? ru : en
    }
}
