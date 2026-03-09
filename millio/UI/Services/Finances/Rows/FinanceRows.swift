//
//  FinanceRows.swift
//  millio
//

import SwiftUI

// MARK: - Finance Group Row

struct FinanceGroupRow: View {
    let group: FinanceGroup
    @ObservedObject var viewModel: FinanceViewModel
    
    private var groupID: String {
        group.groupUniqueID
    }
    
    private var isExpanded: Bool {
        viewModel.state.expandedGroupIDs.contains(groupID)
    }
    
    private var groupTotal: Double {
        viewModel.state.groupTotals[groupID] ?? 0.0
    }
    
    private var priorityIcon: String {
        switch group.priority {
        case .high: return "arrow.up"
        case .normal: return "minus"
        case .low: return "arrow.down"
        }
    }
    
    private var priorityDisplayName: String {
        switch group.priority {
        case .high: return String(localized: "finances.priority.high")
        case .normal: return String(localized: "finances.priority.normal")
        case .low: return String(localized: "finances.priority.low")
        }
    }
    
    private var nextPriority: GroupPriority {
        // Циклически переключаем приоритет: normal -> high -> low -> normal
        switch group.priority {
        case .normal: return .high
        case .high: return .low
        case .low: return .normal
        }
    }
    
    var body: some View {
        groupContent
            .background(groupBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contextMenu {
                contextMenuContent
            }
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
        HStack(spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    viewModel.handle(.toggleGroupExpanded(groupID))
                }
            } label: {
                headerContent
            }
            .buttonStyle(.plain)
        }
    }
    
    private var headerContent: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(group.color)
                .frame(width: 12, height: 12)
               
            
            // Название группы
            groupNameSection
            
            // Сумма группы
            groupAmountSection
            
            // Иконка раскрытия
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
    }
    
    private var groupNameSection: some View {
        HStack(spacing: 6) {
//            if group.isFavorite {
//                Image(systemName: "star.fill")
//                    .font(.system(size: 12, weight: .semibold))
//                    .foregroundStyle(
//                        LinearGradient(
//                            colors: AppColors.incomeGradient,
//                            startPoint: .leading,
//                            endPoint: .trailing
//                        )
//                    )
//            }
            Text(group.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var groupAmountSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(formatBalance(groupTotal, isHidden: viewModel.state.isAmountHidden))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(MonetaCurrency(rawValue: groupDisplayCurrency)?.symbol ?? groupDisplayCurrency)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
        }
    }
    
    private var accountsAccordion: some View {
        VStack(spacing: 0) {
            let displayAccounts: [(account: FinanceAccount, info: (name: String, amount: Double, currency: String, icon: String, isCreditCardDebt: Bool))] = (group.accounts ?? []).compactMap { account in
                guard let info = viewModel.getAccountInfo(account: account) else {
                    return nil
                }
                return (account: account, info: info)
            }

            if displayAccounts.isEmpty {
                Text("finances.main.empty_products.title")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
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
                            .background(Color.white.opacity(0.14))
                            .padding(.leading, 64)
                            .padding(.trailing, 18)
                    }
                }
            }
        }
        .padding(.bottom, 14)
    }
    
    private var groupBackground: some View {
        let accentColor = group.color
        let fillGradient = LinearGradient(
            colors: [
                Color.white.opacity(0.07),
                Color.white.opacity(0.035),
                Color.white.opacity(0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(fillGradient)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.18),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .blendMode(.screen)
            }
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        // Открыть группу (динамика)
        Button {
            viewModel.handle(.showGroupDynamics(group))
        } label: {
            Label("finances.group.menu.open", systemImage: "chart.line.uptrend.xyaxis")
        }
        
        // Избранное
        Button {
            viewModel.handle(.toggleGroupFavorite(group))
        } label: {
            Label(
                group.isFavorite ? String(localized: "finances.group.menu.unfavorite") : String(localized: "finances.group.menu.favorite"),
                systemImage: group.isFavorite ? "star.fill" : "star"
            )
        }
        
        // Приоритет
        Button {
            viewModel.handle(.setGroupPriority(group, nextPriority))
        } label: {
            Label(
                FinancesL10n.format("finances.group.menu.priority", priorityDisplayName),
                systemImage: priorityIcon
            )
        }
        
        // Редактирование
        Button {
            viewModel.handle(.editGroup(group))
        } label: {
            Label("finances.common.edit", systemImage: "pencil")
        }
        
        // Удаление
        Button(role: .destructive) {
            viewModel.handle(.deleteGroup(group))
        } label: {
            Label("finances.common.delete", systemImage: "trash")
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
    let accountType: FinanceAccountType
    let isCreditCardDebt: Bool
    let onEdit: () -> Void
    let onQuickEditAmount: () -> Void
    
    var body: some View {
        if viewModel.getMarketInvestment(account: account) != nil {
            marketInvestmentRow
        } else {
            defaultRow
        }
    }

    private var defaultRow: some View {
        HStack(spacing: 12) {
            iconBadge(
                colors: isDebtHighlighted ? [AppColors.error, AppColors.error] : AppColors.financesGradient
            )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle = viewModel.getInvestmentPositionSubtitle(account: account) {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let limitSubtitle = creditLimitSubtitle {
                    Text(limitSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary.opacity(0.9))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            trailingAmountSection(
                amountFont: .system(size: 16, weight: .semibold),
                currencyFont: .system(size: 16, weight: .semibold),
                maximumFractionDigits: 0
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }

    private var marketInvestmentRow: some View {
        HStack(spacing: 12) {
            iconBadge(
                colors: isDebtHighlighted ? [AppColors.error, AppColors.error] : AppColors.financesGradient
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle = viewModel.getInvestmentPositionSubtitle(account: account) {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if let performance = viewModel.getInvestmentPurchaseGrowthSubtitle(account: account) {
                    Text(performance.text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(performance.isPositive ? Color.green : AppColors.error)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingAmountSection(
                amountFont: .system(size: 17, weight: .semibold),
                currencyFont: .system(size: 17, weight: .semibold),
                maximumFractionDigits: 2
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }

    private var isDebtHighlighted: Bool {
        accountType == .credit || isCreditCardDebt || viewModel.isAccountLiabilityForTotals(account: account)
    }

    @ViewBuilder
    private func iconBadge(colors: [Color]) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 34, height: 34)
    }

    @ViewBuilder
    private func trailingAmountSection(
        amountFont: Font,
        currencyFont: Font,
        maximumFractionDigits: Int
    ) -> some View {
        let amountColor = isDebtHighlighted ? AppColors.error : (amount >= 0 ? AppColors.textPrimary : AppColors.error)
        Button {
            onQuickEditAmount()
        } label: {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatBalance(amount, isHidden: viewModel.state.isAmountHidden, maximumFractionDigits: maximumFractionDigits))
                        .font(amountFont)
                        .foregroundStyle(amountColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(MonetaCurrency(rawValue: currency)?.symbol ?? currency)
                        .font(currencyFont)
                        .foregroundStyle(amountColor)
                        .lineLimit(1)
                }
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
