//
//  FinanceAddAccountPreselection.swift
//  millio
//

import Foundation

enum FinanceAddAccountPreselection {
    static func productTitle(for accountType: FinanceAccountType) -> String {
        productTitle(for: accountType, locale: AppLocalization.currentAppLocale)
    }

    static func productTitle(for accountType: FinanceAccountType, locale: Locale) -> String {
        switch accountType {
        case .card:
            return FinanceAccountType.card.displayName(for: locale)
        case .credit:
            return FinanceAccountType.credit.displayName(for: locale)
        case .investment:
            return FinanceAccountType.investment.displayName(for: locale)
        }
    }
}
