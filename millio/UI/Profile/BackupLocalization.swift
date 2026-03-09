//
//  BackupLocalization.swift
//  millio
//

import Foundation

enum BackupL10n {
    static func tr(_ key: String, fallback: String) -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: fallback, comment: "")
    }

    static func format(_ key: String, fallback: String, _ args: CVarArg...) -> String {
        String(format: tr(key, fallback: fallback), locale: Locale.current, arguments: args)
    }
}

