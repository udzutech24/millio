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
        case .high: return "Высокий"
        case .normal: return "Обычный"
        case .low: return "Низкий"
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
            if let accounts = group.accounts, !accounts.isEmpty {
                ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                    if let accountInfo = viewModel.getAccountInfo(account: account) {
                        FinanceAccountRow(
                            viewModel: viewModel,
                            account: account,
                            name: accountInfo.name,
                            amount: accountInfo.amount,
                            currency: accountInfo.currency,
                            icon: accountInfo.icon,
                            accountType: account.accountType,
                            isCreditCardDebt: accountInfo.isCreditCardDebt,
                            onEdit: {
                                viewModel.handle(.showAccountDynamics(account))
                            },
                            onQuickEditAmount: {
                                viewModel.handle(.showQuickEditAccountSheet(account))
                            }
                        )
                        
                        if index != accounts.count - 1 {
                            Divider()
                                .background((AppColors.financesGradient.last ?? AppColors.textTertiary).opacity(0.35))
                                .padding(.leading, 56)
                        }
                    }
                }
            } else {
                Text("Создайте продукт")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
        }
        .padding(.bottom, 14)
    }
    
    private var groupBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                (AppColors.financesGradient.last ?? .cyan).opacity(0.08),
                                (AppColors.financesGradient.first ?? .blue).opacity(0.04),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            }
          
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        // Открыть группу (динамика)
        Button {
            viewModel.handle(.showGroupDynamics(group))
        } label: {
            Label("Открыть группу", systemImage: "chart.line.uptrend.xyaxis")
        }
        
        // Избранное
        Button {
            viewModel.handle(.toggleGroupFavorite(group))
        } label: {
            Label(
                group.isFavorite ? "Убрать из избранного" : "В избранное",
                systemImage: group.isFavorite ? "star.fill" : "star"
            )
        }
        
        // Приоритет
        Button {
            viewModel.handle(.setGroupPriority(group, nextPriority))
        } label: {
            Label(
                "Приоритет: \(priorityDisplayName)",
                systemImage: priorityIcon
            )
        }
        
        // Редактирование
        Button {
            viewModel.handle(.editGroup(group))
        } label: {
            Label("Редактировать", systemImage: "pencil")
        }
        
        // Удаление
        Button(role: .destructive) {
            viewModel.handle(.deleteGroup(group))
        } label: {
            Label("Удалить", systemImage: "trash")
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
        HStack(spacing: 12) {
            let iconGradientColors = (accountType == .credit || isCreditCardDebt) ? [AppColors.error, AppColors.error] : AppColors.financesGradient
            
            ZStack {
//                RoundedRectangle(cornerRadius: 10, style: .continuous)
//                    .fill(Color.white.opacity(0.06))
//                    .overlay {
//                        RoundedRectangle(cornerRadius: 10, style: .continuous)
//                            .stroke(
//                                LinearGradient(
//                                    colors: iconGradientColors,
//                                    startPoint: .topLeading,
//                                    endPoint: .bottomTrailing
//                                ),
//                                lineWidth: 1
//                            )
//                    }
//                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: iconGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 16, height: 16)
            
            // Название счета
            Text(name)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Сумма (кликабельна для быстрого редактирования)
            Button {
                onQuickEditAmount()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatBalance(amount, isHidden: viewModel.state.isAmountHidden))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(isCreditCardDebt ? AppColors.error : (amount >= 0 ? AppColors.textPrimary : AppColors.error))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Text(MonetaCurrency(rawValue: currency)?.symbol ?? currency)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
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
