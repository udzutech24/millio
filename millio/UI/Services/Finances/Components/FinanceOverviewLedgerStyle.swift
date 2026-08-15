//
//  FinanceOverviewLedgerStyle.swift
//  millio
//
//  Вспомогательные presentation-правила для карточки бухгалтерской раскладки.
//  Держим здесь мелкую UI-логику, чтобы View оставался компактнее и её можно было покрыть тестами.
//

import Foundation
import CoreGraphics

enum FinanceOverviewLedgerStyle {
    struct BalanceComposition: Equatable {
        let debitFraction: Double
        let creditFraction: Double
        let hasData: Bool

        static let empty = BalanceComposition(
            debitFraction: 0,
            creditFraction: 0,
            hasData: false
        )
    }

    static func countsText(groups: Int, accounts: Int) -> String {
        "\(groups) \(L("finances.overview.groups_suffix")) · \(accounts) \(L("finances.overview.accounts_suffix"))"
    }

    static func compactCountsText(groups: Int, accounts: Int) -> String {
        "\(groups) \(L("finances.overview.groups_short")) · \(accounts) \(L("finances.overview.accounts_short"))"
    }

    static func hiddenGroupsText(_ count: Int) -> String {
        "\(L("finances.overview.more_groups")): \(count)"
    }

    static func normalizeAmount(
        _ amount: Double,
        defaultSide: FinanceOverviewLedgerSide,
        epsilon: Double = 0.01
    ) -> (side: FinanceOverviewLedgerSide, amount: Double)? {
        guard abs(amount) > epsilon else { return nil }
        let side: FinanceOverviewLedgerSide = amount < 0 ? .credit : defaultSide
        return (side: side, amount: abs(amount))
    }

    static func barWidth(
        total: Double,
        reference: Double,
        availableWidth: CGFloat,
        minimumWidth: CGFloat
    ) -> CGFloat {
        guard availableWidth > 0 else { return minimumWidth }
        guard reference > 0 else { return minimumWidth }
        let ratio = max(0, min(1, total / reference))
        return max(minimumWidth, availableWidth * ratio)
    }

    /// Ширины двух сегментов ОДНОЙ полосы «активы vs обязательства» (Гейт 5c.7.6.1) — в отличие от
    /// `barWidth` (независимые бары, каждый до `availableWidth`), сегменты здесь обязаны СУММИРОВАТЬСЯ
    /// в `availableWidth`. Если непусты обе стороны — гарантируем минимальную видимость меньшей,
    /// забирая излишек у большей (масштабированием), а не выходя за `availableWidth`.
    static func stackedSegmentWidths(
        debitTotal: Double,
        creditTotal: Double,
        availableWidth: CGFloat,
        minimumSegmentWidth: CGFloat
    ) -> (debit: CGFloat, credit: CGFloat) {
        guard availableWidth > 0 else { return (0, 0) }
        let gross = debitTotal + creditTotal
        guard gross > 0.01, creditTotal > 0.01 else { return (availableWidth, 0) }
        guard debitTotal > 0.01 else { return (0, availableWidth) }

        var debitWidth = availableWidth * CGFloat(debitTotal / gross)
        var creditWidth = availableWidth - debitWidth
        if debitWidth < minimumSegmentWidth {
            debitWidth = minimumSegmentWidth
            creditWidth = availableWidth - debitWidth
        } else if creditWidth < minimumSegmentWidth {
            creditWidth = minimumSegmentWidth
            debitWidth = availableWidth - creditWidth
        }
        return (max(0, debitWidth), max(0, creditWidth))
    }

    /// Доли для donut общего баланса. Использует ту же gross-базу, что stacked bar, но без
    /// минимальной визуальной ширины: круг показывает фактическую пропорцию активов/обязательств.
    static func balanceComposition(
        debitTotal: Double,
        creditTotal: Double,
        epsilon: Double = 0.01
    ) -> BalanceComposition {
        let debit = max(0, debitTotal.isFinite ? debitTotal : 0)
        let credit = max(0, creditTotal.isFinite ? creditTotal : 0)
        let gross = debit + credit
        guard gross > epsilon, gross.isFinite else { return .empty }

        let debitFraction = debit / gross
        return BalanceComposition(
            debitFraction: debitFraction,
            creditFraction: 1 - debitFraction,
            hasData: true
        )
    }
}
