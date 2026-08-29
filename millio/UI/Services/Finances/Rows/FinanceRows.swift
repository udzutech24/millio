//
//  FinanceRows.swift
//  millio
//

import SwiftUI
import UniformTypeIdentifiers

// `OverflowFadeText` и его preference-ключи переехали в `AccountRowView.swift`:
// их использует единая строка счёта, а не только легаси-строки этого файла.

private func financeAmountLabel(
    amountText: String,
    currencySymbol: String,
    amountFontSize: CGFloat,
    amountColor: Color,
    currencyColor: Color
) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(amountText)
            .font(.system(size: amountFontSize, weight: .semibold).monospacedDigit())
            .foregroundStyle(amountColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)

        Text(currencySymbol)
            .font(.system(size: max(11, amountFontSize * 0.82), weight: .medium))
            .foregroundStyle(currencyColor)
            .lineLimit(1)
    }
}

// MARK: - Group Product Category (иконка вместо цветной полоски)

/// Обобщённая товарная категория счетов группы — для иконки-бейджа в строке группы.
/// Не путать с `FinanceAccountType`/`AccountKind` — это UI-упрощение для отображения одной иконки
/// на группу, которая может содержать разнородные счета.
private enum FinanceGroupProductCategory: Hashable {
    case deposit
    case investment
    case credit
    case card
    case other

    /// Порядок разрешения ничьих при подсчёте доминирующей категории.
    static let priorityOrder: [FinanceGroupProductCategory] = [.investment, .credit, .deposit, .card, .other]

    init(legacyType: FinanceAccountType) {
        switch legacyType {
        case .card: self = .card
        case .credit: self = .credit
        case .investment: self = .investment
        }
    }

    init(kind: AccountKind) {
        switch kind {
        case .deposit: self = .deposit
        case .loan, .debt: self = .credit
        case .marketInvestment: self = .investment
        case .cash, .debitCard, .bankAccount: self = .card
        case .manualAsset: self = .other
        }
    }

    var iconName: String {
        switch self {
        case .deposit: return "banknote.fill"
        case .investment: return "chart.line.uptrend.xyaxis"
        case .credit: return "doc.text.fill"
        case .card: return "creditcard.fill"
        case .other: return "square.grid.2x2.fill"
        }
    }
}

/// Квадратная иконка-бейдж типа продукта группы — заменяет цветную вертикальную полоску-акцент.
private struct FinanceGroupTypeIconView: View {
    let category: FinanceGroupProductCategory
    let accentColor: Color
    /// Кастомная иконка группы (SF Symbol / "monogram:XX" / эмодзи). nil = иконка по типу продукта.
    var customIconName: String? = nil

    private var iconName: String { customIconName ?? category.iconName }
    private var isMonogram: Bool { AccountIconSet.isMonogram(iconName) }

    var body: some View {
        RoundedRectangle(cornerRadius: FinancesMainLayoutPolicy.groupRowTypeIconCornerRadius, style: .continuous)
            .fill(accentColor.opacity(0.16))
            .overlay(glyph)
            .frame(
                width: FinancesMainLayoutPolicy.groupRowTypeIconSize,
                height: FinancesMainLayoutPolicy.groupRowTypeIconSize
            )
    }

