import SwiftUI
import SwiftData

/// История событий счёта.
extension AccountDetailView {
    // MARK: - History

    /// `sortedEvents` — фильтрация + сортировка всей истории счёта; берём срез ОДИН раз на
    /// пересчёт секции, а не по разу на заголовок, счётчик, список и разделители.
    var historySection: some View {
        let events = sortedEvents
        return AccountDetailPlaqueSection(
            title: L("accounts_core.detail.history_title"),
            caption: events.isEmpty ? nil : L("cashflow.month_workspace.transaction_count \(events.count)")
        ) {
            if events.isEmpty {
                Text(L("accounts_core.detail.no_events"))
                    .font(.millioCalloutRegular)
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(events, id: \.id) { event in
                        eventRow(event)
                        if event.id != events.last?.id {
                            Divider().background(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
    }

    func eventRow(_ event: AccountEvent) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(eventTypeLabel(event.type))
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textPrimary)
                Text(event.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.textTertiary)
                if let note = event.note, !note.isEmpty {
                    Text(note)
                        .font(.millioCaptionRegular)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            Spacer()
            if (event.type == .buy || event.type == .sell || event.type == .adjustment),
               let quantity = event.quantity {
                // buy/sell не имеют `amount` (движок E считает по quantity×price, не по денежной сумме) —
                // показываем количество и цену отдельными строками, а не одной «49 × 769,35».
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text(formattedAmount(quantity))
                        .font(.millioBodySemibold)
                        .foregroundStyle(AppColors.textPrimary)
                    if let unitPrice = event.unitPrice {
                        Text(String(format: L("accounts_core.detail.market.event_price_format"), formattedAmount(unitPrice)))
                            .font(.millioCaptionRegular)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            } else if let amount = event.amount {
                Text(signedAmountText(amount, type: event.type))
                    .font(.millioBodySemibold)
                    .foregroundStyle(amount < 0 ? AppColors.error : AppColors.textPrimary)
            }
        }
        .padding(.vertical, AppSpacing.s)
    }

    func eventTypeLabel(_ type: AccountEventType) -> String {
        switch type {
        case .openingBalance: return L("accounts_core.detail.event.opening_balance")
        case .income: return L("accounts_core.detail.event.income")
        case .expense: return L("accounts_core.detail.event.expense")
        case .transferOut: return L("accounts_core.detail.event.transfer_out")
        case .transferIn: return L("accounts_core.detail.event.transfer_in")
        case .adjustment: return L("accounts_core.detail.event.adjustment")
        case .interest: return L("accounts_core.detail.event.interest")
        case .fee: return L("accounts_core.detail.event.fee")
        case .creditCardPurchase: return L("accounts_core.detail.event.expense")
        case .creditCardRefund, .creditCardRepayment: return L("accounts_core.detail.event.income")
        case .creditCardFee, .creditCardInterest: return L("accounts_core.detail.event.fee")
        case .extraPayment: return L("accounts_core.detail.event.extra_payment")
        case .buy: return L("accounts_core.detail.event.buy")
        case .sell: return L("accounts_core.detail.event.sell")
        case .dividend: return L("accounts_core.detail.event.dividend")
        case .revaluation: return L("accounts_core.detail.event.revaluation")
        default: return type.rawValue
        }
    }
}
