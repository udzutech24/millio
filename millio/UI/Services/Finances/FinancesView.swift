//
//  FinancesView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData

private struct FinancesSectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(AppColors.textPrimary.opacity(0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }
}

private struct FinancesGlassCard<Content: View>: View {
    let contentPadding: EdgeInsets
    let content: Content
    
    init(
        contentPadding: EdgeInsets = EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
        @ViewBuilder content: () -> Content
    ) {
        self.contentPadding = contentPadding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(contentPadding)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    }
            }
            .shadow(color: (AppColors.financesGradient.last ?? .cyan).opacity(0.18), radius: 18, x: 0, y: 10)
    }
}

private struct FinancesRowDivider: View {
    let leadingPadding: CGFloat
    
    init(leadingPadding: CGFloat = 0) {
        self.leadingPadding = leadingPadding
    }
    
    var body: some View {
        Divider()
            .background(Color.white.opacity(0.14))
            .padding(.leading, leadingPadding)
    }
}

private struct FinancesSelectionRow: View {
    let title: String
    let isSelected: Bool
    let leadingIcon: String?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let leadingIcon {
                    Image(systemName: leadingIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 22)
                }
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.financesGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

private struct FinancesCheckboxOption: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isSelected
                            ? LinearGradient(colors: AppColors.financesGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.2
                    )
                    .frame(width: 18, height: 18)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(LinearGradient(colors: AppColors.financesGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct FinancesRadioOption: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Circle()
                    .stroke(
                        isSelected
                            ? LinearGradient(colors: AppColors.financesGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.2
                    )
                    .frame(width: 18, height: 18)
                    .overlay {
                        if isSelected {
                            Circle()
                                .fill(LinearGradient(colors: AppColors.financesGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 10, height: 10)
                        }
                    }
                
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Finances Tab Enum

enum FinancesTab: String {
    case main = "main"
    case dynamics = "dynamics"
}

struct FinancesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: FinanceViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                FinancesContentViewInternal(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = FinanceViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Internal Content View

private struct FinancesContentViewInternal: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var selectedTab: FinancesTab = .main
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Вкладка 1: Основной экран
            FinancesMainTabView(viewModel: viewModel)
                .tabItem {
                    Label("Финансы", systemImage: "creditcard")
                }
                .tag(FinancesTab.main)
            
            // Вкладка 2: Динамика
            FinanceDynamicsTabView(financeViewModel: viewModel)
                .tabItem {
                    Label("Динамика", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(FinancesTab.dynamics)
        }
        .task {
            await viewModel.refreshRates()
        }
    }
}

// MARK: - Finances Main Tab View

private struct FinancesMainTabView: View {
    @ObservedObject var viewModel: FinanceViewModel
    
    var body: some View {
        mainContent
            .modifier(SheetsModifier(viewModel: viewModel))
    }
    
    private var mainContent: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Общая сумма
                    totalAmountSection
                    
                    // Список групп
                    groupsListSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 100) // Дополнительный отступ снизу для FAB
            }
            
            // Floating Action Button (FAB) внизу справа
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        viewModel.handle(.showAddAccountSheet(nil))
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
    }
    
    // MARK: - Total Amount Section
    
    private var totalAmountSection: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Button {
                        viewModel.handle(.showDisplayCurrencySheet)
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.state.displayCurrency)
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.financesGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    }
                    
                    if let secondaryCurrency = viewModel.state.secondaryDisplayCurrency {
                        Button {
                            viewModel.handle(.showSecondaryDisplayCurrencySheet)
                        } label: {
                            HStack(spacing: 4) {
                                Text(secondaryCurrency)
                                    .font(.system(size: 12, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .foregroundStyle(AppColors.textTertiary)
                        }
                    } else {
                        Button {
                            viewModel.handle(.showSecondaryDisplayCurrencySheet)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Доп. валюта")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    
                    Button {
                        viewModel.handle(.showSavingsGoalSheet)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                
                Spacer()
                
                Button {
                    viewModel.handle(.toggleAmountVisibility)
                } label: {
                    Image(systemName: viewModel.state.isAmountHidden ? "eye.slash" : "eye")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: AppColors.financesGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formatBalance(viewModel.state.totalAmount, isHidden: viewModel.state.isAmountHidden))
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    
                    Text(currencyDisplay(viewModel.state.displayCurrency))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                        .lineLimit(1)
                }
                
                if let secondaryCurrency = viewModel.state.secondaryDisplayCurrency, viewModel.state.secondaryTotalAmount > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formatBalance(viewModel.state.secondaryTotalAmount, isHidden: viewModel.state.isAmountHidden))
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                        
                        Text(currencyDisplay(secondaryCurrency))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }

            if let warning = viewModel.state.currencyConversionWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.warning)

                    Text("Выбранная API не поддерживает часть валют, поэтому итоговые суммы могут быть неполными.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(3)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.warning.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppColors.warning.opacity(0.4), lineWidth: 1)
                }
                .accessibilityLabel(Text(warning))
            }
            
            // Полоса прогресса цели накопления
            if viewModel.state.isSavingsGoalEnabled && viewModel.state.savingsGoalAmount > 0 {
                VStack(spacing: 8) {
                    let progress: Double = {
                        let savingsGoal = viewModel.state.savingsGoalAmount
                        guard savingsGoal > 0 else { return 0.0 }
                        let calculated = viewModel.state.totalAmount / savingsGoal
                        guard calculated.isFinite else { return 0.0 }
                        return max(0.0, min(1.0, calculated))
                    }()
                    let displayCurrency = currencyDisplay(viewModel.state.displayCurrency)
                    let totalText = formatBalance(viewModel.state.totalAmount, isHidden: viewModel.state.isAmountHidden)
                    let goalText = formatBalance(viewModel.state.savingsGoalAmount, isHidden: viewModel.state.isAmountHidden)
                    
                    goalProgressBar(progress: progress)
                    
                    HStack {
                        Text("\(totalText) \(displayCurrency) из \(goalText) \(displayCurrency)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.financesGradient.first ?? AppColors.brandPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        
                        Spacer()
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
                .padding(.top, 4)
            }
            
            if viewModel.state.isLoadingRates {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(AppColors.textTertiary)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: AppColors.financesGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
        }
        .shadow(color: AppColors.financesGradient.last?.opacity(0.18) ?? .clear, radius: 18, x: 0, y: 10)
    }
    
    // MARK: - Groups List Section
    
    private var groupsListSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Группы")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                if !viewModel.state.groups.isEmpty {
                    Text("\(viewModel.state.groups.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            
            if viewModel.state.groups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("Нет групп")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Создайте первую группу")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                groupsListView
            }
        }
    }
    
    private var groupsListView: some View {
        VStack(spacing: 12) {
            ForEach(0..<viewModel.state.groups.count, id: \.self) { index in
                Group {
                    let group = viewModel.state.groups[index]
                    FinanceGroupRow(
                        group: group,
                        viewModel: viewModel
                    )
                }
            }
        }
    }
    
    // MARK: - Helpers
    
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
    
    private func currencyDisplay(_ code: String) -> String {
        switch code.uppercased() {
        case "RUB": "₽"
        case "USD": "$"
        case "EUR": "€"
        case "GBP": "£"
        case "CNY": "¥"
        default: code
        }
    }
    
    private func goalProgressBar(progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, proxy.size.width * progress))
            }
        }
        .frame(height: 10)
    }
}

// MARK: - Finance Dynamics Tab View

private struct FinanceDynamicsTabView: View {
    @ObservedObject var financeViewModel: FinanceViewModel
    
