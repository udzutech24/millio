//
//  FinanceDeleteProductCopy.swift
//  millio
//

import Foundation
import SwiftUI

enum FinanceDeleteProductCopy {
    static func actionTitle(for accountType: FinanceAccountType) -> LocalizedStringResource {
        switch accountType {
        case .investment:
            "finances.dynamics.delete_investment"
        case .card, .credit:
            "finances.dynamics.delete_account"
        }
    }

    static func confirmationTitle(for accountType: FinanceAccountType, name: String) -> String {
        let normalizedName = normalizedProductName(name)

        switch accountType {
        case .investment:
            return FinancesL10n.format("finances.dynamics.delete_investment.confirm.title", normalizedName)
        case .card, .credit:
            return FinancesL10n.format("finances.dynamics.delete_account.confirm.title", normalizedName)
        }
    }

    static func confirmationMessage(for accountType: FinanceAccountType) -> LocalizedStringResource {
        switch accountType {
        case .investment:
            "finances.dynamics.delete_investment.confirm.message"
        case .card, .credit:
            "finances.dynamics.delete_account.confirm.message"
        }
    }

    static func normalizedProductName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
