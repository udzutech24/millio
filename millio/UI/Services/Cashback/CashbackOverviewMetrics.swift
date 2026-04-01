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
    private let featuredCategoryRaw: String?
    private let featuredCustomCategoryName: String?
    let featuredCashbackKey: String?

    var featuredCategoryName: String? {
        guard let featuredCategoryRaw else { return nil }

        if let systemCategory = CashbackCategory(rawValue: featuredCategoryRaw) {
            return systemCategory.displayName
        }

        if featuredCategoryRaw.hasPrefix(Cashback.customCategoryPrefix),
           let featuredCustomCategoryName,
           !featuredCustomCategoryName.isEmpty {
            return featuredCustomCategoryName
        }

        return CashbackCategory.other.displayName
    }

    static let empty = CashbackOverviewMetrics(
        categoryCount: 0,
        linkedCardCount: 0,
        averagePercentage: 0,
        highestPercentage: 0,
        featuredCategoryRaw: nil,
        featuredCustomCategoryName: nil,
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
            let lhsName = localizedCategoryName(for: lhs)
            let rhsName = localizedCategoryName(for: rhs)

            if lhs.percentage != rhs.percentage {
                return lhs.percentage < rhs.percentage
            }

            let lhsCards = lhs.cardIDs.count
            let rhsCards = rhs.cardIDs.count
            if lhsCards != rhsCards {
                return lhsCards < rhsCards
            }

            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedDescending
        }

        return CashbackOverviewMetrics(
            categoryCount: categoryCount,
            linkedCardCount: linkedCardCount,
            averagePercentage: averagePercentage,
            highestPercentage: highestPercentage,
            featuredCategoryRaw: featuredCashback?.categoryRaw,
            featuredCustomCategoryName: featuredCashback?.isCustomCategory == true ? featuredCashback?.name : nil,
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

    private static func localizedCategoryName(for cashback: Cashback) -> String {
        if let systemCategory = CashbackCategory(rawValue: cashback.categoryRaw) {
            return systemCategory.displayName
        }

        if cashback.isCustomCategory, !cashback.name.isEmpty {
            return cashback.name
        }

        return CashbackCategory.other.displayName
    }
}
