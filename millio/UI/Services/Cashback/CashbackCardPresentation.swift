//
//  CashbackCardPresentation.swift
//  millio
//
//  Centralized card copy for cashback card selection screens.
//

import Foundation

enum CashbackCardPresentation {
    static func title(for card: Card) -> String {
        card.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? String(localized: "Карта без названия")
            : card.name
    }

    static func pickerSubtitle(for card: Card) -> String {
        var parts: [String] = []

        if card.bank != .other {
            parts.append(card.bank.displayName)
        }

        parts.append(card.cardType.displayName)
        return parts.joined(separator: " • ")
    }

    static func pickerDetail(for card: Card) -> String {
        var parts = [detail(for: card)]

        let maskedNumber = maskedNumberText(for: card)
        if !maskedNumber.isEmpty {
            parts.append(maskedNumber)
        }

        return parts.joined(separator: " • ")
    }

    static func subtitle(for card: Card) -> String {
        var parts: [String] = []

        if card.bank != .other {
            parts.append(card.bank.displayName)
        }

        parts.append(card.cardType.displayName)

        let maskedNumber = maskedNumberText(for: card)
        if !maskedNumber.isEmpty {
            parts.append(maskedNumber)
        }

        return parts.joined(separator: " • ")
    }

    static func detail(for card: Card) -> String {
        var parts = ["Баланс \(amountText(card.balance, currency: card.currency))"]

        if let creditLimit = card.creditLimit, card.cardType == .credit {
            parts.append("Лимит \(amountText(creditLimit, currency: card.currency))")
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
