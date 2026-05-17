import SwiftUI

private func qaL(_ key: String) -> String { FinancesL10n.tr(key) }

// MARK: - Модель данных для флоу аудита

struct AuditableAccount: Identifiable {
    enum AccountKind {
        case card(Card)
        case investment(Investment)
        case credit(Credit)
    }

    let id = UUID()
    let kind: AccountKind
    var balance: Double
    let displayName: String
    let iconName: String
    let accentColors: [Color]
    let typeLabel: String
    let typeIcon: String
    let currencyCode: String
}

// MARK: - Хелперы форматирования (используются в обоих компонентах)

func auditCurrencySymbol(_ code: String) -> String {
    switch code {
    case "RUB": return "₽"
    case "USD": return "$"
    case "EUR": return "€"
    case "CNY": return "¥"
    default: return code
    }
}

func auditFormattedBalance(_ value: Double, currency: String) -> String {
    let fmt = NumberFormatter()
    fmt.numberStyle = .decimal
    fmt.maximumFractionDigits = 2
    fmt.minimumFractionDigits = 0
    fmt.groupingSeparator = " "
    let num = fmt.string(from: NSNumber(value: abs(value))) ?? "0"
    let sign = value < 0 ? "−" : ""
    return "\(sign)\(auditCurrencySymbol(currency))\(num)"
}

func auditBalanceForEditing(_ value: Double) -> String {
    guard value != 0 else { return "" }
    let s = String(format: "%.2f", value)
    return s.hasSuffix(".00") ? String(s.dropLast(3)) : s
}

// MARK: - Активная строка (центральная, с редактируемым балансом)

struct AccountAuditActiveRow: View {
    let account: AuditableAccount
    @Binding var balanceText: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            // Тип счёта
            Label(account.typeLabel, systemImage: account.typeIcon)
                .font(Font.millioCaption)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.xs)
                .background(Capsule().fill(Color.white.opacity(0.1)))

            // Иконка + название
            HStack(spacing: AppSpacing.m) {
                Image(systemName: account.iconName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: account.accentColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(account.accentColors.first?.opacity(0.15) ?? Color.clear)
                    )
                Text(account.displayName)
                    .font(Font.millioTitle2)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
            }

            // Баланс — всегда редактируемый
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(auditCurrencySymbol(account.currencyCode))
                    .font(Font.millioTitle)
                    .foregroundStyle(AppColors.textSecondary)
                TextField("0", text: $balanceText)
                    .font(Font.millioDisplayLarge)
                    .foregroundStyle(AppColors.textPrimary)
                    .keyboardType(.decimalPad)
                    .focused(isFocused)
                    .tint(AppColors.brandPrimary)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
        }
        .padding(AppSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.xxl)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: AppSpacing.xxl)
                        .strokeBorder(
                            LinearGradient(
                                colors: account.accentColors.map { $0.opacity(0.55) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        )
    }
}

// MARK: - Неактивная строка (соседний счёт, dimmed)

struct AccountAuditInactiveRow: View {
    let account: AuditableAccount

    var body: some View {
        HStack(spacing: AppSpacing.m) {
            Image(systemName: account.iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: account.accentColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(account.accentColors.first?.opacity(0.1) ?? Color.clear)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(Font.millioBody)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(account.typeLabel)
                    .font(Font.millioCaption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            Text(auditFormattedBalance(account.balance, currency: account.currencyCode))
                .font(Font.millioCalloutSemibold)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.l)
        .padding(.vertical, AppSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.l)
                .fill(Color.white.opacity(0.06))
        )
        .opacity(0.5)
    }
}
