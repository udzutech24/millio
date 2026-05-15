//
//  CashflowCategoryIconSuggestionEngine.swift
//  millio
//
//  Created by Codex on 20.03.2026.
//

import Foundation

enum CashflowCategoryIconSuggestionEngine {
    static func suggestedIcons(forExpenseName name: String) -> [String] {
        ExpenseCategoryCatalog.suggestedIcons(for: name)
    }

    static func suggestedIcons(forIncomeName name: String) -> [String] {
        let q = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(incomeDefaultSuggested.prefix(8)) }

        let keywords: [(tokens: [String], icons: [String])] = [
            (["зарплат", "оклад", "salary", "wage", "payroll"], ["💵", "💼", "👔", "📋", "💰"]),
            (["фриланс", "freelance", "подработ", "заказ", "client"], ["🧑‍💻", "💻", "🖥️", "🎨", "💳"]),
            (["бизнес", "business", "выруч", "продаж", "revenue"], ["🏢", "📊", "💹", "🏭", "📈"]),
            (["дивиденд", "dividend", "акци", "stock", "портфел"], ["📈", "💹", "📊", "🏦", "🪙"]),
            (["аренд", "недвижим", "rental", "rent", "property", "квартир"], ["🏠", "🏘️", "🔑", "🏗️", "💰"]),
            (["продаж", "sale", "товар", "маркет", "магазин"], ["🏷️", "🛒", "🛍️", "📦", "🚚"]),
            (["бонус", "bonus", "премия", "award", "reward"], ["🎉", "🥳", "🏆", "🥇", "⭐️"]),
            (["подарок", "gift", "present"], ["🎁", "🎀", "🎉", "✨", "💜"]),
            (["процент", "interest", "вклад", "депозит", "deposit"], ["🏦", "💳", "📈", "🪙", "💹"]),
            (["крипт", "crypto", "bitcoin", "биткоин", "токен", "nft"], ["🪙", "💹", "📈", "🔒", "🌐"]),
            (["инвест", "invest", "фонд", "etf"], ["📈", "📊", "💹", "🏦", "💰"]),
            (["возврат", "refund", "cashback", "кэшбэк", "компенсац"], ["↩️", "🔄", "💳", "💰", "✅"]),
            (["пенси", "pension", "пособ", "соцвыпл"], ["📋", "🏦", "💰", "📝", "🤝"]),
            (["роялти", "royalt", "автор", "лицензи", "patent"], ["📖", "🎵", "✍️", "🎬", "📸"]),
            (["стипенди", "stipend", "grant", "грант", "субсид"], ["📚", "🏛️", "📝", "💰", "🤝"]),
            (["творчеств", "creative", "дизайн", "design", "арт", "art"], ["🎨", "🖌️", "✍️", "📸", "🎬"]),
            (["музык", "music", "аудио", "podcast", "подкаст"], ["🎵", "🎤", "🎧", "🎬", "🎙️"]),
            (["консульт", "consult", "коуч", "coach", "mentor"], ["🤝", "💼", "📋", "💡", "📝"]),
        ]

        var result: [String] = []
        for entry in keywords {
            if entry.tokens.contains(where: { q.contains($0) }) {
                result.append(contentsOf: entry.icons)
            }
        }
        result.append(contentsOf: incomeDefaultSuggested)

        var unique: [String] = []
        for item in result where !unique.contains(item) {
            unique.append(item)
        }
        return Array(unique.prefix(10))
    }

    private static let incomeDefaultSuggested = ["💰", "💵", "💹", "📈", "🏦", "💳", "💼", "🧑‍💻", "🏢", "🧩"]
}
