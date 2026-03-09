//
//  FinanceOverviewLedgerStyle.swift
//  millio
//
//  Вспомогательные presentation-правила для карточки бухгалтерской раскладки.
//  Держим здесь мелкую UI-логику, чтобы View оставался компактнее и её можно было покрыть тестами.
//

import CoreGraphics

enum FinanceOverviewLedgerStyle {
    static func countsText(groups: Int, accounts: Int) -> String {
        "\(groups) групп · \(accounts) счетов"
    }

    static func disclosureText(isExpanded: Bool) -> String {
        isExpanded ? "Свернуть" : "Показать детали"
    }

    static func hiddenGroupsText(_ count: Int) -> String {
        "Еще групп: \(count)"
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
}
