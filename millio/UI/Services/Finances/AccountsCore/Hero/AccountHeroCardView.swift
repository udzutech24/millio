import SwiftUI

/// Готовые к отрисовке данные hero-карточки детального экрана счёта. Значение, а не модель:
/// hero одинаково собирается для обоих миров счетов (core `Account` и легаси `Card`/`Credit`/
/// `Investment`), а сумма приходит УЖЕ отформатированной — второго определения баланса и его
/// форматирования в приложении быть не должно.
struct AccountHeroPresentation: Equatable {
    struct Badge: Equatable, Identifiable {
        let text: String
        let systemImage: String
        /// Предупреждающий статус (просрочка, устаревшая цена) — красится в `AppColors.warning`.
        var isWarning: Bool = false

        var id: String { "\(systemImage)|\(text)" }
    }

    let name: String
    /// Банк и `•• last4` / тикер — вторая строка идентичности счёта.
    let subtitle: String?
    /// Человекочитаемый тип продукта («Кредитная карта», «Вклад»).
    let typeTitle: String?
    let amountText: String
    let currencySymbol: String
    /// Долг/обязательство: сумма красится в `AppColors.error`.
    let isNegative: Bool
    let iconName: String?
    let iconColorHex: String?
    let fallbackIconName: String
    /// Градиент выбранного дизайна (Ф2). Пусто → карточка строится из акцента счёта.
    let gradientHexes: [String]
    /// Строки-подробности конкретного типа (ставка/срок вклада, лимит/платёж кредитки).
    let detailLines: [String]
    let badges: [Badge]

    /// Сборка через ОБЩИЙ резолвер оформления — того же, что рисует строку списка и пикер Cashflow.
    /// Другой источник иконки/цвета здесь означал бы, что деталка и список расходятся визуально.
    static func make(
        key: String,
        name: String,
        appearance: AccountAppearanceSnapshot?,
        legacyIconName: String? = nil,
        legacyIconColorHex: String? = nil,
        fallbackIconName: String,
        subtitle: String? = nil,
        typeTitle: String? = nil,
        amountText: String,
        currencySymbol: String,
        isNegative: Bool = false,
        detailLines: [String] = [],
        badges: [Badge] = []
    ) -> AccountHeroPresentation {
        let resolved = CashflowAccountPickerDetailsFactory.resolvedAppearance(
            key: key,
            name: name,
            appearance: appearance,
            legacyIconName: legacyIconName,
            legacyIconColorHex: legacyIconColorHex
        )
        return AccountHeroPresentation(
            name: name,
            subtitle: subtitle,
            typeTitle: typeTitle,
            amountText: amountText,
            currencySymbol: currencySymbol,
            isNegative: isNegative,
            iconName: resolved.iconName,
            iconColorHex: resolved.iconColorHex,
            fallbackIconName: fallbackIconName,
            gradientHexes: AccountAppearancePreset.resolve(appearance?.presetRaw)?.gradientHexes ?? [],
            detailLines: detailLines,
            badges: badges
        )
    }

    /// Цвета подложки. Без выбранного дизайна карточка строится из акцента счёта (того самого, что
    /// красит бейдж в списке): второй градиент к нему подмешивается затемнением, чтобы карточка
    /// оставалась читаемой в тёмной теме и не расходилась по цвету со строкой списка.
    var gradientColors: [Color] {
        if !gradientHexes.isEmpty {
            return gradientHexes.map { Color(hex: $0) }
        }
        guard let hex = iconColorHex, !hex.isEmpty else {
            return AppColors.financesGradient
        }
        let accent = Color(hex: hex)
        return [accent.opacity(0.92), accent.opacity(0.42)]
    }
}

/// ЕДИНСТВЕННАЯ шапка детального экрана счёта. Per-type секции показывают свои метрики, но
/// идентичность счёта (имя, оформление, баланс, статусы) рисует только этот компонент — иначе
/// экран получает 5 разных шапок, как было до Ф3.
struct AccountHeroCardView<Content: View>: View {
    let presentation: AccountHeroPresentation
    /// Замена стандартной начинки (identity/сумма/детали/бейджи) — используется вкладом: у него
    /// hero несёт баланс/статус/метрики вклада, а не имя счёта (оно уже в navigation title).
    /// Носитель (градиент/скругления/паддинг) при этом остаётся тем же самым для всех типов.
    private var customContent: Content?

    init(presentation: AccountHeroPresentation) where Content == EmptyView {
        self.presentation = presentation
        self.customContent = nil
    }

    init(presentation: AccountHeroPresentation, @ViewBuilder customContent: () -> Content) {
        self.presentation = presentation
        self.customContent = customContent()
    }

    private static var badgeSize: CGFloat { 44 }

    private var amountColor: Color {
        presentation.isNegative ? AppColors.error : .white
    }

    var body: some View {
        Group {
            if let customContent {
                customContent
            } else {
                standardContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.l)
        .background(
            LinearGradient(
                colors: presentation.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Затемнение под контентом: пресеты бывают светлыми (золото, небо), а текст hero — белый.
            .overlay(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.xl, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.xl, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var standardContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            identityRow
            amountRow

            if !presentation.detailLines.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    ForEach(presentation.detailLines, id: \.self) { line in
                        Text(line)
                            .font(.millioCalloutRegular)
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
            }

            if !presentation.badges.isEmpty {
                statusBadges
            }
        }
    }

    private var identityRow: some View {
        HStack(spacing: AppSpacing.m) {
            AccountIconBadgeView(
                iconName: presentation.iconName,
                iconColor: presentation.iconColorHex,
                fallback: presentation.fallbackIconName,
                size: Self.badgeSize
            )

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(presentation.name)
                    .font(.millioHeadline)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                if let subtitle = presentation.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.millioCalloutRegular)
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: AppSpacing.s)

            if let typeTitle = presentation.typeTitle, !typeTitle.isEmpty {
                Text(typeTitle)
                    .font(.millioCaption2Medium)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, AppSpacing.s)
                    .padding(.vertical, AppSpacing.xs)
                    .background(Capsule().fill(Color.black.opacity(0.24)))
                    .lineLimit(1)
            }
        }
    }

    private var amountRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
            Text(presentation.amountText)
                .font(.millioTitle)
                .foregroundStyle(amountColor)
                // Крупная сумма на длинном балансе должна сжиматься, а не обрезаться многоточием.
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(presentation.currencySymbol)
                .font(.millioBody)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var statusBadges: some View {
        // Статусов бывает несколько сразу (архив + не в тотале) — переносим их, а не режем.
        FlowLayout(spacing: AppSpacing.s) {
            ForEach(presentation.badges) { badge in
                Label(badge.text, systemImage: badge.systemImage)
                    .font(.millioCaption2Medium)
                    .foregroundStyle(badge.isWarning ? AppColors.warning : .white.opacity(0.9))
                    .padding(.horizontal, AppSpacing.s)
                    .padding(.vertical, AppSpacing.xs)
                    .background(Capsule().fill(Color.black.opacity(0.24)))
            }
        }
    }
}

/// Простой переносящийся ряд для статус-бейджей. `LazyVGrid` здесь не подходит: бейджи разной
/// ширины, а фиксированные колонки дали бы дыры между «Архив» и «Не в тотале».
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: CGFloat = 1
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                totalHeight += lineHeight + spacing
                rows += 1
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += (lineWidth > 0 ? spacing : 0) + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }
        totalHeight += lineHeight
        return CGSize(width: proposal.width ?? lineWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