    var body: some View {
        FinanceDynamicsView(
            financeViewModel: financeViewModel,
            wrapInNavigationStack: false
        )
    }
}

// MARK: - Finance Group Row

private struct FinanceGroupRow: View {
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
                .shadow(color: group.color.opacity(0.6), radius: 10, x: 0, y: 0)
            
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
            if group.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.incomeGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            Text(group.name)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var groupAmountSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(formatBalance(groupTotal, isHidden: viewModel.state.isAmountHidden))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(currencyDisplay(groupDisplayCurrency))
                .font(.system(size: 16, weight: .semibold))
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
                Text("Нет счетов")
                    .font(.system(size: 14, weight: .regular))
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
                        lineWidth: 1.5
                    )
            }
            .shadow(color: (AppColors.financesGradient.last ?? .cyan).opacity(0.22), radius: 26, x: 0, y: 16)
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
    
    private func currencyDisplay(_ code: String) -> String {
        switch code.uppercased() {
        case "RUB": "₽"
        case "USD": "$"
        case "EUR": "€"
        case "GBP": "£"
        case "CNY": "¥"
        default: code
        }
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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: iconGradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                
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
            .frame(width: 34, height: 34)
            
            // Название счета
            Text(name)
                .font(.system(size: 16, weight: .medium))
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
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isCreditCardDebt ? AppColors.error : (amount >= 0 ? AppColors.textPrimary : AppColors.error))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Text(currencyDisplay(currency))
                        .font(.system(size: 12, weight: .semibold))
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
    
    private func currencyDisplay(_ code: String) -> String {
        switch code.uppercased() {
        case "RUB": "₽"
        case "USD": "$"
        case "EUR": "€"
        case "GBP": "£"
        case "CNY": "¥"
        default: code
        }
    }
}

// MARK: - Sheets Modifier

private struct SheetsModifier: ViewModifier {
    @ObservedObject var viewModel: FinanceViewModel
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { viewModel.state.showGroupEditor },
                set: { if !$0 { viewModel.handle(.hideGroupEditor) } }
            )) {
                FinanceGroupEditorView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showAddAccountSheet },
                set: { if !$0 { viewModel.handle(.hideAddAccountSheet) } }
            )) {
                FinanceAddAccountView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showCreateCardSheet },
                set: { if !$0 { viewModel.handle(.hideCreateCardSheet) } }
            )) {
                FinanceCreateCardView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showCreateCreditSheet },
                set: { if !$0 { viewModel.handle(.hideCreateCreditSheet) } }
            )) {
                FinanceCreateCreditView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showCreateInvestmentSheet },
                set: { if !$0 { viewModel.handle(.hideCreateInvestmentSheet) } }
            )) {
                FinanceCreateInvestmentView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showDisplayCurrencySheet },
                set: { if !$0 { viewModel.handle(.hideDisplayCurrencySheet) } }
            )) {
                DisplayCurrencySheet(viewModel: viewModel, isSecondary: false)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showSecondaryDisplayCurrencySheet },
                set: { if !$0 { viewModel.handle(.hideSecondaryDisplayCurrencySheet) } }
            )) {
                DisplayCurrencySheet(viewModel: viewModel, isSecondary: true)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showEditCardSheet },
                set: { if !$0 { viewModel.handle(.hideEditCardSheet) } }
            )) {
                if let cardID = viewModel.state.editingCardID,
                   let card = viewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID }) {
                    FinanceEditCardView(card: card, viewModel: viewModel)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showEditCreditSheet },
                set: { if !$0 { viewModel.handle(.hideEditCreditSheet) } }
            )) {
                if let creditID = viewModel.state.editingCreditID,
                   let credit = viewModel.state.availableCredits.first(where: { $0.creditUniqueID == creditID }) {
                    FinanceEditCreditView(credit: credit, viewModel: viewModel)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showEditInvestmentSheet },
                set: { if !$0 { viewModel.handle(.hideEditInvestmentSheet) } }
            )) {
                if let investmentID = viewModel.state.editingInvestmentID,
                   let investment = viewModel.state.availableInvestments.first(where: { $0.investmentUniqueID == investmentID }) {
                    FinanceEditInvestmentView(investment: investment, viewModel: viewModel)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showQuickEditAccountSheet },
                set: { if !$0 { viewModel.handle(.hideQuickEditAccountSheet) } }
            )) {
                if let account = viewModel.state.quickEditAccount {
                    FinanceQuickEditAccountView(account: account, viewModel: viewModel)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showGroupDynamics },
                set: { if !$0 { viewModel.handle(.hideGroupDynamics) } }
            )) {
                if let group = viewModel.state.selectedGroupForDynamics {
                    FinanceDynamicsView(
                        financeViewModel: viewModel,
                        initialGroupID: group.groupUniqueID,
                        initialGroupCurrency: group.displayCurrency
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showAccountDynamics },
                set: { if !$0 { viewModel.handle(.hideAccountDynamics) } }
            )) {
                if let account = viewModel.state.selectedAccountForDynamics {
                    FinanceDynamicsView(
                        financeViewModel: viewModel,
                        initialAccountID: account.accountUniqueID,
                        initialAccountCurrency: viewModel.getAccountInfo(account: account)?.currency,
                        initialAccount: account
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showSavingsGoalSheet },
                set: { if !$0 { viewModel.handle(.hideSavingsGoalSheet) } }
            )) {
                SavingsGoalSettingsView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
    }
}

// MARK: - Finance Group Editor View

