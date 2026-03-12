//
//  CashbackOverviewMetrics.swift
//  millio
//
//  Created by Codex on 12.03.2026.
//

import Foundation

/// Summary-модель для верхнего блока экрана кешбэка.
/// Держит вычисления вне SwiftUI-вью, чтобы layout оставался простым,
/// а поведение можно было проверить юнит-тестами.
struct CashbackOverviewMetrics: Equatable {
    let categoryCount: Int
    let linkedCardCount: Int
    let averagePercentage: Double
    let highestPercentage: Double
    let featuredCategoryName: String?
    let featuredCashbackKey: String?

    static let empty = CashbackOverviewMetrics(
        categoryCount: 0,
        linkedCardCount: 0,
        averagePercentage: 0,
        highestPercentage: 0,
        featuredCategoryName: nil,
        featuredCashbackKey: nil
    )

    static func make(from cashbacks: [Cashback]) -> CashbackOverviewMetrics {
        guard !cashbacks.isEmpty else { return .empty }

        let categoryCount = cashbacks.count
        let linkedCardCount = Set(
            cashbacks
                .flatMap(\.cardIDs)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ).count

        let highestPercentage = cashbacks.map(\.percentage).max() ?? 0
        let averagePercentage = cashbacks.map(\.percentage).reduce(0, +) / Double(categoryCount)

        let featuredCashback = cashbacks.max { lhs, rhs in
            if lhs.percentage != rhs.percentage {
                return lhs.percentage < rhs.percentage
            }

            let lhsCards = lhs.cardIDs.count
            let rhsCards = rhs.cardIDs.count
            if lhsCards != rhsCards {
                return lhsCards < rhsCards
            }

            return lhs.displayCategoryName.localizedCaseInsensitiveCompare(rhs.displayCategoryName) == .orderedDescending
        }

        return CashbackOverviewMetrics(
            categoryCount: categoryCount,
            linkedCardCount: linkedCardCount,
            averagePercentage: averagePercentage,
            highestPercentage: highestPercentage,
            featuredCategoryName: featuredCashback?.displayCategoryName,
            featuredCashbackKey: featuredCashback.map(stableKey(for:))
        )
    }

    var formattedAveragePercentage: String {
        Self.percentageString(for: averagePercentage)
    }

    var formattedHighestPercentage: String {
        Self.percentageString(for: highestPercentage)
    }

    private static func percentageString(for value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return "\(formatter.string(from: NSNumber(value: value)) ?? "0")%"
    }

    static func stableKey(for cashback: Cashback) -> String {
        let cardsKey = cashback.cardIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: ",")
        return "\(cashback.monthKey)|\(cashback.categoryRaw)|\(cardsKey)"
    }
}
