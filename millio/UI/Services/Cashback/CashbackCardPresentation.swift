//
//  CashbackCardPresentation.swift
//  millio
//
//  Centralized card copy for cashback card selection screens.
//

import Foundation

enum CashbackCardPresentation {
    static func title(for card: Card, locale: Locale = CashbackL10n.locale) -> String {
        card.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CashbackL10n.text("cashback.card.unnamed", locale: locale, fallback: "Untitled card")
            : card.name
    }

    static func pickerSubtitle(for card: Card, locale: Locale = CashbackL10n.locale) -> String {
        var parts: [String] = []

        if card.bank != .other {
            parts.append(card.bank.displayName(for: locale))
        }

        parts.append(card.cardType.displayName(for: locale))
        return parts.joined(separator: " • ")
    }

    static func pickerDetail(for card: Card, locale: Locale = CashbackL10n.locale) -> String {
        var parts = [detail(for: card, locale: locale)]

        let maskedNumber = maskedNumberText(for: card)
        if !maskedNumber.isEmpty {
            parts.append(maskedNumber)
        }

        return parts.joined(separator: " • ")
    }

    static func subtitle(for card: Card, locale: Locale = CashbackL10n.locale) -> String {
        var parts: [String] = []

        if card.bank != .other {
            parts.append(card.bank.displayName(for: locale))
        }

        parts.append(card.cardType.displayName(for: locale))

        let maskedNumber = maskedNumberText(for: card)
        if !maskedNumber.isEmpty {
            parts.append(maskedNumber)
        }

        return parts.joined(separator: " • ")
    }

    static func detail(for card: Card, locale: Locale = CashbackL10n.locale) -> String {
        let balanceTitle = CashbackL10n.text("cashback.card.detail.balance", locale: locale, fallback: "Balance")
        let limitTitle = CashbackL10n.text("cashback.card.detail.limit", locale: locale, fallback: "Limit")
        var parts = ["\(balanceTitle) \(amountText(card.balance, currency: card.currency))"]

        if let creditLimit = card.creditLimit, card.cardType == .credit {
            parts.append("\(limitTitle) \(amountText(creditLimit, currency: card.currency))")
        }

        return parts.joined(separator: " • ")
    }

    static func maskedNumberText(for card: Card) -> String {
        let lastDigits = card.maskedNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lastDigits.isEmpty else { return "" }
        return "•••• \(lastDigits)"
    }

    private static func amountText(_ value: Double, currency: String) -> String {
        "\(FinanceAmountText.decimal(value: value)) \(currency)"
    }
}
