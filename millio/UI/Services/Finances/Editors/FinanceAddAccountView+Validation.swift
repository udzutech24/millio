import SwiftUI
import SwiftData
import PhotosUI

/// Валидация формы: готовность к сохранению и подсказки «обязательно/рекомендуем».
extension FinanceAddAccountView {
    var isValid: Bool {
        guard requiredHints.isEmpty else { return false }
        if selectedProductOption == .house, isProcessingRealEstatePhotos { return false }

        switch selectedAccountType {
        case .card:
            guard let cardData else { return false }
            if cardData.cardType == .credit {
                guard let limit = cardData.creditLimit, limit > 0 else { return false }
                let last4 = cardData.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                return last4.isEmpty || (last4.count == 4 && last4.allSatisfy(\.isNumber))
            }
            return true
        case .credit:
            return creditData != nil
        case .investment:
            if selectedInvestmentPreset == .deposit {
                return depositData != nil
            }
            return investmentData != nil
        }
    }

    var warningAccentColor: Color {
        Color(red: 1.0, green: 0.37, blue: 0.35)
    }

    var recommendationAccentColor: Color {
        Color(red: 0.18, green: 0.95, blue: 0.45)
    }

    var trimmedAccountName: String {
        accountName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasEnteredPrimaryAmount: Bool {
        switch selectedAccountType {
        case .card:
            guard let cardData else { return false }
            if cardData.cardType == .credit {
                return cardData.creditLimit != nil
            }
            return cardData.balance != 0
        case .credit:
            guard let creditData else { return false }
            return creditData.amount != 0
        case .investment:
            if selectedInvestmentPreset == .deposit {
                return (depositData?.amount ?? 0) != 0
            }
            guard let investmentData else { return false }
            if selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto {
                return (investmentData.marketData?.quantity ?? 0) != 0
            }
            return investmentData.amount != 0
        }
    }

    var requiredHints: [ValidationHint] {
        var hints: [ValidationHint] = []

        if isTickerDrivenName {
                let selectedSymbol = investmentData?.marketData?.symbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if selectedSymbol.isEmpty {
                    let tickerHint = selectedInvestmentCategory == .crypto
                    ? L("finances.add_account.hint.select_coin_or_pair")
                    : L("finances.add_account.hint.select_ticker")
                    hints.append(ValidationHint(text: tickerHint, kind: .required))
                }
            } else if trimmedAccountName.isEmpty {
            hints.append(ValidationHint(text: L("finances.add_account.hint.fill_name"), kind: .required))
        }

        return hints
    }

    var recommendedHints: [ValidationHint] {
        var hints: [ValidationHint] = []
        if !hasEnteredPrimaryAmount {
            let amountHint: String
            switch selectedAccountType {
            case .card:
                amountHint = cardData?.cardType == .credit
                ? L("finances.add_account.hint.recommended_credit_limit")
                : L("finances.add_account.hint.recommended_amount")
            case .credit:
                amountHint = L("finances.add_account.hint.recommended_credit_amount")
            case .investment:
                if selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto {
                    amountHint = L("finances.add_account.hint.recommended_quantity")
                } else {
                    amountHint = L("finances.add_account.hint.recommended_amount")
                }
            }
            hints.append(ValidationHint(text: amountHint, kind: .recommended))
        }
        if targetGroup == nil {
            hints.append(ValidationHint(text: L("finances.add_account.hint.recommended_group"), kind: .recommended))
        }
        if selectedAccountType == .investment,
           selectedInvestmentCategory.isMarketTickerCategory,
           canUseMarketCategory(selectedInvestmentCategory),
           EntitlementPolicy.hasTrackedTickerLimit(isPro: appState.isPro) {
            let remaining = max(0, EntitlementPolicy.freeTrackedTickerLimit - currentTrackedTickerCount)
            if !appState.isPro {
                hints.append(
                    ValidationHint(
                        text: String(
                            format: L("monetization.ticker.limit.remaining_format"),
                            remaining,
                            EntitlementPolicy.freeTrackedTickerLimit
                        ),
                        kind: .recommended
                    )
                )
            }
        }
        return hints
    }

    var validationHints: [ValidationHint] {
        requiredHints + recommendedHints
    }

    func focusNameFieldIfNeeded() {
        guard hasConfirmedProductSelection, !isTickerDrivenName else {
            isNameFieldFocused = false
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            isNameFieldFocused = true
        }
    }
}
