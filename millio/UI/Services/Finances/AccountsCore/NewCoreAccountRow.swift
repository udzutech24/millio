import SwiftUI

/// Строка счёта нового ядра event-sourcing в списке групп (Фаза 1a-ui) — рядом со строками
/// старого мира (`FinanceAccountRow`), минимальный, но рабочий стиль на токенах дизайн-системы.
struct NewCoreAccountRow: View {
    let account: Account
    let balance: Decimal
    let isAmountHidden: Bool

    private var amountValue: Double {
        NSDecimalNumber(decimal: balance).doubleValue
    }

    private var amountColor: Color {
        amountValue < 0 ? AppColors.error : AppColors.textPrimary
    }

    private var formattedAmount: String {
        guard !isAmountHidden else {
            let digitCount = String(Int(amountValue.rounded())).count
            return String(repeating: "•", count: max(3, digitCount))
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amountValue)) ?? "0"
    }

    private var currencySymbol: String {
        MonetaCurrency(rawValue: account.currency)?.symbol ?? account.currency
    }

    var body: some View {
        HStack(spacing: AppSpacing.m) {
            AccountIconBadgeView(
                iconName: nil,
                iconColor: nil,
                fallback: account.kind.fallbackIconName,
                size: 36,
                isError: amountValue < 0
            )

            Text(account.name)
                .font(.millioSubheadline)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(formattedAmount)
                    .font(.millioSubheadline)
                    .foregroundStyle(amountColor.opacity(0.92))
                Text(currencySymbol)
                    .font(.millioCallout)
                    .foregroundStyle(amountColor.opacity(0.66))
            }
        }
        .padding(.vertical, AppSpacing.s)
        .contentShape(Rectangle())
    }
}

extension AccountKind {
    /// SF Symbol по умолчанию для новых счетов — до появления кастомных иконок нового ядра
    /// (та же зона ответственности, что `CardType.icon`/`Bank.icon` у старого мира).
    var fallbackIconName: String {
        switch self {
        case .cash: return "banknote.fill"
        case .debitCard: return "creditcard.fill"
        case .bankAccount: return "building.columns.fill"
        case .deposit: return "lock.fill"
        case .loan: return "creditcard.trianglebadge.exclamationmark.fill"
        case .debt: return "person.2.fill"
        case .marketInvestment: return "chart.line.uptrend.xyaxis"
        case .manualAsset: return "house.fill"
        }
    }
}
