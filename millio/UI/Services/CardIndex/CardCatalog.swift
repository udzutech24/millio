//
//  CardCatalog.swift
//  millio
//

import Foundation
import SwiftData

/// Единый read-model для карточных экранов.
/// Хранит общую бизнес-семантику: что считать доступным остатком, долгом и вкладом в net worth.
struct CardSnapshot: Equatable {
    let cardID: String
    let name: String
    let currency: String
    let icon: String
    let cardType: CardType
    let availableAmount: Double
    let debtAmount: Double
    let netWorthAmount: Double
    let isFavorite: Bool
    let prioritySortOrder: Int
    let updatedAt: Date

    var isCreditCard: Bool {
        cardType == .credit
    }
}

enum CardSnapshotFactory {
    static func make(from card: Card) -> CardSnapshot {
        let normalizedAvailable = max(0, card.balance)
        let debt = card.cardType == .credit ? max(0, (card.creditLimit ?? 0) - normalizedAvailable) : 0
        let netWorthAmount = card.includeInTotal
            ? (card.cardType == .credit ? -debt : normalizedAvailable)
            : 0

        return CardSnapshot(
            cardID: card.cardUniqueID,
            name: card.name,
            currency: card.currency,
            icon: card.cardType.icon,
            cardType: card.cardType,
            availableAmount: normalizedAvailable,
            debtAmount: debt,
            netWorthAmount: netWorthAmount,
            isFavorite: card.isFavorite,
            prioritySortOrder: card.priority.sortOrder,
            updatedAt: card.updatedAt
        )
    }
}

enum CardCatalog {
    static func fetchAll(in modelContext: ModelContext, removeDuplicates: Bool = true) -> [Card] {
        let descriptor = FetchDescriptor<Card>()
        let rawCards = (try? modelContext.fetch(descriptor)) ?? []
        let deduped = deduped(rawCards)

        guard removeDuplicates, rawCards.count > deduped.count else {
            return deduped
        }

        let dedupedIDs = Set(deduped.map(\.persistentModelID))
        let duplicatesToDelete = rawCards.filter { !dedupedIDs.contains($0.persistentModelID) }

        guard !duplicatesToDelete.isEmpty else {
            return deduped
        }

        for duplicate in duplicatesToDelete {
            modelContext.delete(duplicate)
        }

        do {
            try modelContext.save()
        } catch {
            AppLogger.log(.error, category: "CardCatalog", "Failed to remove duplicate cards: \(error.localizedDescription)")
        }

        return deduped
    }

    static func deduped(_ cards: [Card]) -> [Card] {
        var latestByID: [String: Card] = [:]
        var cardsWithoutStableID: [Card] = []

        for card in cards {
            let id = card.cardUniqueID
            guard !id.isEmpty else {
                cardsWithoutStableID.append(card)
                continue
            }

            if let existing = latestByID[id] {
                if card.updatedAt >= existing.updatedAt {
                    latestByID[id] = card
                }
            } else {
                latestByID[id] = card
            }
        }

        let deduped = Array(latestByID.values) + cardsWithoutStableID
        return deduped.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    static func sortForDisplay(_ cards: [Card]) -> [Card] {
        cards.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            if lhs.priority.sortOrder != rhs.priority.sortOrder {
                return lhs.priority.sortOrder < rhs.priority.sortOrder
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