    @ViewBuilder
    private var glyph: some View {
        if isMonogram {
            Text(AccountIconSet.monogramText(iconName))
                .font(.system(size: FinancesMainLayoutPolicy.groupRowTypeIconSize * 0.40, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            Image(systemName: iconName)
                .font(.system(size: FinancesMainLayoutPolicy.groupRowTypeIconSize * 0.44, weight: .semibold))
                .foregroundStyle(accentColor)
        }
    }
}

// MARK: - Finance Group Row

struct FinanceGroupRow: View {
    let group: AccountGroup
    @ObservedObject var viewModel: FinanceViewModel
    @Binding var draggedGroupID: String?

    // Раньше 28pt резервировали место под цветную полоску-акцент слева от заголовка.
    // Полоску заменила иконка типа продукта (см. FinanceGroupTypeIconView) — инсет уменьшен.
    private let contentLeadingInset: CGFloat = AppSpacing.l
    private let contentTrailingInset: CGFloat = 16
    private let expandedDividerLeadingInset: CGFloat = 64
    
    private var groupID: String {
        group.groupUniqueID
    }
    
    private var isExpanded: Bool {
        viewModel.state.expandedGroupIDs.contains(groupID)
    }
    
    private var groupTotal: Double {
        viewModel.state.groupTotals[groupID] ?? 0.0
    }

    /// [Ф5c.7 contract] Легаси-fallback-хвост (invariant 9 §2.1) — непроконвертированные записи
    /// одноимённой `FinanceGroup`. Primary-рендер группы теперь `newCoreAccounts` ниже.
    private var legacyAccounts: [FinanceAccount] {
        viewModel.legacyAccountsMatchingGroupName(group.name)
    }

    private var totalAccountsCount: Int {
        legacyAccounts.count + newCoreAccounts.count
    }

    /// Доминирующая товарная категория группы для иконки-бейджа (заменяет цветную полоску).
    /// Группа может содержать разные типы счетов — берём большинство, при ничьей приоритет
    /// фиксированный (инвестиции > кредит > вклад > карта), пустая группа = "прочее".
    private var dominantProductCategory: FinanceGroupProductCategory {
        var counts: [FinanceGroupProductCategory: Int] = [:]
        for account in legacyAccounts {
            let category = FinanceGroupProductCategory(legacyType: account.accountType)
            counts[category, default: 0] += 1
        }
        for account in newCoreAccounts {
            let category = FinanceGroupProductCategory(kind: account.kind)
            counts[category, default: 0] += 1
        }
        guard let maxCount = counts.values.max() else { return .other }
        let topCategories = counts.filter { $0.value == maxCount }.keys
        return FinanceGroupProductCategory.priorityOrder.first { topCategories.contains($0) } ?? .other
    }

    var body: some View {
        groupContent
            .background(groupBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(FinanceScreenChrome.surfaceStrokeColor)
                    .frame(height: FinancesMainLayoutPolicy.accountsListGroupSeparatorHeight)
            }
            .clipShape(Rectangle())
            .onDrop(
                of: [UTType.text],
                delegate: FinanceGroupIndexDropDelegate(
                    destinationIndex: viewModel.visibleGroupsForList().firstIndex(where: { $0.groupUniqueID == groupID }) ?? 0,
                    draggedGroupID: $draggedGroupID,
                    viewModel: viewModel
                )
            )
            .modifier(GroupRowModifiers(
                isExpanded: isExpanded,
                group: group,
                viewModel: viewModel,
                groupID: groupID,
                loadGroupTotal: loadGroupTotal
            ))
    }
    
    private var groupContent: some View {
        VStack(spacing: 0) {
            groupHeader
            if isExpanded {
                accountsAccordion
            }
        }
    }
    
    private var groupHeader: some View {
        GeometryReader { proxy in
            HStack(spacing: AppSpacing.m) {
                FinanceGroupTypeIconView(
                    category: dominantProductCategory,
                    accentColor: group.color,
                    customIconName: group.customIconName
                )

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.handle(.toggleGroupExpanded(groupID))
                    }
                } label: {
                    headerContent(containerWidth: proxy.size.width)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

                dragChevron
            }
            .padding(.vertical, AppSpacing.l)
            .padding(.leading, contentLeadingInset)
            .padding(.trailing, contentTrailingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in
                        viewModel.handle(.showGroupDynamics(group))
                    }
            )
        }
        .frame(height: FinancesMainLayoutPolicy.groupRowHeaderHeight)
    }
    
