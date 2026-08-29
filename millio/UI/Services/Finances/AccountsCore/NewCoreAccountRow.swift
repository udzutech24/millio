import SwiftUI

/// Адаптер core-счёта к единой строке `AccountRowView`: собирает презентацию и передаёт действия.
/// Собственной вёрстки здесь НЕТ — иначе визуал снова разъедется между мирами счетов.
///
/// `appearance` приходит ГОТОВЫМ значением из ViewModel (один fetch на список). Собственного
/// запроса к `AccountAppearanceStore` здесь нет и быть не должно: `body` вызывается на каждый кадр.
struct NewCoreAccountRow: View {
    let account: Account
    let balance: Decimal
    let isAmountHidden: Bool
    /// nil = оформления нет → детерминированный дефолт (монограмма по имени + цвет по `Account.id`).
    var appearance: AccountAppearanceSnapshot?
    /// Архивный счёт: тот же макет, приглушённый.
    var isDimmed: Bool = false
    /// nil = строка read-only (редактор группы, архив): контекстное меню не вешается.
    var onToggleFavorite: (() -> Void)?
    /// Применение выбранного оформления. nil = редактирование из этого места недоступно.
    var onSaveAppearance: ((_ iconName: String?, _ tintHex: String?) -> Void)?

    @State private var isEditingAppearance = false
    @State private var draftIconName: String?
    @State private var draftTintHex: String?

    private var amountValue: Double {
        NSDecimalNumber(decimal: balance).doubleValue
    }

    private var presentation: AccountRowPresentation {
        AccountRowPresentation.make(
            key: account.id.uuidString,
            name: account.name,
            appearance: appearance,
            fallbackIconName: account.kind.fallbackIconName,
            amountText: AccountRowAmountFormatter.text(amountValue, isHidden: isAmountHidden),
            currencySymbol: MonetaCurrency(rawValue: account.currency)?.symbol ?? account.currency,
            isNegative: amountValue < 0
        )
    }

    private var editAppearanceAction: (() -> Void)? {
        guard onSaveAppearance != nil else { return nil }
        return { startEditingAppearance() }
    }

    var body: some View {
        AccountRowView(
            presentation: presentation,
            isDimmed: isDimmed,
            onToggleFavorite: onToggleFavorite,
            onEditAppearance: editAppearanceAction
        )
        .sheet(isPresented: $isEditingAppearance) {
            AccountIconPickerSheet(iconName: $draftIconName, iconColor: $draftTintHex)
                .onDisappear {
                    // Сохраняем на закрытии листа: у `AccountIconPickerSheet` нет колбэка «готово»,
                    // он работает через биндинги, а «Отмена» их не откатывает (поведение, общее
                    // с легаси-формами счёта — второго контракта не заводим).
                    onSaveAppearance?(draftIconName, draftTintHex)
                }
        }
    }

    private func startEditingAppearance() {
        // В пикер отдаём то, что пользователь выбрал ЯВНО, а не вычисленный дефолт: иначе первый же
        // вход в редактор «застолбил» бы авто-цвет как ручной выбор.
        draftIconName = appearance?.iconName
        draftTintHex = appearance?.tintHex
        isEditingAppearance = true
    }
}

/// Единый формат суммы в строке счёта: разряды пробелом, скрытие — точками по числу разрядов.
enum AccountRowAmountFormatter {
    static func text(_ amount: Double, isHidden: Bool, maximumFractionDigits: Int = 0) -> String {
        guard !isHidden else {
            let digitCount = String(Int(amount.rounded())).count
            return String(repeating: "•", count: max(3, digitCount))
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }
}

extension AccountKind {
    /// SF Symbol по умолчанию для новых счетов — используется, когда имя счёта пустое и монограмму
    /// собрать не из чего (та же зона ответственности, что `CardType.icon`/`Bank.icon` у старого мира).
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
