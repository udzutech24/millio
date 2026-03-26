//
//  ProfileBackupStatusFormatter.swift
//  millio
//
//  Created by Codex on 26.03.2026.
//

import Foundation

enum ProfileBackupStatusFormatter {
    static func trailingDateText(for date: Date, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }
}