    private func headerContent(containerWidth: CGFloat) -> some View {
        HStack(spacing: 12) {
            groupNameSection

            groupAmountSection(containerWidth: containerWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    
    private var groupNameSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs / 2) {
            OverflowFadeText(
                text: group.name,
                font: .system(size: 16, weight: .semibold),
                color: AppColors.textPrimary,
                fadeStart: FinancesMainLayoutPolicy.groupRowNameFadeStart,
                fadeEnd: FinancesMainLayoutPolicy.groupRowNameFadeEnd
            )

            // Явно без процентов динамики — приросты живут только на экране «Динамика».
            Text(String(format: L("finances.group.accounts_count"), totalAccountsCount))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textTertiary.opacity(0.9))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }
    
    private func groupAmountSection(containerWidth: CGFloat) -> some View {
        let amountColor = groupTotal < 0 ? AppColors.error : AppColors.textPrimary
        return VStack(alignment: .trailing, spacing: AppSpacing.xs / 2) {
            financeAmountLabel(
                amountText: formatBalance(groupTotal, isHidden: viewModel.state.isAmountHidden),
                currencySymbol: MonetaCurrency(rawValue: groupDisplayCurrency)?.symbol ?? groupDisplayCurrency,
                amountFontSize: 15,
                amountColor: amountColor.opacity(0.92),
                currencyColor: amountColor.opacity(0.66)
            )

            if showsPrimaryCurrencySubtitle {
                Text(primaryCurrencySubtitleText)
                    .font(.millioMicro)
                    .foregroundStyle(AppColors.textTertiary.opacity(0.82))
                    .lineLimit(1)
            }
        }
        .frame(
            width: FinancesMainLayoutPolicy.groupRowAmountWidth(containerWidth: containerWidth),
            alignment: .trailing
        )
        .padding(.leading, 12)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// [Гейт 5c.7.6.2 фикс-раунд] Группа со своей `displayCurrency`, отличной от валюты шапки —
    /// показываем подстроку «≈ N ₽» (зеркалит формат чипа шапки). Значение уже посчитано СИНХРОННО
    /// (`state.groupTotalsPrimaryCurrency`, обновляется в `FinanceViewModel.refreshGroupTotalPrimaryCurrency`
    /// тем же `calculateGroupTotal`) — второго async-прохода конвертации здесь нет.
    private var showsPrimaryCurrencySubtitle: Bool {
        guard let groupCurrency = group.displayCurrency else { return false }
        return groupCurrency.uppercased() != viewModel.state.displayCurrency.uppercased()
            && viewModel.state.groupTotalsPrimaryCurrency[groupID] != nil
    }

    private var primaryCurrencySubtitleText: String {
        // `showsPrimaryCurrencySubtitle` гарантирует наличие значения. Не подменяем состояние
        // «ещё не рассчитано» доказанным финансовым нулём: это и было причиной ложного `≈ 0 ₽`.
        guard let converted = viewModel.state.groupTotalsPrimaryCurrency[groupID] else { return "" }
        let symbol = MonetaCurrency(rawValue: viewModel.state.displayCurrency)?.symbol ?? viewModel.state.displayCurrency
        return "≈ \(formatBalance(converted, isHidden: viewModel.state.isAmountHidden)) \(symbol)"
    }
    
    private var accountsAccordion: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.leading, expandedDividerLeadingInset)
                .padding(.trailing, contentTrailingInset)

            let displayAccounts: [(account: FinanceAccount, info: (name: String, amount: Double, currency: String, icon: String, isCreditCardDebt: Bool), customIconName: String?, customIconColor: String?)] = legacyAccounts.compactMap { account in
                guard let info = viewModel.getAccountInfo(account: account) else { return nil }
                let iconInfo = viewModel.customIconInfo(for: account)
                return (account: account, info: info, customIconName: iconInfo.iconName, customIconColor: iconInfo.iconColor)
            }

            if displayAccounts.isEmpty && newCoreAccounts.isEmpty {
                Text(L("finances.main.empty_products.title"))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, contentLeadingInset)
                    .padding(.trailing, contentTrailingInset)
                    .padding(.vertical, 14)
            } else {
                ForEach(Array(displayAccounts.enumerated()), id: \.element.account.id) { index, item in
                    FinanceAccountRow(
                        viewModel: viewModel,
                        account: item.account,
                        name: item.info.name,
                        amount: item.info.amount,
                        currency: item.info.currency,
                        icon: item.info.icon,
                        customIconName: item.customIconName,
                        customIconColor: item.customIconColor,
                        accountType: item.account.accountType,
                        isCreditCardDebt: item.info.isCreditCardDebt,
                        // [Ф5c.7 contract] `.showAccountDynamics` остаётся легаси-типизированным
                        // (ментор-находка — реальный потребитель неотделимо легаси). Quick-edit
                        // недоступен для легаси fallback-хвоста (invariant 9) — мёртвый
                        // `FinanceQuickEditAccountView`/`.showQuickEditAccountSheet` снесён (владелец
                        // 2026-07-12): редактирование доступно через AccountDetailView/AccountAdjustBalanceSheet.
                        onEdit: {
                            viewModel.handle(.showAccountDynamics(item.account))
                        },
                        onQuickEditAmount: {}
                    )

                    if index != displayAccounts.count - 1 || !newCoreAccounts.isEmpty {
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.leading, expandedDividerLeadingInset)
                            .padding(.trailing, contentTrailingInset)
                    }
                }
            }

            // Счета нового ядра event-sourcing (Фаза 1a-ui) — сосуществуют со старым миром в той же
            // группе (сопоставление по имени, см. `FinanceViewModel.newCoreAccounts(matching:)`).
            ForEach(Array(newCoreAccounts.enumerated()), id: \.element.id) { index, account in
                NavigationLink {
                    AccountDetailView(account: account, modelContext: viewModel.modelContext)
                } label: {
                    NewCoreAccountRow(
                        account: account,
                        balance: viewModel.newCoreBalanceToday(account),
                        isAmountHidden: viewModel.state.isAmountHidden,
                        appearance: viewModel.appearance(for: account),
                        onToggleFavorite: { viewModel.toggleFavorite(account) },
                        onSaveAppearance: { iconName, tintHex, presetRaw in
                            viewModel.saveAppearance(
                                iconName: iconName,
                                tintHex: tintHex,
                                presetRaw: presetRaw,
                                for: account
                            )
                        }
                    )
                    .padding(.leading, contentLeadingInset)
                    .padding(.trailing, contentTrailingInset)
                }
                .buttonStyle(.plain)

                if index != newCoreAccounts.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.leading, expandedDividerLeadingInset)
                        .padding(.trailing, contentTrailingInset)
                }
            }
        }
        .padding(.bottom, 10)
    }

    /// [Ф5c.7 contract] Primary-рендер группы — `orderedAccounts(for:)` читает `group.accounts`
    /// напрямую (core) — тот же источник, что у ledger-графика и редактора группы (R8).
    private var newCoreAccounts: [Account] {
        viewModel.orderedAccounts(for: group)
    }

    private var dragChevron: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                viewModel.handle(.toggleGroupExpanded(groupID))
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary.opacity(0.9))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(
                    width: FinancesMainLayoutPolicy.groupRowChevronSize,
                    height: FinancesMainLayoutPolicy.groupRowChevronSize
                )
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag {
            draggedGroupID = groupID
            return NSItemProvider(object: groupID as NSString)
        }
    }
    
    // Цветной акцент группы теперь несёт иконка типа продукта (FinanceGroupTypeIconView),
    // отдельная капсула-полоска слева больше не нужна.
    private var groupBackground: some View {
        FinanceChromeCardBackground(
            cornerRadius: FinancesMainLayoutPolicy.accountsListGroupCornerRadius,
            accentColor: group.color,
            showsStroke: false
        )
    }
    
    private func loadGroupTotal() async {
        let currency = group.displayCurrency ?? viewModel.state.displayCurrency
        let total = await viewModel.calculateGroupTotal(
            group: group,
            in: currency
        )
        viewModel.handle(.setGroupTotal(groupID, total))
    }
    
    private var groupDisplayCurrency: String {
        group.displayCurrency ?? viewModel.state.displayCurrency
    }
    
    private func formatBalance(_ balance: Double, isHidden: Bool = false) -> String {
        if isHidden {
            // Подсчитываем количество цифр в числе
            let digits = Int(balance.rounded())
            let digitCount = String(digits).count
            // Возвращаем точки вместо цифр
            return String(repeating: "•", count: max(3, digitCount))
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
    }
    
}

