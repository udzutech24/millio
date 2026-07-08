//
//  CashflowUpcomingCard.swift
//  millio
//
//  Компактная карточка «Предстоящие» на главном экране Cashflow (Фаза 0, Шаг 6, план
//  `2026-07-05__cashflow-add-transaction-redesign.md`): ближайшие recurring/разовые плановые
//  операции + будущие проценты по вкладам. Ссылка «Все» открывает уже существующий полный
//  «Планировщик» (`CashflowScheduledTransactionsView`) — management-контур не меняется, только
//  добавляется новая точка входа (§5 плана). Пустой список — карточка не рендерится вовсе,
//  решение принимает вызывающая сторона (`CashflowView`).
//

import SwiftUI

struct CashflowUpcomingCard: View {
    let items: [CashflowUpcomingItem]
    let onShowAll: () -> Void

    private let primaryText = AppColors.textPrimary
    private let secondaryText = Color.white.opacity(0.72)

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            header

            VStack(spacing: AppSpacing.s) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                    row(for: item)
                }
            }
        }
        .padding(AppSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var header: some View {
        HStack {
            Text(L("cashflow.upcoming.section_title"))
                .font(.millioSubheadline)
                .foregroundStyle(primaryText)
            Spacer()
            Button(action: onShowAll) {
                HStack(spacing: AppSpacing.xs) {
                    Text(L("cashflow.upcoming.show_all"))
                    Image(systemName: "chevron.right")
                        .font(.millioCaption2)
                }
                .font(.millioCalloutSemibold)
                .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func row(for item: CashflowUpcomingItem) -> some View {
        HStack(spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(dateText(item.date))
                    .font(.millioCaption2)
                    .foregroundStyle(secondaryText)
                Text(item.title)
                    .font(.millioBodySemibold)
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: AppSpacing.s)

            Text(amountText(item))
                .font(.millioBodySemibold)
                .foregroundStyle(item.kind == .income ? AppColors.positiveColor : AppColors.negativeColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func amountText(_ item: CashflowUpcomingItem) -> String {
        let signed = item.kind == .income ? item.amount : -item.amount
        return "\(cashflowSignedAmountText(signed)) \(cashflowCurrencyCodeLabel(item.currencyCode))"
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }
}
