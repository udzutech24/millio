import SwiftUI

// MARK: - Overflow fade

private struct OverflowFadeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct AvailableFadeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Однострочный текст, растворяющийся к правому краю вместо многоточия.
/// Живёт рядом со строкой счёта: её же используют подстроки легаси-строк (`FinanceRows`).
struct OverflowFadeText: View {
    let text: String
    let font: Font
    let color: Color
    let fadeStart: CGFloat
    let fadeEnd: CGFloat

    @State private var intrinsicWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0

    private var shouldFade: Bool {
        intrinsicWidth > availableWidth + 1
    }

    var body: some View {
        displayedText
            .mask(
                Group {
                    if shouldFade {
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: fadeStart),
                                .init(color: .clear, location: fadeEnd)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color.white
                    }
                }
            )
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: AvailableFadeWidthKey.self, value: proxy.size.width)
                }
            )
            .background(intrinsicWidthProbe)
            .onPreferenceChange(AvailableFadeWidthKey.self) { availableWidth = $0 }
            .onPreferenceChange(OverflowFadeWidthKey.self) { intrinsicWidth = $0 }
    }

    private var displayedText: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .clipped()
    }

    private var intrinsicWidthProbe: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .hidden()
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: OverflowFadeWidthKey.self, value: proxy.size.width)
                }
            )
    }
}

// MARK: - Presentation

/// Готовые к отрисовке данные строки счёта — общие для обоих миров (core `Account` и легаси
/// `Card`/`Credit`/`Investment`). Сумма приходит УЖЕ отформатированной: у миров разная точность
/// (0 знаков в списке, 2 у рыночной инвестиции) и разные источники баланса, и второе определение
/// форматирования внутри строки нам не нужно.
struct AccountRowPresentation: Equatable {
    let name: String
    /// SF Symbol или монограмма вида `monogram:СБ` (см. `AccountIconSet`).
    let iconName: String?
    let iconColorHex: String?
    let fallbackIconName: String
    let amountText: String
    let currencySymbol: String
    /// Долг/обязательство: сумма и бейдж красятся в `AppColors.error`.
    let isNegative: Bool
    let isFavorite: Bool

    init(
        name: String,
        iconName: String?,
        iconColorHex: String?,
        fallbackIconName: String,
        amountText: String,
        currencySymbol: String,
        isNegative: Bool = false,
        isFavorite: Bool = false
    ) {
        self.name = name
        self.iconName = iconName
        self.iconColorHex = iconColorHex
        self.fallbackIconName = fallbackIconName
        self.amountText = amountText
        self.currencySymbol = currencySymbol
        self.isNegative = isNegative
        self.isFavorite = isFavorite
    }

    /// Сборка из общего резолвера оформления — второго резолвера в проекте нет.
    static func make(
        key: String,
        name: String,
        appearance: AccountAppearanceSnapshot?,
        legacyIconName: String? = nil,
        legacyIconColorHex: String? = nil,
        fallbackIconName: String,
        amountText: String,
        currencySymbol: String,
        isNegative: Bool = false
    ) -> AccountRowPresentation {
        let resolved = CashflowAccountPickerDetailsFactory.resolvedAppearance(
            key: key,
            name: name,
            appearance: appearance,
            legacyIconName: legacyIconName,
            legacyIconColorHex: legacyIconColorHex
        )
        return AccountRowPresentation(
            name: name,
            iconName: resolved.iconName,
            iconColorHex: resolved.iconColorHex,
            fallbackIconName: fallbackIconName,
            amountText: amountText,
            currencySymbol: currencySymbol,
            isNegative: isNegative,
            isFavorite: appearance?.isFavorite == true
        )
    }
}

// MARK: - Row

/// ЕДИНСТВЕННАЯ вёрстка строки счёта в приложении. Списки групп, «Без группы», редактор группы,
/// архив и легаси-строки рисуют её, а не свою разметку: два параллельных макета — это ровно та
/// причина, по которой редизайн V11 не был виден на счетах старого мира.
///
/// `accessory` — слот под подстроки конкретного мира (позиция инвестиции, остаток лимита,
/// sparkline). Это не «вторая вёрстка»: скелет (бейдж → имя → сумма) один и тот же.
struct AccountRowView<Accessory: View>: View {
    let presentation: AccountRowPresentation
    /// Архивный счёт: тот же макет, приглушённый — отдельной вёрстки для архива не заводим.
    var isDimmed: Bool = false
    /// nil = строка read-only (редактор группы, архив): контекстное меню не вешается.
    var onToggleFavorite: (() -> Void)?
    /// nil = оформление этого счёта редактируется в другом месте (легаси-форма счёта).
    var onEditAppearance: (() -> Void)?
    @ViewBuilder var accessory: () -> Accessory

    /// Размер бейджа строки списка. Hero-карточка деталки (Ф3) свой размер задаёт сама.
    private static var badgeSize: CGFloat { 36 }
    private static var dimmedOpacity: Double { 0.55 }

    private var amountColor: Color {
        presentation.isNegative ? AppColors.error : AppColors.textPrimary
    }

    private var hasMenu: Bool {
        onToggleFavorite != nil || onEditAppearance != nil
    }

    var body: some View {
        // Меню вешаем только там, где есть хоть одно действие: пустой `contextMenu` даёт долгое
        // нажатие без единого пункта — визуальный «мёртвый» отклик в редакторе группы и архиве.
        if hasMenu {
            rowContent.contextMenu { menuItems }
        } else {
            rowContent
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        if let onToggleFavorite {
            Button(action: onToggleFavorite) {
                if presentation.isFavorite {
                    Label(L("finances.account.favorite.remove"), systemImage: "star.slash")
                } else {
                    Label(L("finances.account.favorite.add"), systemImage: "star")
                }
            }
        }
        if let onEditAppearance {
            Button(action: onEditAppearance) {
                Label(L("finances.account.appearance.edit"), systemImage: "paintpalette")
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: AppSpacing.m) {
            AccountIconBadgeView(
                iconName: presentation.iconName,
                iconColor: presentation.iconColorHex,
                fallback: presentation.fallbackIconName,
                size: Self.badgeSize,
                isError: presentation.isNegative
            )

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    OverflowFadeText(
                        text: presentation.name,
                        font: .millioSubheadline,
                        color: AppColors.textPrimary,
                        fadeStart: FinancesMainLayoutPolicy.groupRowNameFadeStart,
                        fadeEnd: FinancesMainLayoutPolicy.groupRowNameFadeEnd
                    )

                    if presentation.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.millioCaption2)
                            .foregroundStyle(AppColors.warning)
                            .accessibilityLabel(L("finances.account.favorite.badge"))
                    }
                }

                accessory()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(presentation.amountText)
                    .font(.millioSubheadline)
                    .foregroundStyle(amountColor.opacity(0.92))
                Text(presentation.currencySymbol)
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

extension AccountRowView where Accessory == EmptyView {
    init(
        presentation: AccountRowPresentation,
        isDimmed: Bool = false,
        onToggleFavorite: (() -> Void)? = nil,
        onEditAppearance: (() -> Void)? = nil
    ) {
        self.init(
            presentation: presentation,
            isDimmed: isDimmed,
            onToggleFavorite: onToggleFavorite,
            onEditAppearance: onEditAppearance,
            accessory: { EmptyView() }
        )
    }
}