// MARK: - Group Row Modifiers

private struct GroupRowModifiers: ViewModifier {
    let isExpanded: Bool
    let group: AccountGroup
    @ObservedObject var viewModel: FinanceViewModel
    let groupID: String
    let loadGroupTotal: () async -> Void
    
    func body(content: Content) -> some View {
        content
            .task {
                await loadGroupTotal()
            }
            .onChange(of: isExpanded) { oldValue, newValue in
                if newValue {
                    Task {
                        await loadGroupTotal()
                    }
                }
            }
            .onChange(of: group.id) { oldValue, newValue in
                Task {
                    await loadGroupTotal()
                }
            }
            .onChange(of: group.displayCurrency) { oldValue, newValue in
                Task {
                    await loadGroupTotal()
                }
            }
            .onChange(of: viewModel.state.displayCurrency) { oldValue, newValue in
                if group.displayCurrency == nil {
                    Task {
                        await loadGroupTotal()
                    }
                }
            }
            .onChange(of: viewModel.state.availableCards) { oldCards, newCards in
                Task {
                    await loadGroupTotal()
                }
            }
            .onChange(of: viewModel.state.availableCredits) { oldCredits, newCredits in
                Task {
                    await loadGroupTotal()
                }
            }
            .onChange(of: viewModel.state.availableInvestments) { oldInvestments, newInvestments in
                Task {
                    await loadGroupTotal()
                }
            }
    }
}