private struct FinanceGroupEditorView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var selectedColor: Color = Color.blue
    @State private var selectedCurrency: String? = nil
    @State private var availableCurrencies: [String] = []
    @State private var isLoadingCurrencies = true
    @State private var isFavorite: Bool = false
    @State private var selectedPriority: GroupPriority = .normal
    
    private let predefinedColors: [Color] = [
        .blue, .cyan, .green, .mint, .purple, .pink,
        .indigo, .orange, .red, .yellow, .teal, .brown
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    Section {
                        TextField("Название группы", text: $name)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Основная информация")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            ForEach(predefinedColors, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                } label: {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 40, height: 40)
                                        .overlay {
                                            if selectedColor == color {
                                                Circle()
                                                    .stroke(AppColors.textPrimary, lineWidth: 3)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Цвет группы")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        if isLoadingCurrencies {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .tint(AppColors.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else {
                            Picker("Валюта отображения", selection: $selectedCurrency) {
                                Text("Использовать общую валюту")
                                    .tag(nil as String?)
                                ForEach(availableCurrencies, id: \.self) { currency in
                                    Text(currency)
                                        .tag(currency as String?)
                                }
                            }
                            .foregroundStyle(AppColors.textPrimary)
                        }
                    } header: {
                        Text("Валюта отображения")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        Toggle("В избранном", isOn: $isFavorite)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Picker("Приоритет", selection: $selectedPriority) {
                            ForEach(GroupPriority.allCases, id: \.self) { priority in
                                Text(priority.displayName).tag(priority)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Дополнительно")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    // Показываем список счетов только при редактировании группы
                    if let editingGroup = viewModel.state.editingGroup,
                       let accounts = editingGroup.accounts,
                       !accounts.isEmpty {
                        Section {
                            ForEach(accounts) { account in
                                if let accountInfo = viewModel.getAccountInfo(account: account) {
                                    HStack {
                                        // Иконка счета
                                        Image(systemName: accountInfo.icon)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: AppColors.financesGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: 24, height: 24)
                                        
                                        // Название и сумма счета
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(accountInfo.name)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(AppColors.textPrimary)
                                            
                                            HStack(spacing: 4) {
                                                Text(formatAmount(accountInfo.amount, isHidden: viewModel.state.isAmountHidden))
                                                    .font(.system(size: 12, weight: .regular))
                                                    .foregroundStyle(accountInfo.isCreditCardDebt ? AppColors.error : AppColors.textSecondary)
                                                
                                                Text(accountInfo.currency)
                                                    .font(.system(size: 12, weight: .regular))
                                                    .foregroundStyle(AppColors.textSecondary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        // Кнопка удаления
                                        Button {
                                            viewModel.handle(.removeAccountFromGroup(account))
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundStyle(AppColors.error)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } header: {
                            Text("Счета группы")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(viewModel.state.editingGroup == nil ? "Новая группа" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        saveGroup()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let editing = viewModel.state.editingGroup {
                    name = editing.name
                    selectedCurrency = editing.displayCurrency
                    isFavorite = editing.isFavorite
                    selectedPriority = editing.priority
                    // Находим соответствующий цвет из predefinedColors по hex-значению
                    let editingColorHex = editing.colorHex.uppercased()
                    if let matchingColor = predefinedColors.first(where: { color in
                        color.toHex().uppercased() == editingColorHex
                    }) {
                        selectedColor = matchingColor
                    } else {
                        // Если точного совпадения нет, используем цвет из группы
                        selectedColor = editing.color
                    }
                }
            }
            .task {
                await loadAvailableCurrencies()
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty
    }
    
    private func saveGroup() {
        let colorHex = selectedColor.toHex()
        viewModel.handle(.updateGroup(name: name, colorHex: colorHex, displayCurrency: selectedCurrency, isFavorite: isFavorite, priority: selectedPriority))
        dismiss()
    }
    
    private func loadAvailableCurrencies() async {
        isLoadingCurrencies = true
        defer { isLoadingCurrencies = false }
        
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        
        let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
        let fromAccounts = Set(
            viewModel.state.availableCards.map { $0.currency } +
            viewModel.state.availableCredits.map { $0.currency } +
            viewModel.state.availableInvestments.map { $0.currency }
        )
        availableCurrencies = Array(fromRateSource.union(fromAccounts)).sorted()
    }
    
    private func formatAmount(_ amount: Double, isHidden: Bool = false) -> String {
        if isHidden {
            // Подсчитываем количество цифр в числе
            let digits = Int(amount.rounded())
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
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }
}

// MARK: - Finance Add Account View

private struct FinanceAddAccountView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    private enum AddAccountMode: String, CaseIterable, Identifiable {
        case create
        case archived
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .create:
                "Создать"
            case .archived:
                "Из архива"
            }
        }
    }
    
    @State private var selectedAccountType: FinanceAccountType = .card
    @State private var addAccountMode: AddAccountMode = .create
    @State private var selectedGroupID: String? = nil
    @State private var showCreateGroup = false
    @State private var cardViewModel: CardViewModel?
    @State private var creditViewModel: CreditViewModel?
    @State private var investmentViewModel: InvestmentViewModel?
    @State private var cardData: Card?
    @State private var creditData: (name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, includeInTotal: Bool)?
    @State private var investmentData: (name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool)?
    @State private var selectedArchivedAccountID: String? = nil
    
    var targetGroup: FinanceGroup? {
        if let selectedGroupID = selectedGroupID {
            return viewModel.state.groups.first { group in
                group.groupUniqueID == selectedGroupID
            }
        }
        return viewModel.state.selectedGroupForAccount
    }
    
    // MARK: - Form Sections
    
    private var accountTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Тип продукта")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    ForEach(FinanceAccountType.allCases, id: \.self) { type in
                        Button {
                            selectedAccountType = type
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .frame(width: 22)
                                
                                Text(type.displayName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                
                                Spacer()
                                
                                if selectedAccountType == type {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.financesGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        
                        if type != FinanceAccountType.allCases.last {
                            FinancesRowDivider(leadingPadding: 50)
                        }
                    }
                }
            }
        }
    }
    
    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Группа")
            
            if viewModel.state.groups.isEmpty {
                FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                    VStack(spacing: 12) {
                        Text("Сначала создайте группу")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Button {
                            showCreateGroup = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.plus")
                                Text("Создать группу")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                    }
                }
            } else {
                let currentGroupID = selectedGroupID ?? viewModel.state.selectedGroupForAccount?.groupUniqueID ?? viewModel.state.groups.first?.groupUniqueID ?? ""
                
                FinancesGlassCard {
                    VStack(spacing: 0) {
                        ForEach(viewModel.state.groups) { group in
                            Button {
                                selectedGroupID = group.groupUniqueID
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(group.color)
                                        .frame(width: 12, height: 12)
                                        .shadow(color: group.color.opacity(0.4), radius: 8, x: 0, y: 0)
                                    
                                    Text(group.name)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    
                                    Spacer()
                                    
                                    if currentGroupID == group.groupUniqueID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: AppColors.financesGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                            
                            if group.groupUniqueID != viewModel.state.groups.last?.groupUniqueID {
                                FinancesRowDivider(leadingPadding: 40)
                            }
                        }
                    }
                }
                
                Button {
                    showCreateGroup = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                        Text("Создать новую группу")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
                .padding(.top, 4)
            }
        }
    }
    
    private var addAccountModeSection: some View {
        Group {
            if viewModel.state.hasArchivedAccounts {
                VStack(alignment: .leading, spacing: 10) {
                    FinancesSectionHeader(title: "Режим")
                    FinancesGlassCard(contentPadding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
                        Picker("Режим", selection: $addAccountMode) {
                            ForEach(AddAccountMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var createFormSections: some View {
        switch selectedAccountType {
        case .card:
            if cardViewModel == nil {
                VStack(alignment: .leading, spacing: 10) {
                    FinancesSectionHeader(title: "Создать карту")
                    FinancesGlassCard(contentPadding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)) {
                        ProgressView()
                            .tint(AppColors.textPrimary)
                            .task {
                                let vm = CardViewModel(modelContext: modelContext)
                                vm.handle(.addCard)
                                cardViewModel = vm
                            }
                    }
                }
                groupSection
            } else if let vm = cardViewModel {
                InlineCardCreateForm(
                    viewModel: vm,
                    onCardDataChanged: { card in
                        self.cardData = card
                    }
                ) {
                    groupSection
                }
            }
        case .credit:
            if creditViewModel == nil {
                VStack(alignment: .leading, spacing: 10) {
                    FinancesSectionHeader(title: "Создать кредит")
                    FinancesGlassCard(contentPadding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)) {
                        ProgressView()
                            .tint(AppColors.textPrimary)
                            .task {
                                let vm = CreditViewModel(modelContext: modelContext)
                                vm.handle(.addCredit)
                                creditViewModel = vm
                            }
                    }
                }
                groupSection
            } else if let vm = creditViewModel {
                InlineCreditCreateForm(
                    viewModel: vm,
                    onCreditDataChanged: { data in
                        self.creditData = data
                    }
                ) {
                    groupSection
                }
            }
        case .investment:
            if investmentViewModel == nil {
                VStack(alignment: .leading, spacing: 10) {
                    FinancesSectionHeader(title: "Создать актив")
                    FinancesGlassCard(contentPadding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)) {
                        ProgressView()
                            .tint(AppColors.textPrimary)
                            .task {
                                let vm = InvestmentViewModel(modelContext: modelContext)
                                vm.handle(.addInvestment)
                                investmentViewModel = vm
                            }
                    }
                }
                groupSection
            } else if let vm = investmentViewModel {
                InlineInvestmentCreateForm(
                    viewModel: vm,
                    onInvestmentDataChanged: { data in
                        self.investmentData = data
                    }
                ) {
                    groupSection
                }
            }
        }
    }

    @ViewBuilder
    private var archivedSelectionSections: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Выбрать из архива")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    switch selectedAccountType {
                    case .card:
                        if viewModel.state.archivedCards.isEmpty {
                            Text("Нет архивных карт")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(AppColors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 16)
                        } else {
                            ForEach(viewModel.state.archivedCards) { card in
                                FinancesSelectionRow(
                                    title: card.name,
                                    isSelected: selectedArchivedAccountID == card.cardUniqueID,
                                    leadingIcon: nil,
                                    onTap: { selectedArchivedAccountID = card.cardUniqueID }
                                )
                                if card.cardUniqueID != viewModel.state.archivedCards.last?.cardUniqueID {
                                    FinancesRowDivider(leadingPadding: 16)
                                }
                            }
                        }
                        
                    case .credit:
                        if viewModel.state.archivedCredits.isEmpty {
                            Text("Нет архивных кредитов")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(AppColors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 16)
                        } else {
                            ForEach(viewModel.state.archivedCredits) { credit in
                                FinancesSelectionRow(
                                    title: credit.name,
                                    isSelected: selectedArchivedAccountID == credit.creditUniqueID,
                                    leadingIcon: nil,
                                    onTap: { selectedArchivedAccountID = credit.creditUniqueID }
                                )
                                if credit.creditUniqueID != viewModel.state.archivedCredits.last?.creditUniqueID {
                                    FinancesRowDivider(leadingPadding: 16)
                                }
                            }
                        }
                        
                    case .investment:
                        if viewModel.state.archivedInvestments.isEmpty {
                            Text("Нет архивных активов")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(AppColors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 16)
                        } else {
                            ForEach(viewModel.state.archivedInvestments) { investment in
                                FinancesSelectionRow(
                                    title: investment.name,
                                    isSelected: selectedArchivedAccountID == investment.investmentUniqueID,
                                    leadingIcon: nil,
                                    onTap: { selectedArchivedAccountID = investment.investmentUniqueID }
                                )
                                if investment.investmentUniqueID != viewModel.state.archivedInvestments.last?.investmentUniqueID {
                                    FinancesRowDivider(leadingPadding: 16)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        groupSection
    }
    
    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                accountTypeSection
                addAccountModeSection
                if addAccountMode == .create {
                    createFormSections
                } else {
                    archivedSelectionSections
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }
    
    @ViewBuilder
    private var navigationContent: some View {
        ZStack {
            GradientBackground()
            scrollContent
        }
        .navigationTitle("Новый продукт")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreateGroup) {
            FinanceGroupEditorView(viewModel: viewModel)
                .onDisappear {
                    viewModel.handle(.loadGroups)
                    if let newGroup = viewModel.state.groups.last {
                        selectedGroupID = newGroup.groupUniqueID
                    }
                }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Отмена") { dismiss() }
                    .foregroundStyle(AppColors.textPrimary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Добавить") { addAccount() }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
            }
        }
        .onAppear {
            if let preselectedGroup = viewModel.state.selectedGroupForAccount {
                selectedGroupID = preselectedGroup.groupUniqueID
            } else if let firstGroup = viewModel.state.groups.first {
                selectedGroupID = firstGroup.groupUniqueID
            }
            viewModel.handle(.loadAccounts)
        }
    }
    
    var body: some View {
        NavigationStack {
            navigationContent
                .modifier(SelectedAccountTypeChangeHandler(selectedAccountType: $selectedAccountType, cardViewModel: $cardViewModel, creditViewModel: $creditViewModel, investmentViewModel: $investmentViewModel, selectedArchivedAccountID: $selectedArchivedAccountID))
                .onChange(of: addAccountMode) { _, newValue in
                    if newValue == .create {
                        selectedArchivedAccountID = nil
                    }
                }
        }
    }
    
    private var isValid: Bool {
        guard targetGroup != nil else { return false }

        if addAccountMode == .archived {
            return selectedArchivedAccountID != nil
        }
        
        switch selectedAccountType {
        case .card:
            return cardData != nil && !(cardData?.name.isEmpty ?? true)
        case .credit:
            return creditData != nil && !(creditData?.name.isEmpty ?? true)
        case .investment:
            return investmentData != nil && !(investmentData?.name.isEmpty ?? true)
        }
    }
    
    private func addAccount() {
        guard let targetGroup = targetGroup else { return }

        if addAccountMode == .archived {
            guard let archivedAccountID = selectedArchivedAccountID else { return }
            viewModel.handle(.restoreArchivedAccountToGroup(
                accountType: selectedAccountType,
                accountID: archivedAccountID,
                group: targetGroup
            ))
            dismiss()
            return
        }
        
        switch selectedAccountType {
        case .card:
            if let cardViewModel = cardViewModel {
                // Получаем данные из формы и создаем карту
                createCardAndAddToGroup(cardViewModel: cardViewModel, group: targetGroup)
                return
            }
        case .credit:
            if let creditViewModel = creditViewModel {
                createCreditAndAddToGroup(creditViewModel: creditViewModel, group: targetGroup)
                return
            }
        case .investment:
            if let investmentViewModel = investmentViewModel {
                createInvestmentAndAddToGroup(investmentViewModel: investmentViewModel, group: targetGroup)
                return
            }
        }
    }
    
    private func createCardAndAddToGroup(cardViewModel: CardViewModel, group: FinanceGroup) {
        guard let cardData = cardData else { return }
        
        if cardData.uniqueID.isEmpty {
            cardData.uniqueID = UUID().uuidString
        }
        
        let createdCardID = cardData.cardUniqueID
        
        // Создаем карту из данных формы
        cardViewModel.handle(.updateCard(cardData))
        
        guard cardViewModel.state.cards.contains(where: { $0.cardUniqueID == createdCardID }) else { return }
        
        viewModel.handle(.addAccountToGroup(
            accountType: .card,
            accountID: createdCardID,
            group: group
        ))
        dismiss()
    }
    
    private func createCreditAndAddToGroup(creditViewModel: CreditViewModel, group: FinanceGroup) {
        guard let creditData = creditData else { return }
        let createdCreditID = UUID().uuidString
        
        // Создаем кредит из данных формы
        creditViewModel.handle(.updateCredit(
            name: creditData.name,
            amount: creditData.amount,
            monthlyPayment: creditData.monthlyPayment,
            endDate: creditData.endDate,
            remainingAmount: creditData.remainingAmount,
            currency: creditData.currency,
            bank: creditData.bank,
            creditType: creditData.creditType,
            isFavorite: creditData.isFavorite,
            includeInTotal: creditData.includeInTotal,
            uniqueID: createdCreditID
        ))
        
        guard creditViewModel.state.credits.contains(where: { $0.creditUniqueID == createdCreditID }) else { return }
        
        viewModel.handle(.addAccountToGroup(
            accountType: .credit,
            accountID: createdCreditID,
            group: group
        ))
        dismiss()
    }
    
    private func createInvestmentAndAddToGroup(investmentViewModel: InvestmentViewModel, group: FinanceGroup) {
        guard let investmentData = investmentData else { return }
        let createdInvestmentID = UUID().uuidString
        
        // Создаем актив из данных формы
        investmentViewModel.handle(.updateInvestment(
            name: investmentData.name,
            investmentType: investmentData.investmentType,
            category: investmentData.category,
            amount: investmentData.amount,
            currency: investmentData.currency,
            includeInTotal: investmentData.includeInTotal,
            priority: investmentData.priority,
            isFavorite: investmentData.isFavorite,
            uniqueID: createdInvestmentID
        ))
        
        guard investmentViewModel.state.investments.contains(where: { $0.investmentUniqueID == createdInvestmentID }) else { return }
        
        viewModel.handle(.addAccountToGroup(
            accountType: .investment,
            accountID: createdInvestmentID,
            group: group
        ))
        dismiss()
    }
}

// MARK: - ViewModifier Helpers for FinanceAddAccountView

private struct SelectedAccountTypeChangeHandler: ViewModifier {
    @Binding var selectedAccountType: FinanceAccountType
    @Binding var cardViewModel: CardViewModel?
    @Binding var creditViewModel: CreditViewModel?
    @Binding var investmentViewModel: InvestmentViewModel?
    @Binding var selectedArchivedAccountID: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: selectedAccountType) { oldValue, newValue in
                if oldValue != newValue {
                    selectedArchivedAccountID = nil
                    // Сбрасываем viewModels при смене типа
                    switch oldValue {
                    case .card:
                        cardViewModel = nil
                    case .credit:
                        creditViewModel = nil
                    case .investment:
                        investmentViewModel = nil
                    }
                }
            }
    }
}

// MARK: - Finance Editor Wrappers
private struct FinanceCardEditorWrapper: View {
    @ObservedObject var cardViewModel: CardViewModel
    @Binding var showCreateCard: Bool
    let onCardCreated: (String) -> Void
    
    @State private var initialCardsCount: Int = 0
    @State private var wasNewCard: Bool = true
    @State private var initialCardIDs: Set<String> = []
    
    var body: some View {
        CardEditorView(viewModel: cardViewModel)
            .onAppear {
                initialCardsCount = cardViewModel.state.cards.count
                initialCardIDs = Set(cardViewModel.state.cards.map { $0.cardUniqueID })
                wasNewCard = cardViewModel.state.editingCard == nil
            }
            .onChange(of: cardViewModel.state.cards.count) { oldCount, newCount in
                if wasNewCard && newCount > initialCardsCount {
                    let newCards = cardViewModel.state.cards.filter { !initialCardIDs.contains($0.cardUniqueID) }
                    if let newCard = newCards.first {
                        onCardCreated(newCard.cardUniqueID)
                    }
                }
            }
    }
}

private struct FinanceCreditEditorWrapper: View {
    @ObservedObject var creditViewModel: CreditViewModel
    @Binding var showCreateCredit: Bool
    let onCreditCreated: (String) -> Void
    
    @State private var initialCreditsCount: Int = 0
    @State private var wasNewCredit: Bool = true
    @State private var initialCreditIDs: Set<String> = []
    
    var body: some View {
        CreditEditorView(viewModel: creditViewModel)
            .onAppear {
                initialCreditsCount = creditViewModel.state.credits.count
                initialCreditIDs = Set(creditViewModel.state.credits.map { $0.creditUniqueID })
                wasNewCredit = creditViewModel.state.editingCredit == nil
            }
            .onChange(of: creditViewModel.state.credits.count) { oldCount, newCount in
                if wasNewCredit && newCount > initialCreditsCount {
                    let newCredits = creditViewModel.state.credits.filter { !initialCreditIDs.contains($0.creditUniqueID) }
                    if let newCredit = newCredits.first {
                        onCreditCreated(newCredit.creditUniqueID)
                    }
                }
            }
    }
}

private struct FinanceInvestmentEditorWrapper: View {
    @ObservedObject var investmentViewModel: InvestmentViewModel
    @Binding var showCreateInvestment: Bool
    let onInvestmentCreated: (String) -> Void
    
    @State private var initialInvestmentsCount: Int = 0
    @State private var wasNewInvestment: Bool = true
    @State private var initialInvestmentIDs: Set<String> = []
    
    var body: some View {
        InvestmentEditorView(viewModel: investmentViewModel)
            .onAppear {
                initialInvestmentsCount = investmentViewModel.state.investments.count
                initialInvestmentIDs = Set(investmentViewModel.state.investments.map { $0.investmentUniqueID })
                wasNewInvestment = investmentViewModel.state.editingInvestment == nil
            }
            .onChange(of: investmentViewModel.state.investments.count) { oldCount, newCount in
                if wasNewInvestment && newCount > initialInvestmentsCount {
                    let newInvestments = investmentViewModel.state.investments.filter { !initialInvestmentIDs.contains($0.investmentUniqueID) }
                    if let newInvestment = newInvestments.first {
                        onInvestmentCreated(newInvestment.investmentUniqueID)
                    }
                }
            }
    }
}

// MARK: - Finance Edit Views

struct FinanceEditCardView: View {
    let card: Card
    @ObservedObject var viewModel: FinanceViewModel
    let onClose: (() -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var cardViewModel: CardViewModel?

    init(
        card: Card,
        viewModel: FinanceViewModel,
        onClose: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.card = card
        self.viewModel = viewModel
        self.onClose = onClose
        self.onDelete = onDelete
    }
    
    var body: some View {
        Group {
            if let cardViewModel = cardViewModel {
                CardEditorView(viewModel: cardViewModel, onClose: onClose, onDelete: onDelete)
                    .onChange(of: cardViewModel.state.showCardEditor) { oldValue, newValue in
                        if oldValue == true && newValue == false {
                            viewModel.handle(.loadAccounts)
                            viewModel.handle(.loadGroups)
                            Task { await recalculateAllGroupTotals() }
                            if let onClose {
                                onClose()
                            } else {
                                dismiss()
                            }
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        cardViewModel = CardViewModel(modelContext: modelContext)
                        cardViewModel?.handle(.editCard(card))
                    }
            }
        }
    }
    
    private func recalculateAllGroupTotals() async {
        for group in viewModel.state.groups {
            let currency = group.displayCurrency ?? viewModel.state.displayCurrency
            let total = await viewModel.calculateGroupTotal(group: group, in: currency)
            viewModel.handle(.setGroupTotal(group.groupUniqueID, total))
        }
        await viewModel.calculateTotalAmountAsync()
    }
}

struct FinanceEditCreditView: View {
    let credit: Credit
    @ObservedObject var viewModel: FinanceViewModel
    let onClose: (() -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var creditViewModel: CreditViewModel?

    init(
        credit: Credit,
        viewModel: FinanceViewModel,
        onClose: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.credit = credit
        self.viewModel = viewModel
        self.onClose = onClose
        self.onDelete = onDelete
    }
    
    var body: some View {
        Group {
            if let creditViewModel = creditViewModel {
                CreditEditorView(viewModel: creditViewModel, onClose: onClose, onDelete: onDelete)
                    .onChange(of: creditViewModel.state.showCreditEditor) { oldValue, newValue in
                        if oldValue == true && newValue == false {
                            viewModel.handle(.loadAccounts)
                            viewModel.handle(.loadGroups)
                            Task { await recalculateAllGroupTotals() }
                            if let onClose {
                                onClose()
                            } else {
                                dismiss()
                            }
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        creditViewModel = CreditViewModel(modelContext: modelContext)
                        creditViewModel?.handle(.editCredit(credit))
                    }
            }
        }
    }
    
    private func recalculateAllGroupTotals() async {
        for group in viewModel.state.groups {
            let currency = group.displayCurrency ?? viewModel.state.displayCurrency
            let total = await viewModel.calculateGroupTotal(group: group, in: currency)
            viewModel.handle(.setGroupTotal(group.groupUniqueID, total))
        }
        await viewModel.calculateTotalAmountAsync()
    }
}

struct FinanceEditInvestmentView: View {
    let investment: Investment
    @ObservedObject var viewModel: FinanceViewModel
    let onClose: (() -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var investmentViewModel: InvestmentViewModel?

    init(
        investment: Investment,
        viewModel: FinanceViewModel,
        onClose: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.investment = investment
        self.viewModel = viewModel
        self.onClose = onClose
        self.onDelete = onDelete
    }
    
    var body: some View {
        Group {
            if let investmentViewModel = investmentViewModel {
                InvestmentEditorView(viewModel: investmentViewModel, onClose: onClose, onDelete: onDelete)
                    .onChange(of: investmentViewModel.state.showInvestmentEditor) { oldValue, newValue in
                        if oldValue == true && newValue == false {
                            viewModel.handle(.loadAccounts)
                            viewModel.handle(.loadGroups)
                            Task { await recalculateAllGroupTotals() }
                            if let onClose {
                                onClose()
                            } else {
                                dismiss()
                            }
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        investmentViewModel = InvestmentViewModel(modelContext: modelContext)
                        investmentViewModel?.handle(.editInvestment(investment))
                    }
            }
        }
    }
    
    private func recalculateAllGroupTotals() async {
        for group in viewModel.state.groups {
            let currency = group.displayCurrency ?? viewModel.state.displayCurrency
            let total = await viewModel.calculateGroupTotal(group: group, in: currency)
            viewModel.handle(.setGroupTotal(group.groupUniqueID, total))
        }
        await viewModel.calculateTotalAmountAsync()
    }
}

// MARK: - Finance Create Views

private struct FinanceCreateCardView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var cardViewModel: CardViewModel?
    @State private var createdCardID: String? = nil
    
    var body: some View {
        Group {
            if let cardViewModel = cardViewModel {
                CardEditorView(viewModel: cardViewModel)
                    .onChange(of: cardViewModel.state.editingCard) { oldValue, newValue in
                        if oldValue == nil && newValue != nil {
                            createdCardID = newValue?.cardUniqueID
                        }
                    }
                    .onDisappear {
                        if let cardID = createdCardID,
                           let targetGroup = viewModel.state.selectedGroupForAccount {
                            viewModel.handle(.addAccountToGroup(
                                accountType: .card,
                                accountID: cardID,
                                group: targetGroup
                            ))
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        cardViewModel = CardViewModel(modelContext: modelContext)
                        cardViewModel?.handle(.addCard)
                    }
            }
        }
    }
}

private struct FinanceCreateCreditView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var creditViewModel: CreditViewModel?
    @State private var createdCreditID: String? = nil
    
    var body: some View {
        Group {
            if let creditViewModel = creditViewModel {
                CreditEditorView(viewModel: creditViewModel)
                    .onChange(of: creditViewModel.state.editingCredit) { oldValue, newValue in
                        if oldValue == nil && newValue != nil {
                            createdCreditID = newValue?.creditUniqueID
                        }
                    }
                    .onDisappear {
                        if let creditID = createdCreditID,
                           let targetGroup = viewModel.state.selectedGroupForAccount {
                            viewModel.handle(.addAccountToGroup(
                                accountType: .credit,
                                accountID: creditID,
                                group: targetGroup
                            ))
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        creditViewModel = CreditViewModel(modelContext: modelContext)
                        creditViewModel?.handle(.addCredit)
                    }
            }
        }
    }
}

private struct FinanceCreateInvestmentView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var investmentViewModel: InvestmentViewModel?
    @State private var createdInvestmentID: String? = nil
    
    var body: some View {
        Group {
            if let investmentViewModel = investmentViewModel {
                InvestmentEditorView(viewModel: investmentViewModel)
                    .onChange(of: investmentViewModel.state.editingInvestment) { oldValue, newValue in
                        if oldValue == nil && newValue != nil {
                            createdInvestmentID = newValue?.investmentUniqueID
                        }
                    }
                    .onDisappear {
                        if let investmentID = createdInvestmentID,
                           let targetGroup = viewModel.state.selectedGroupForAccount {
                            viewModel.handle(.addAccountToGroup(
                                accountType: .investment,
                                accountID: investmentID,
                                group: targetGroup
                            ))
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        investmentViewModel = InvestmentViewModel(modelContext: modelContext)
                        investmentViewModel?.handle(.addInvestment)
                    }
            }
        }
    }
}

// MARK: - Display Currency Sheet

private struct DisplayCurrencySheet: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    var isSecondary: Bool = false
    @State private var availableCurrencies: [String] = []
    @State private var filteredCurrencies: [String] = []
    @State private var searchText: String = ""
    @State private var isLoading = true
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)
            TextField("Поиск валют", text: $searchText)
                .foregroundStyle(AppColors.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                if isLoading {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                } else {
                    VStack(spacing: 0) {
                        searchBar
                        
                        List {
                            ForEach(filteredCurrencies, id: \.self) { currency in
                                Button {
                                    if isSecondary {
                                        viewModel.handle(.setSecondaryDisplayCurrency(currency))
                                    } else {
                                        viewModel.handle(.setDisplayCurrency(currency))
                                    }
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(currency)
                                            .foregroundStyle(AppColors.textPrimary)
                                        Spacer()
                                        if isSecondary {
                                            if viewModel.state.secondaryDisplayCurrency == currency {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(
                                                        LinearGradient(
                                                            colors: AppColors.financesGradient,
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                            }
                                        } else {
                                            if viewModel.state.displayCurrency == currency {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(
                                                        LinearGradient(
                                                            colors: AppColors.financesGradient,
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                            }
                                        }
                                    }
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(isSecondary ? "Дополнительная валюта" : "Валюта отображения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.financesGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .task { await loadAvailableCurrencies() }
            .onChange(of: searchText) { _, _ in filterCurrencies() }
        }
    }
    
    private func loadAvailableCurrencies() async {
        isLoading = true
        defer { isLoading = false }
        
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        
        let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
        let fromAccounts = Set(
            viewModel.state.availableCards.map { $0.currency } +
            viewModel.state.availableCredits.map { $0.currency } +
            viewModel.state.availableInvestments.map { $0.currency }
        )
        availableCurrencies = Array(fromRateSource.union(fromAccounts)).sorted()
        filteredCurrencies = availableCurrencies
    }
    
    private func filterCurrencies() {
        if searchText.isEmpty {
            filteredCurrencies = availableCurrencies
        } else {
            filteredCurrencies = availableCurrencies.filter { currency in
                currency.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

// MARK: - Savings Goal Settings View

private struct SavingsGoalSettingsView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var isEnabled: Bool = false
    @State private var goalAmount: String = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    Section {
                        Toggle("Включить цель накопления", isOn: $isEnabled)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Настройки цели")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    if isEnabled {
                        Section {
                            TextField("Сумма цели", text: $goalAmount)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(AppColors.textPrimary)
                        } header: {
                            Text("Сумма цели (\(viewModel.state.displayCurrency))")
                                .foregroundStyle(AppColors.textSecondary)
                        } footer: {
                            if let amount = Double(goalAmount), amount > 0 {
                                let progress: Double = {
                                    guard amount > 0 else { return 0.0 }
                                    let calculated = viewModel.state.totalAmount / amount
                                    guard calculated.isFinite else { return 0.0 }
                                    return max(0.0, min(1.0, calculated))
                                }()
                                let remaining = max(0, amount - viewModel.state.totalAmount)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Текущая сумма: \(formatAmount(viewModel.state.totalAmount, isHidden: viewModel.state.isAmountHidden)) \(viewModel.state.displayCurrency)")
                                    Text("Осталось накопить: \(formatAmount(remaining, isHidden: viewModel.state.isAmountHidden)) \(viewModel.state.displayCurrency)")
                                    
                                    ProgressView(value: progress)
                                        .tint(AppColors.financesGradient.first ?? AppColors.brandPrimary)
                                    
                                    Text("Прогресс: \(Int(progress * 100))%")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Цель накопления")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(AppColors.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        viewModel.handle(.setSavingsGoalEnabled(isEnabled))
                        if let amount = Double(goalAmount) {
                            viewModel.handle(.setSavingsGoalAmount(amount))
                        }
                        dismiss()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
            .onAppear {
                isEnabled = viewModel.state.isSavingsGoalEnabled
                if viewModel.state.savingsGoalAmount > 0 {
                    goalAmount = String(format: "%.2f", viewModel.state.savingsGoalAmount)
                }
            }
        }
    }
    
    private func formatAmount(_ amount: Double, isHidden: Bool = false) -> String {
        if isHidden {
            let digits = Int(amount.rounded())
            let digitCount = String(digits).count
            return String(repeating: "•", count: max(3, digitCount))
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }
}

// MARK: - Inline Create Forms

private struct InlineCardCreateForm<GroupSection: View>: View {
    @ObservedObject var viewModel: CardViewModel
    let onCardDataChanged: (Card) -> Void
    let groupSection: GroupSection
    
    @State private var card: Card
    @State private var creditLimitText: String = ""
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    
    init(
        viewModel: CardViewModel,
        onCardDataChanged: @escaping (Card) -> Void,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
        self.onCardDataChanged = onCardDataChanged
        self.groupSection = groupSection()
        _card = State(initialValue: Card(
            name: "",
            cardNumber: "",
            bank: .other,
            cardType: .debit,
            priority: .normal,
            currency: "RUB",
            balance: 0.0
        ))
    }
    
    var currentCard: Card {
        let result = card
        if result.cardType == .credit, let limit = Double(creditLimitText.replacingOccurrences(of: ",", with: ".")) {
            result.creditLimit = limit
        }
        return result
    }
    
    var isValid: Bool { !card.name.isEmpty }
    
    var body: some View {
        VStack(spacing: 18) {
            nameSection
            typeSection
            balanceSection
            organizationSection
            groupSection
            calculationsSection
            prioritySection
        }
        .onAppear { loadAvailableCurrencies() }
        .onChange(of: card.name) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.cardNumber) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.bankRaw) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.cardTypeRaw) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.currency) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.balance) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: creditLimitText) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.priority) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.isFavorite) { _, _ in onCardDataChanged(currentCard) }
        .onChange(of: card.includeInTotal) { _, _ in onCardDataChanged(currentCard) }
    }
    
    private var accentColor: Color { AppColors.financesGradient.first ?? AppColors.brandPrimary }
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Название")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 22)
                        
                        TextField("Например, Тинькофф Black", text: $card.name)
                            .foregroundStyle(AppColors.textPrimary)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Image(systemName: "number")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 22)
                        
                        Text("Последние 4 цифры")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Spacer()
                        
                        TextField("0000", text: Binding(
                            get: { card.cardNumber },
                            set: { newValue in
                                let filtered = newValue.filter { $0.isNumber }
                                if filtered.count <= 4 { card.cardNumber = filtered }
                            }
                        ))
                        .keyboardType(.numberPad)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Тип")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Тип продукта")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("Карта")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        FinancesCheckboxOption(
                            title: "дебетовая",
                            isSelected: card.cardTypeRaw == CardType.debit.rawValue,
                            onTap: { card.cardTypeRaw = CardType.debit.rawValue }
                        )
                        
                        FinancesCheckboxOption(
                            title: "кредитная",
                            isSelected: card.cardTypeRaw == CardType.credit.rawValue,
                            onTap: { card.cardTypeRaw = CardType.credit.rawValue }
                        )
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
        }
        .onChange(of: card.cardTypeRaw) { _, newValue in
            if newValue == CardType.debit.rawValue {
                card.creditLimit = nil
                creditLimitText = ""
            }
        }
    }
    
    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Баланс")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Сумма")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", value: $card.balance, format: .number)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 140)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Text("Валюта")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        if isLoadingCurrencies {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(AppColors.textTertiary)
                        } else {
                            Menu {
                                ForEach(availableCurrencies, id: \.self) { currency in
                                    Button(currency) { card.currency = currency }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(card.currency)
                                        .font(.system(size: 16, weight: .semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    if card.cardType == .credit {
                        FinancesRowDivider(leadingPadding: 16)
                        
                        HStack(spacing: 12) {
                            Text("Лимит")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            TextField("0", text: $creditLimitText)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(AppColors.textPrimary)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 140)
                                .onChange(of: creditLimitText) { _, newValue in
                                    if let limit = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                                        card.creditLimit = limit
                                    } else if newValue.isEmpty {
                                        card.creditLimit = nil
                                    }
                                }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
    
    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Организация")
            FinancesGlassCard {
                HStack(spacing: 12) {
                    Text("Банк")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(Bank.allCases, id: \.rawValue) { bank in
                            Button(bank.displayName) { card.bankRaw = bank.rawValue }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(Bank(rawValue: card.bankRaw)?.displayName ?? Bank.other.displayName)
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var calculationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Подсчёты")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Учитывать в «Итого»", isOn: $card.includeInTotal)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Toggle("Избранная", isOn: $card.isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Определяет, как изменение баланса влияет на общий итог по всем продуктам.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Приоритет")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        FinancesRadioOption(title: "низкий", isSelected: card.priority == .low) { card.priority = .low }
                        FinancesRadioOption(title: "обычный", isSelected: card.priority == .normal) { card.priority = .normal }
                        FinancesRadioOption(title: "высокий", isSelected: card.priority == .high) { card.priority = .high }
                    }
                    
                    Text("Высокий приоритет — выше в списках.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                }
            }
        }
    }
    
    private func loadAvailableCurrencies() {
        Task {
            isLoadingCurrencies = true
            defer { isLoadingCurrencies = false }
            
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            var currencies = Array(fromRateSource)
            if !currencies.contains(card.currency) { currencies.append(card.currency) }
            availableCurrencies = currencies.sorted()
        }
    }
}

private struct InlineCreditCreateForm<GroupSection: View>: View {
    @ObservedObject var viewModel: CreditViewModel
    let onCreditDataChanged: ((name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, includeInTotal: Bool)?) -> Void
    let groupSection: GroupSection
    
    @State private var name: String = ""
    @State private var amountText: String = ""
    @State private var remainingAmountText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var selectedBank: Bank = .other
    @State private var selectedCreditType: CreditType = .consumer
    @State private var isFavorite: Bool = false
    @State private var includeInTotal: Bool = true
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    
    init(
        viewModel: CreditViewModel,
        onCreditDataChanged: @escaping ((name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, includeInTotal: Bool)?) -> Void,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
        self.onCreditDataChanged = onCreditDataChanged
        self.groupSection = groupSection()
    }
    
    var isValid: Bool {
        !name.isEmpty &&
        parseNumber(amountText) != nil && parseNumber(amountText)! > 0 &&
        parseNumber(remainingAmountText) != nil && parseNumber(remainingAmountText)! >= 0
    }
    
    func getCreditData() -> (name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, includeInTotal: Bool)? {
        guard let amount = parseNumber(amountText),
              let remainingAmount = parseNumber(remainingAmountText) else { return nil }
        // Дефолты для упрощенной формы: срок 12 месяцев от текущей даты
        let endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        let monthlyPayment = amount / 12.0
        return (name, amount, monthlyPayment, endDate, remainingAmount, selectedCurrency, selectedBank, selectedCreditType, isFavorite, includeInTotal)
    }
    
    var body: some View {
        VStack(spacing: 18) {
            FinancesSectionHeader(title: "Название")
            FinancesGlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 22)
                    
                    TextField("Например, Потребительский кредит", text: $name)
                        .foregroundStyle(AppColors.textPrimary)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            
            FinancesSectionHeader(title: "Тип")
            FinancesGlassCard {
                HStack(spacing: 12) {
                    Text("Тип кредита")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(CreditType.allCases, id: \.self) { type in
                            Button(type.displayName) { selectedCreditType = type }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedCreditType.displayName)
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            
            FinancesSectionHeader(title: "Баланс")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Сумма")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { formatNumberForDisplay(amountText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                amountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Text("Остаток")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { formatNumberForDisplay(remainingAmountText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                remainingAmountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Text("Валюта")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        if isLoadingCurrencies {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(AppColors.textTertiary)
                        } else {
                            Menu {
                                ForEach(availableCurrencies, id: \.self) { currency in
                                    Button(currency) { selectedCurrency = currency }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedCurrency)
                                        .font(.system(size: 16, weight: .semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
            
            FinancesSectionHeader(title: "Организация")
            FinancesGlassCard {
                HStack(spacing: 12) {
                    Text("Банк")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Menu {
                        ForEach(Bank.allCases, id: \.self) { bank in
                            Button(bank.displayName) { selectedBank = bank }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedBank.displayName)
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            
            groupSection
            
            FinancesSectionHeader(title: "Подсчёты")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Учитывать в «Итого»", isOn: $includeInTotal)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Toggle("В избранном", isOn: $isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .onAppear { loadAvailableCurrencies() }
        .onChange(of: name) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: amountText) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: remainingAmountText) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: selectedCurrency) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: selectedBank) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: selectedCreditType) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: isFavorite) { _, _ in onCreditDataChanged(getCreditData()) }
        .onChange(of: includeInTotal) { _, _ in onCreditDataChanged(getCreditData()) }
    }
    
    private func loadAvailableCurrencies() {
        Task {
            isLoadingCurrencies = true
            defer { isLoadingCurrencies = false }
            
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            var currencies = Array(fromRateSource)
            if !currencies.contains(selectedCurrency) { currencies.append(selectedCurrency) }
            availableCurrencies = currencies.sorted()
        }
    }
    
    private func parseNumber(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
    
    private func formatNumberForDisplay(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        guard let number = parseNumber(text) else { return text }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        let normalized = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        let hasDecimal = normalized.contains(".")
        if !hasDecimal { formatter.maximumFractionDigits = 0 }
        
        return formatter.string(from: NSNumber(value: number)) ?? text
    }
}

private struct InlineInvestmentCreateForm<GroupSection: View>: View {
    @ObservedObject var viewModel: InvestmentViewModel
    let onInvestmentDataChanged: ((name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool)?) -> Void
    let groupSection: GroupSection
    
    @State private var name: String = ""
    @State private var selectedInvestmentType: InvestmentType = .positive
    @State private var selectedCategory: InvestmentCategory = .other
    @State private var amountText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var includeInTotal: Bool = true
    @State private var selectedPriority: InvestmentPriority = .normal
    @State private var isFavorite: Bool = false
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    
    init(
        viewModel: InvestmentViewModel,
        onInvestmentDataChanged: @escaping ((name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool)?) -> Void,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self.viewModel = viewModel
        self.onInvestmentDataChanged = onInvestmentDataChanged
        self.groupSection = groupSection()
    }
    
    var isValid: Bool { !name.isEmpty && parseNumber(amountText) != nil && parseNumber(amountText)! > 0 }
    
    func getInvestmentData() -> (name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool)? {
        guard let amount = parseNumber(amountText) else { return nil }
        return (name, selectedInvestmentType, selectedCategory, amount, selectedCurrency, includeInTotal, selectedPriority, isFavorite)
    }
    
    var body: some View {
        VStack(spacing: 18) {
            FinancesSectionHeader(title: "Название")
            FinancesGlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 22)
                    
                    TextField("Например, Наличные", text: $name)
                        .foregroundStyle(AppColors.textPrimary)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            
            FinancesSectionHeader(title: "Баланс")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Сумма")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { formatNumberForDisplay(amountText) },
                            set: { newValue in
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                amountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider(leadingPadding: 16)
                    
                    HStack(spacing: 12) {
                        Text("Валюта")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        if isLoadingCurrencies {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(AppColors.textTertiary)
                        } else {
                            Menu {
                                ForEach(availableCurrencies, id: \.self) { currency in
                                    Button(currency) { selectedCurrency = currency }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedCurrency)
                                        .font(.system(size: 16, weight: .semibold))
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
            
            FinancesSectionHeader(title: "Организация")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Категория")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Menu {
                            ForEach(InvestmentCategory.allCases, id: \.self) { category in
                                Button(category.displayName) { selectedCategory = category }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedCategory.displayName)
                                    .font(.system(size: 16, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
            
            groupSection
            
            FinancesSectionHeader(title: "Подсчёты")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Учитывать в «Итого»", isOn: $includeInTotal)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    HStack(spacing: 12) {
                        FinancesCheckboxOption(
                            title: "увеличивает",
                            isSelected: selectedInvestmentType == .positive,
                            onTap: { selectedInvestmentType = .positive }
                        )
                        FinancesCheckboxOption(
                            title: "уменьшает",
                            isSelected: selectedInvestmentType == .negative,
                            onTap: { selectedInvestmentType = .negative }
                        )
                    }
                    
                    Toggle("В избранном", isOn: $isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Определяет, как изменение баланса влияет на общий итог по всем продуктам.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            FinancesSectionHeader(title: "Приоритет")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        FinancesRadioOption(title: "низкий", isSelected: selectedPriority == .low) { selectedPriority = .low }
                        FinancesRadioOption(title: "обычный", isSelected: selectedPriority == .normal) { selectedPriority = .normal }
                        FinancesRadioOption(title: "высокий", isSelected: selectedPriority == .high) { selectedPriority = .high }
                    }
                    
                    Text("Высокий приоритет — выше в списках.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                }
            }
        }
        .onAppear { loadAvailableCurrencies() }
        .onChange(of: name) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: selectedInvestmentType) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: selectedCategory) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: amountText) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: selectedCurrency) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: includeInTotal) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: selectedPriority) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
        .onChange(of: isFavorite) { _, _ in onInvestmentDataChanged(getInvestmentData()) }
    }
    
    private func loadAvailableCurrencies() {
        Task {
            isLoadingCurrencies = true
            defer { isLoadingCurrencies = false }
            
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            var currencies = Array(fromRateSource)
            if !currencies.contains(selectedCurrency) { currencies.append(selectedCurrency) }
            availableCurrencies = currencies.sorted()
        }
    }
    
    private func parseNumber(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
    
    private func formatNumberForDisplay(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        guard let number = parseNumber(text) else { return text }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        let normalized = text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        let hasDecimal = normalized.contains(".")
        if !hasDecimal { formatter.maximumFractionDigits = 0 }
        
        return formatter.string(from: NSNumber(value: number)) ?? text
    }
}
