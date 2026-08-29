import SwiftUI

/// Единственный компонент строки счёта нового ядра: список групп, «Без группы», редактор группы и
/// архив рисуют её, а не свою вёрстку — иначе визуал разъезжается по четырём местам.
///
/// `appearance` приходит ГОТОВЫМ значением из ViewModel (один fetch на список). Собственного
/// запроса к `AccountAppearanceStore` здесь нет и быть не должно: `body` вызывается на каждый кадр.
struct NewCoreAccountRow: View {
    let account: Account
    let balance: Decimal
    let isAmountHidden: Bool
    /// nil = оформления нет → дефолтный вид (монограмма по имени), как до V11.
    var appearance: AccountAppearanceSnapshot?
    /// Архивный счёт: тот же макет, приглушённый — отдельной вёрстки для архива не заводим.
    var isDimmed: Bool = false
    /// nil = строка read-only (редактор группы, архив): контекстное меню «избранное» не показываем.
    var onToggleFavorite: (() -> Void)?

    /// Размер бейджа строки списка. Hero-карточка деталки (Ф3) свой размер задаёт сама.
    private static let badgeSize: CGFloat = 36
    private static let dimmedOpacity: Double = 0.55

    private var details: CashflowAccountPickerDetails {
        CashflowAccountPickerDetailsFactory.details(
            for: account,
            appearance: appearance,
            balance: balance
        )
    }

    private var isFavorite: Bool { appearance?.isFavorite == true }

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
        // Меню вешаем только там, где действие есть: пустой `contextMenu` даёт долгое нажатие
        // без единого пункта — визуальный «мёртвый» отклик в редакторе группы и архиве.
        if let onToggleFavorite {
            rowContent.contextMenu { favoriteButton(onToggleFavorite) }
        } else {
            rowContent
        }
    }

    private func favoriteButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isFavorite {
                Label(L("finances.account.favorite.remove"), systemImage: "star.slash")
            } else {
                Label(L("finances.account.favorite.add"), systemImage: "star")
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: AppSpacing.m) {
            AccountIconBadgeView(
                iconName: details.iconName,
                iconColor: details.iconColorHex,
                fallback: details.fallbackIconName,
                size: Self.badgeSize,
                isError: amountValue < 0
            )

            HStack(spacing: AppSpacing.xs) {
                Text(account.name)
                    .font(.millioSubheadline)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.millioCaption2)
                        .foregroundStyle(AppColors.warning)
                        .accessibilityLabel(L("finances.account.favorite.badge"))
                }
            }
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
        // Архив отличается только приглушением: saturation(0) гасит цвет оформления, чтобы
        // закрытый счёт не выглядел активнее рабочих.
        .saturation(isDimmed ? 0 : 1)
        .opacity(isDimmed ? Self.dimmedOpacity : 1)
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