// MARK: - Finance Account Row

/// Строка легаси-счёта (`Card`/`Credit`/`Investment`). Своей вёрстки НЕ имеет — собирает
/// презентацию и отдаёт её единой `AccountRowView`; собственными остаются только подстроки
/// старого мира (позиция инвестиции, остаток лимита, sparkline) и переходы.
private struct FinanceAccountRow: View {
    @ObservedObject var viewModel: FinanceViewModel
    let account: FinanceAccount
    let name: String
    let amount: Double
    let currency: String
    let icon: String
    let customIconName: String?
    let customIconColor: String?
    let accountType: FinanceAccountType
    let isCreditCardDebt: Bool
    let onEdit: () -> Void
    let onQuickEditAmount: () -> Void

    /// Один sheet-слот на строку: два независимых `.sheet` на одной вьюхе дают гонку presentation.
    private enum ActiveSheet: Int, Identifiable {
        case balanceChart
        case appearance
        var id: Int { rawValue }
    }

    @State private var activeSheet: ActiveSheet?
    // Sheet-в-sheet напрямую SwiftUI не поддерживает (гонка presentation).
    // Поэтому переход в деталку счёта откладываем до onDismiss текущего sheet.
    @State private var shouldOpenAccountDetailAfterChartDismiss = false
    @State private var draftIconName: String?
    @State private var draftTintHex: String?
    @State private var draftPresetRaw: String?

    // Читаем баланс из viewModel в body — @ObservedObject FinanceAccountRow сам перерисуется
    // при objectWillChange, не завися от того, перерисует ли родитель FinanceGroupRow
    private var resolvedAmount: Double {
        viewModel.getAccountInfo(account: account)?.amount ?? amount
    }

    private var isMarketInvestment: Bool {
        viewModel.getMarketInvestment(account: account) != nil
    }

    private var isDebtHighlighted: Bool {
        viewModel.isAccountLiabilityForTotals(account: account) || isCreditCardDebt
    }

    /// Рыночная позиция показывает копейки — у остальных продуктов в списке их нет.
    private var maximumFractionDigits: Int { isMarketInvestment ? 2 : 0 }

    private var presentation: AccountRowPresentation {
        AccountRowPresentation.make(
            key: account.accountID,
            name: name,
            appearance: viewModel.appearance(for: account),
            legacyIconName: customIconName,
            legacyIconColorHex: customIconColor,
            fallbackIconName: icon,
            amountText: formatBalance(
                resolvedAmount,
                isHidden: viewModel.state.isAmountHidden,
                maximumFractionDigits: maximumFractionDigits
            ),
            currencySymbol: MonetaCurrency(rawValue: currency)?.symbol ?? currency,
            isNegative: isDebtHighlighted || resolvedAmount < 0
        )
    }

    private var sparklineColor: Color {
        if let hex = presentation.iconColorHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        return AppColors.brandPrimary
    }

    /// Счёт со «старым» composite-идентификатором в UUID не парсится, а `AccountAppearance`
    /// ключуется UUID — редактировать оформление такому счёту негде (рисуется дефолтом).
    private var appearanceAccountID: UUID? {
        UUID(uuidString: account.accountID)
    }

    private let contentLeadingInset: CGFloat = 28
    private let contentTrailingInset: CGFloat = 16

    private var editAppearanceAction: (() -> Void)? {
        guard appearanceAccountID != nil else { return nil }
        return { startEditingAppearance() }
    }

