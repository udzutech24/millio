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
    let originalBalance: Double

    // Режим ввода количества (для рыночных инвестиций)
    // unitPrice != nil → balance хранит количество, amount = balance × unitPrice
    var unitPrice: Double?
    var unitCurrencyCode: String?

    // Для неактивных строк — всегда итоговая стоимость
    var displayBalance: Double {
        if let p = unitPrice { return balance * p }
        return balance
    }
    var displayCurrency: String { unitCurrencyCode ?? currencyCode }

    // Стабильный ключ для сохранения порядка в UserDefaults
    var stableKey: String {
        let k: String
        switch kind {
        case .card: k = "card"
        case .investment: k = "inv"
        case .credit: k = "credit"
        }
        return "\(k)|\(displayName)|\(currencyCode)"
    }
}

// MARK: - Форматирование ввода с разделителями тысяч

func formatNumberInput(_ raw: String) -> String {
    let noSpaces = raw.replacingOccurrences(of: " ", with: "")
    let decSep = noSpaces.first(where: { $0 == "," || $0 == "." })

    let parts: [Substring]
    if let sep = decSep {
        parts = noSpaces.split(separator: sep, maxSplits: 1, omittingEmptySubsequences: false)
    } else {
        parts = [Substring(noSpaces)]
    }

    let intDigits = (parts.first ?? "").filter { $0.isNumber }
    var intFormatted = ""
    for (i, char) in intDigits.reversed().enumerated() {
        if i > 0 && i % 3 == 0 { intFormatted = " " + intFormatted }
        intFormatted = String(char) + intFormatted
    }

    if parts.count > 1, let sep = decSep {
        let decDigits = parts[1].filter { $0.isNumber }
        return intFormatted + "\(sep)\(decDigits)"
    }
    return intFormatted
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
    let raw = s.hasSuffix(".00") ? String(s.dropLast(3)) : s
    return formatNumberInput(raw)
}

// MARK: - Активная строка (центральная, с редактируемым балансом)

struct AccountAuditActiveRow: View {
    let account: AuditableAccount
    @Binding var balanceText: String
    var isFocused: FocusState<Bool>.Binding
    var confirmFlash: Bool = false

    private var borderColors: [Color] {
        confirmFlash
            ? [AppColors.positiveColor, Color(hex: "00E0B8")]
            : account.accentColors.map { $0.opacity(0.55) }
    }

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

            // Баланс — всегда редактируемый, с форматированием тысяч
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                    if account.unitPrice == nil {
                        Text(auditCurrencySymbol(account.currencyCode))
                            .font(Font.millioTitle)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    TextField("0", text: $balanceText)
                        .font(Font.millioDisplayLarge)
                        .foregroundStyle(AppColors.textPrimary)
                        .keyboardType(.decimalPad)
                        .focused(isFocused)
                        .tint(AppColors.brandPrimary)
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .onChange(of: balanceText) { _, new in
                            let formatted = formatNumberInput(new)
                            if formatted != new { balanceText = formatted }
                        }
                    if account.unitPrice != nil {
                        Text(qaL("finances.quick_audit.units"))
                            .font(Font.millioTitle)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                if let unitPrice = account.unitPrice {
                    let qty = Double(balanceText.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0
                    let total = qty * unitPrice
                    let cur = account.unitCurrencyCode ?? account.currencyCode
                    Text("× \(auditFormattedBalance(unitPrice, currency: cur)) = \(auditFormattedBalance(total, currency: cur))")
                        .font(Font.millioCaption)
                        .foregroundStyle(AppColors.textTertiary)
                        .padding(.top, 2)
                }
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
                                colors: borderColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: confirmFlash ? 2.5 : 1.5
                        )
                )
        )
        .animation(.easeInOut(duration: 0.2), value: confirmFlash)
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

            Text(auditFormattedBalance(account.displayBalance, currency: account.displayCurrency))
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
