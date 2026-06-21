//
//  FinanceRows.swift
//  millio
//

import SwiftUI
import UniformTypeIdentifiers

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

private struct OverflowFadeText: View {
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

// MARK: - Finance Group Row

struct FinanceGroupRow: View {
    let group: FinanceGroup
    @ObservedObject var viewModel: FinanceViewModel
    @Binding var draggedGroupID: String?

    private let contentLeadingInset: CGFloat = 28
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
    
    var body: some View {
        groupContent
            .background(groupBackground)
            .clipShape(RoundedRectangle(cornerRadius: FinanceScreenChrome.groupRowCornerRadius, style: .continuous))
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
            HStack(spacing: 12) {
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
            .padding(.vertical, 16)
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
        .frame(height: 56)
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
        HStack(spacing: 6) {
            OverflowFadeText(
                text: group.name,
                font: .system(size: 16, weight: .semibold),
                color: AppColors.textPrimary,
                fadeStart: FinancesMainLayoutPolicy.groupRowNameFadeStart,
                fadeEnd: FinancesMainLayoutPolicy.groupRowNameFadeEnd
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }
    
    private func groupAmountSection(containerWidth: CGFloat) -> some View {
        let amountColor = groupTotal < 0 ? AppColors.error : AppColors.textPrimary
        return financeAmountLabel(
            amountText: formatBalance(groupTotal, isHidden: viewModel.state.isAmountHidden),
            currencySymbol: MonetaCurrency(rawValue: groupDisplayCurrency)?.symbol ?? groupDisplayCurrency,
            amountFontSize: 15,
            amountColor: amountColor.opacity(0.92),
            currencyColor: amountColor.opacity(0.66)
        )
        .frame(
            width: FinancesMainLayoutPolicy.groupRowAmountWidth(containerWidth: containerWidth),
            alignment: .trailing
        )
        .padding(.leading, 12)
        .fixedSize(horizontal: false, vertical: true)
    }
    
    private var accountsAccordion: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.leading, expandedDividerLeadingInset)
                .padding(.trailing, contentTrailingInset)

            let displayAccounts: [(account: FinanceAccount, info: (name: String, amount: Double, currency: String, icon: String, isCreditCardDebt: Bool), customIconName: String?, customIconColor: String?)] = viewModel.orderedAccounts(for: group).compactMap { account in
                guard let info = viewModel.getAccountInfo(account: account) else { return nil }
                let iconInfo = viewModel.customIconInfo(for: account)
                return (account: account, info: info, customIconName: iconInfo.iconName, customIconColor: iconInfo.iconColor)
            }

            if displayAccounts.isEmpty {
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
                        onEdit: {
                            viewModel.handle(.showAccountDynamics(item.account))
                        },
                        onQuickEditAmount: {
                            viewModel.handle(.showQuickEditAccountSheet(item.account))
                        }
                    )

                    if index != displayAccounts.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.08))
                            .padding(.leading, expandedDividerLeadingInset)
                            .padding(.trailing, contentTrailingInset)
                    }
                }
            }

        }
        .padding(.bottom, 10)
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
    
    private var groupBackground: some View {
        let accentColor = group.color
        return FinanceChromeCardBackground(
            cornerRadius: FinanceScreenChrome.groupRowCornerRadius,
            accentColor: accentColor
        )
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(accentColor.opacity(0.9))
                    .frame(width: 2.5)
                    .padding(.vertical, 14)
                    .padding(.leading, 12)
            }
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
    let group: FinanceGroup
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

    @State private var showBalanceChart = false

    // Читаем баланс из viewModel в body — @ObservedObject FinanceAccountRow сам перерисуется
    // при objectWillChange, не завися от того, перерисует ли родитель FinanceGroupRow
    private var resolvedAmount: Double {
        viewModel.getAccountInfo(account: account)?.amount ?? amount
    }

    private var sparklineColor: Color {
        if let hex = customIconColor, !hex.isEmpty {
            return Color(hex: hex)
        }
        return AppColors.brandPrimary
    }

    private let contentLeadingInset: CGFloat = 28
    private let contentTrailingInset: CGFloat = 16
    
    var body: some View {
        if viewModel.getMarketInvestment(account: account) != nil {
            marketInvestmentRow
        } else {
            defaultRow
        }
    }

    private var defaultRow: some View {
        HStack(spacing: 12) {
            AccountIconBadgeView(
                iconName: customIconName,
                iconColor: customIconColor,
                fallback: icon,
                size: 36,
                isError: isDebtHighlighted
            )

            VStack(alignment: .leading, spacing: 3) {
                OverflowFadeText(
                    text: name,
                    font: .system(size: 15, weight: .semibold),
                    color: AppColors.textPrimary,
                    fadeStart: FinancesMainLayoutPolicy.groupRowNameFadeStart,
                    fadeEnd: FinancesMainLayoutPolicy.groupRowNameFadeEnd
                )

                if let subtitle = viewModel.getInvestmentPositionSubtitle(account: account) {
                    OverflowFadeText(
                        text: subtitle,
                        font: .system(size: 11, weight: .regular),
                        color: AppColors.textSecondary,
                        fadeStart: FinancesMainLayoutPolicy.groupRowNameFadeStart,
                        fadeEnd: FinancesMainLayoutPolicy.groupRowNameFadeEnd
                    )
                }

                if let limitSubtitle = creditLimitSubtitle {
                    Text(limitSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary.opacity(0.9))
                        .lineLimit(1)
                }

                // Sparkline истории баланса
                let sparkPoints = AccountBalanceHistoryStore.dailyAmounts(
                    accountID: account.accountID,
                    currency: currency,
                    daysCount: 14
                ).compactMap { $0 }
                if sparkPoints.count >= 2 {
                    Button {
                        showBalanceChart = true
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
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingAmountSection(
                amountFontSize: 15,
                maximumFractionDigits: 0
            )
        }
        .padding(.leading, contentLeadingInset)
        .padding(.trailing, contentTrailingInset)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .sheet(isPresented: $showBalanceChart) {
            AccountBalanceChartView(
                accountID: account.accountID,
                accountName: name,
                currency: currency,
                accentColor: sparklineColor
            )
        }
    }

    private var marketInvestmentRow: some View {
        HStack(spacing: 12) {
            AccountIconBadgeView(
                iconName: customIconName,
                iconColor: customIconColor,
                fallback: icon,
                size: 36,
                isError: isDebtHighlighted
            )

            VStack(alignment: .leading, spacing: 3) {
                OverflowFadeText(
                    text: name,
                    font: .system(size: 15, weight: .semibold),
                    color: AppColors.textPrimary,
                    fadeStart: FinancesMainLayoutPolicy.groupRowNameFadeStart,
                    fadeEnd: FinancesMainLayoutPolicy.groupRowNameFadeEnd
                )

                if let subtitle = viewModel.getInvestmentPositionSubtitle(account: account) {
                    OverflowFadeText(
                        text: subtitle,
                        font: .system(size: 11, weight: .regular),
                        color: AppColors.textSecondary,
                        fadeStart: FinancesMainLayoutPolicy.groupRowNameFadeStart,
                        fadeEnd: FinancesMainLayoutPolicy.groupRowNameFadeEnd
                    )
                }

                if let performance = viewModel.getInvestmentPurchaseGrowthSubtitle(account: account) {
                    OverflowFadeText(
                        text: performance.text,
                        font: .system(size: 11, weight: .medium),
                        color: performance.isPositive ? Color.green : AppColors.error,
                        fadeStart: FinancesMainLayoutPolicy.groupRowNameFadeStart,
                        fadeEnd: FinancesMainLayoutPolicy.groupRowNameFadeEnd
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingAmountSection(
                amountFontSize: 15,
                maximumFractionDigits: 2
            )
        }
        .padding(.leading, contentLeadingInset)
        .padding(.trailing, contentTrailingInset)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }

    private var isDebtHighlighted: Bool {
        viewModel.isAccountLiabilityForTotals(account: account) || isCreditCardDebt
    }

    @ViewBuilder
    private func iconBadge(colors: [Color]) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 32, height: 32)
    }

    @ViewBuilder
    private func trailingAmountSection(
        amountFontSize: CGFloat,
        maximumFractionDigits: Int
    ) -> some View {
        let amountColor = isDebtHighlighted ? AppColors.error : (resolvedAmount >= 0 ? AppColors.textPrimary : AppColors.error)
        Button {
            onQuickEditAmount()
        } label: {
            VStack(alignment: .trailing, spacing: 2) {
                financeAmountLabel(
                    amountText: formatBalance(resolvedAmount, isHidden: viewModel.state.isAmountHidden, maximumFractionDigits: maximumFractionDigits),
                    currencySymbol: MonetaCurrency(rawValue: currency)?.symbol ?? currency,
                    amountFontSize: amountFontSize,
                    amountColor: amountColor.opacity(0.92),
                    currencyColor: amountColor.opacity(0.66)
                )
            }
        }
        .buttonStyle(.plain)
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
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
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