    var body: some View {
        AccountRowView(
            presentation: presentation,
            onEditAppearance: editAppearanceAction,
            accessory: { accessory }
        )
        .padding(.leading, contentLeadingInset)
        .padding(.trailing, contentTrailingInset)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .sheet(item: $activeSheet, onDismiss: {
            if shouldOpenAccountDetailAfterChartDismiss {
                shouldOpenAccountDetailAfterChartDismiss = false
                onEdit()
            }
        }) { sheet in
            switch sheet {
            case .balanceChart:
                AccountBalanceChartView(
                    accountID: account.accountID,
                    accountName: name,
                    currency: currency,
                    accentColor: sparklineColor,
                    onOpenAccountDetail: {
                        shouldOpenAccountDetailAfterChartDismiss = true
                        activeSheet = nil
                    }
                )
            case .appearance:
                AccountIconPickerSheet(
                    iconName: $draftIconName,
                    iconColor: $draftTintHex,
                    presetRaw: $draftPresetRaw
                )
                .onDisappear {
                    viewModel.saveAppearance(
                        iconName: draftIconName,
                        tintHex: draftTintHex,
                        presetRaw: draftPresetRaw,
                        for: account
                    )
                }
            }
        }
    }

    /// Подстроки старого мира. Единственное, чем строка легаси-счёта отличается от core-строки.
    @ViewBuilder
    private var accessory: some View {
        if let subtitle = viewModel.getInvestmentPositionSubtitle(account: account) {
            OverflowFadeText(
                text: subtitle,
                font: .millioCaption2Regular,
                color: AppColors.textSecondary,
                fadeStart: FinancesMainLayoutPolicy.groupRowNameFadeStart,
                fadeEnd: FinancesMainLayoutPolicy.groupRowNameFadeEnd
            )
        }

        if isMarketInvestment {
            if let performance = viewModel.getInvestmentPurchaseGrowthSubtitle(account: account) {
                OverflowFadeText(
                    text: performance.text,
                    font: .millioCaption2Medium,
                    color: performance.isPositive ? Color.green : AppColors.error,
                    fadeStart: FinancesMainLayoutPolicy.groupRowNameFadeStart,
                    fadeEnd: FinancesMainLayoutPolicy.groupRowNameFadeEnd
                )
            }
        } else {
            if let limitSubtitle = creditLimitSubtitle {
                Text(limitSubtitle)
                    .font(.millioCaption2Medium)
                    .foregroundStyle(AppColors.textTertiary.opacity(0.9))
                    .lineLimit(1)
            }
            sparkline
        }
    }

    @ViewBuilder
    private var sparkline: some View {
        let sparkPoints = AccountBalanceHistoryStore.dailyAmounts(
            accountID: account.accountID,
            currency: currency,
            daysCount: 14
        ).compactMap { $0 }
        if sparkPoints.count >= 2 {
            Button {
                activeSheet = .balanceChart
            } label: {
                AccountBalanceSparklineView(
                    accountID: account.accountID,
                    currency: currency,
                    color: sparklineColor
                )
                .frame(width: 56, height: 22)
            }
            .buttonStyle(.plain)
        }
    }

    private func startEditingAppearance() {
        // В пикер отдаём ЯВНЫЙ выбор пользователя (оформление или легаси-поля счёта), но не
        // вычисленный дефолт: иначе первый же вход в редактор «застолбил» бы авто-цвет как ручной.
        let appearance = viewModel.appearance(for: account)
        draftIconName = appearance?.iconName ?? customIconName
        draftTintHex = appearance?.tintHex ?? customIconColor
        draftPresetRaw = appearance?.presetRaw
        activeSheet = .appearance
    }

    private var creditLimitSubtitle: String? {
        guard let remaining = viewModel.getCreditCardLimitRemaining(account: account) else {
            return nil
        }
        let amountText = formatBalance(remaining.amount, isHidden: viewModel.state.isAmountHidden)
        let currencySymbol = MonetaCurrency(rawValue: remaining.currency)?.symbol ?? remaining.currency
        return FinancesL10n.format("finances.account.credit_limit_remaining", amountText, currencySymbol)
    }

    private func formatBalance(_ balance: Double, isHidden: Bool = false, maximumFractionDigits: Int = 0) -> String {
        AccountRowAmountFormatter.text(
            balance,
            isHidden: isHidden,
            maximumFractionDigits: maximumFractionDigits
        )
    }
}

struct FinanceGroupIndexDropDelegate: DropDelegate {
    let destinationIndex: Int
    @Binding var draggedGroupID: String?
    let viewModel: FinanceViewModel

    func performDrop(info: DropInfo) -> Bool {
        if let sourceGroupID = draggedGroupID {
            viewModel.handle(.moveGroup(sourceGroupID: sourceGroupID, destinationIndex: destinationIndex))
        }
        draggedGroupID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
