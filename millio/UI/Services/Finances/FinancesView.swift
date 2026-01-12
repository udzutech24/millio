//
//  FinancesView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData

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
    
    var body: some View {
        mainContent
            .navigationTitle("Финансы")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .modifier(SheetsModifier(viewModel: viewModel))
            .task {
                await viewModel.refreshRates()
            }
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
                .padding(.bottom, 32)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            NavigationLink {
                FinanceDynamicsView(financeViewModel: viewModel)
            } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    viewModel.handle(.addGroup)
                } label: {
                    Label("Создать группу", systemImage: "folder.badge.plus")
                }
                
                Button {
                    viewModel.handle(.showAddAccountSheet(nil))
                } label: {
                    Label("Добавить счет", systemImage: "plus.circle")
                }
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
    }
    
    // MARK: - Total Amount Section
    
    private var totalAmountSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Общая сумма")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
                
                Spacer()
                
                Button {
                    viewModel.handle(.showDisplayCurrencySheet)
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.state.displayCurrency)
                            .font(.system(size: 14, weight: .semibold))
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
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatBalance(viewModel.state.totalAmount))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                
                Text(viewModel.state.displayCurrency)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
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
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
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
            // Цветная полоска
            RoundedRectangle(cornerRadius: 2)
                .fill(group.color)
                .frame(width: 4, height: 40)
            
            // Название группы
            groupNameSection
            
            // Сумма группы
            groupAmountSection
            
            // Иконка раскрытия
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var groupAmountSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(formatBalance(groupTotal))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(groupDisplayCurrency)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
        }
    }
    
    private var accountsAccordion: some View {
        VStack(spacing: 8) {
            if let accounts = group.accounts, !accounts.isEmpty {
                ForEach(accounts) { account in
                    if let accountInfo = viewModel.getAccountInfo(account: account) {
                        FinanceAccountRow(
                            account: account,
                            name: accountInfo.name,
                            amount: accountInfo.amount,
                            currency: accountInfo.currency,
                            icon: accountInfo.icon,
                            accountType: account.accountType,
                            isCreditCardDebt: accountInfo.isCreditCardDebt,
                            onEdit: {
                                viewModel.handle(.editAccount(account))
                            },
                            onDelete: {
                                viewModel.handle(.removeAccountFromGroup(account))
                            },
                            onQuickEditAmount: {
                                viewModel.handle(.showQuickEditAccountSheet(account))
                            }
                        )
                    }
                }
            } else {
                Text("Нет счетов")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)
                    .padding(.vertical, 12)
            }
            
            addAccountButton
        }
        .padding(.bottom, 12)
    }
    
    private var addAccountButton: some View {
        Button {
            viewModel.handle(.showAddAccountSheet(group))
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("Добавить счет")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 20)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
    
    private var groupBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
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
    
    private func formatBalance(_ balance: Double) -> String {
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
    let account: FinanceAccount
    let name: String
    let amount: Double
    let currency: String
    let icon: String
    let accountType: FinanceAccountType
    let isCreditCardDebt: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onQuickEditAmount: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Иконка счета
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: AppColors.financesGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32, height: 32)
            
            // Название счета
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Сумма (кликабельна для быстрого редактирования)
            Button {
                onQuickEditAmount()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatBalance(amount))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isCreditCardDebt ? AppColors.error : (amount >= 0 ? AppColors.textPrimary : AppColors.error))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Text(currency)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
    }
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
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
                DisplayCurrencySheet(viewModel: viewModel)
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
                    NavigationStack {
                        FinanceDynamicsView(
                            financeViewModel: viewModel,
                            initialGroupID: group.groupUniqueID,
                            initialGroupCurrency: group.displayCurrency
                        )
                        .navigationTitle(group.name)
                        .navigationBarTitleDisplayMode(.inline)
                    }
                }
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
}

// MARK: - Finance Add Account View

private struct FinanceAddAccountView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var selectedAccountType: FinanceAccountType = .card
    @State private var selectedCardID: String? = nil
    @State private var selectedCreditID: String? = nil
    @State private var selectedInvestmentID: String? = nil
    @State private var selectedGroupID: String? = nil
    @State private var showCreateCard = false
    @State private var showCreateCredit = false
    @State private var showCreateInvestment = false
    @State private var cardViewModel: CardViewModel?
    @State private var creditViewModel: CreditViewModel?
    @State private var investmentViewModel: InvestmentViewModel?
    
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
        Section {
            Picker("Тип счета", selection: $selectedAccountType) {
                ForEach(FinanceAccountType.allCases, id: \.self) { type in
                    HStack {
                        Image(systemName: type.icon)
                        Text(type.displayName)
                    }
                    .tag(type)
                }
            }
            .foregroundStyle(AppColors.textPrimary)
        } header: {
            Text("Тип счета")
                .foregroundStyle(AppColors.textSecondary)
        }
    }
    
    private var groupSection: some View {
        Section {
            if viewModel.state.groups.isEmpty {
                Text("Сначала создайте группу")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                Picker("Группа", selection: Binding(
                    get: { selectedGroupID ?? viewModel.state.selectedGroupForAccount?.groupUniqueID ?? viewModel.state.groups.first?.groupUniqueID ?? "" },
                    set: { selectedGroupID = $0 }
                )) {
                    ForEach(viewModel.state.groups) { group in
                        HStack {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(group.color)
                                .frame(width: 16, height: 16)
                            Text(group.name)
                        }
                        .tag(group.groupUniqueID)
                    }
                }
                .foregroundStyle(AppColors.textPrimary)
            }
        } header: {
            Text("Группа")
                .foregroundStyle(AppColors.textSecondary)
        }
    }
    
    @ViewBuilder
    private var accountSection: some View {
        Section {
            switch selectedAccountType {
            case .card:
                cardAccountContent
            case .credit:
                creditAccountContent
            case .investment:
                investmentAccountContent
            }
        } header: {
            Text("Счет")
                .foregroundStyle(AppColors.textSecondary)
        }
    }
    
    @ViewBuilder
    private var cardAccountContent: some View {
        if viewModel.state.availableCards.isEmpty {
            createCardButton(isEmpty: true)
        } else {
            Picker("Карта", selection: Binding(
                get: { selectedCardID ?? "" },
                set: { selectedCardID = $0.isEmpty ? nil : $0 }
            )) {
                Text("Выберите карту").tag("")
                ForEach(viewModel.state.availableCards) { card in
                    Text(card.name).tag(card.cardUniqueID)
                }
            }
            .foregroundStyle(AppColors.textPrimary)
            
            createCardButton(isEmpty: false)
        }
    }
    
    @ViewBuilder
    private var creditAccountContent: some View {
        if viewModel.state.availableCredits.isEmpty {
            createCreditButton(isEmpty: true)
        } else {
            Picker("Кредит", selection: Binding(
                get: { selectedCreditID ?? "" },
                set: { selectedCreditID = $0.isEmpty ? nil : $0 }
            )) {
                Text("Выберите кредит").tag("")
                ForEach(viewModel.state.availableCredits) { credit in
                    Text(credit.name).tag(credit.creditUniqueID)
                }
            }
            .foregroundStyle(AppColors.textPrimary)
            
            createCreditButton(isEmpty: false)
        }
    }
    
    @ViewBuilder
    private var investmentAccountContent: some View {
        if viewModel.state.availableInvestments.isEmpty {
            createInvestmentButton(isEmpty: true)
        } else {
            Picker("Актив", selection: Binding(
                get: { selectedInvestmentID ?? "" },
                set: { selectedInvestmentID = $0.isEmpty ? nil : $0 }
            )) {
                Text("Выберите актив").tag("")
                ForEach(viewModel.state.availableInvestments) { investment in
                    Text(investment.name).tag(investment.investmentUniqueID)
                }
            }
            .foregroundStyle(AppColors.textPrimary)
            
            createInvestmentButton(isEmpty: false)
        }
    }
    
    private func createCardButton(isEmpty: Bool) -> some View {
        Button {
            showCreateCard = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text(isEmpty ? "Создать карту" : "Создать новую карту")
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
    
    private func createCreditButton(isEmpty: Bool) -> some View {
        Button {
            showCreateCredit = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text(isEmpty ? "Создать кредит" : "Создать новый кредит")
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
    
    private func createInvestmentButton(isEmpty: Bool) -> some View {
        Button {
            showCreateInvestment = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text(isEmpty ? "Создать актив" : "Создать новый актив")
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    accountTypeSection
                    groupSection
                    accountSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Добавить счет")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showCreateCard) {
                Group {
                    if let cardViewModel = cardViewModel {
                        FinanceCardEditorWrapper(
                            cardViewModel: cardViewModel,
                            onCardCreated: { cardID in
                                selectedCardID = cardID
                                viewModel.handle(.loadAccounts)
                            }
                        )
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
            .navigationDestination(isPresented: $showCreateCredit) {
                Group {
                    if let creditViewModel = creditViewModel {
                        FinanceCreditEditorWrapper(
                            creditViewModel: creditViewModel,
                            onCreditCreated: { creditID in
                                selectedCreditID = creditID
                                viewModel.handle(.loadAccounts)
                            }
                        )
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
            .navigationDestination(isPresented: $showCreateInvestment) {
                Group {
                    if let investmentViewModel = investmentViewModel {
                        FinanceInvestmentEditorWrapper(
                            investmentViewModel: investmentViewModel,
                            onInvestmentCreated: { investmentID in
                                selectedInvestmentID = investmentID
                                viewModel.handle(.loadAccounts)
                            }
                        )
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Добавить") {
                        addAccount()
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
                // Устанавливаем предустановленную группу, если она была выбрана
                if let preselectedGroup = viewModel.state.selectedGroupForAccount {
                    selectedGroupID = preselectedGroup.groupUniqueID
                } else if let firstGroup = viewModel.state.groups.first {
                    selectedGroupID = firstGroup.groupUniqueID
                }
                // Обновляем список доступных карт при открытии формы
                viewModel.handle(.loadAccounts)
            }
            .onChange(of: viewModel.state.availableCards) { oldCards, newCards in
                // Если была выбрана карта, но её нет в новом списке, сбрасываем выбор
                if let selectedID = selectedCardID,
                   !newCards.contains(where: { $0.cardUniqueID == selectedID }) {
                    selectedCardID = nil
                }
                // Если была создана новая карта и она еще не выбрана, выбираем её
                if selectedCardID == nil {
                    let oldCardIDs = Set(oldCards.map { $0.cardUniqueID })
                    let newCards = newCards.filter { !oldCardIDs.contains($0.cardUniqueID) }
                    if let newCard = newCards.first {
                        selectedCardID = newCard.cardUniqueID
                    }
                }
            }
            .onChange(of: viewModel.state.availableCredits) { oldCredits, newCredits in
                if let selectedID = selectedCreditID,
                   !newCredits.contains(where: { $0.creditUniqueID == selectedID }) {
                    selectedCreditID = nil
                }
                if selectedCreditID == nil {
                    let oldCreditIDs = Set(oldCredits.map { $0.creditUniqueID })
                    let newCredits = newCredits.filter { !oldCreditIDs.contains($0.creditUniqueID) }
                    if let newCredit = newCredits.first {
                        selectedCreditID = newCredit.creditUniqueID
                    }
                }
            }
            .onChange(of: viewModel.state.availableInvestments) { oldInvestments, newInvestments in
                if let selectedID = selectedInvestmentID,
                   !newInvestments.contains(where: { $0.investmentUniqueID == selectedID }) {
                    selectedInvestmentID = nil
                }
                if selectedInvestmentID == nil {
                    let oldInvestmentIDs = Set(oldInvestments.map { $0.investmentUniqueID })
                    let newInvestments = newInvestments.filter { !oldInvestmentIDs.contains($0.investmentUniqueID) }
                    if let newInvestment = newInvestments.first {
                        selectedInvestmentID = newInvestment.investmentUniqueID
                    }
                }
            }
        }
    }
    
    private var isValid: Bool {
        guard targetGroup != nil else { return false }
        switch selectedAccountType {
        case .card:
            return selectedCardID != nil
        case .credit:
            return selectedCreditID != nil
        case .investment:
            return selectedInvestmentID != nil
        }
    }
    
    private func addAccount() {
        guard let targetGroup = targetGroup else { return }
        
        let accountID: String?
        switch selectedAccountType {
        case .card:
            accountID = selectedCardID
        case .credit:
            accountID = selectedCreditID
        case .investment:
            accountID = selectedInvestmentID
        }
        
        guard let accountID = accountID else { return }
        
        viewModel.handle(.addAccountToGroup(
            accountType: selectedAccountType,
            accountID: accountID,
            group: targetGroup
        ))
        
        dismiss()
    }
}

// MARK: - Finance Editor Wrappers

private struct FinanceCardEditorWrapper: View {
    @ObservedObject var cardViewModel: CardViewModel
    @Environment(\.dismiss) private var dismiss
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
                // Если количество карт увеличилось и это была новая карта
                if wasNewCard && newCount > initialCardsCount {
                    // Находим новую карту (та, которой не было в начальном списке)
                    let newCards = cardViewModel.state.cards.filter { !initialCardIDs.contains($0.cardUniqueID) }
                    if let newCard = newCards.first {
                        onCardCreated(newCard.cardUniqueID)
                        dismiss()
                    }
                }
            }
            .onChange(of: cardViewModel.state.showCardEditor) { oldValue, newValue in
                // Когда форма закрывается после сохранения новой карты
                if wasNewCard && oldValue == true && newValue == false {
                    // Даем время на сохранение и обновление списка
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        let newCards = cardViewModel.state.cards.filter { !initialCardIDs.contains($0.cardUniqueID) }
                        if let newCard = newCards.first {
                            onCardCreated(newCard.cardUniqueID)
                            dismiss()
                        }
                    }
                }
            }
    }
}

private struct FinanceCreditEditorWrapper: View {
    @ObservedObject var creditViewModel: CreditViewModel
    @Environment(\.dismiss) private var dismiss
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
                        dismiss()
                    }
                }
            }
            .onChange(of: creditViewModel.state.showCreditEditor) { oldValue, newValue in
                if wasNewCredit && oldValue == true && newValue == false {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        let newCredits = creditViewModel.state.credits.filter { !initialCreditIDs.contains($0.creditUniqueID) }
                        if let newCredit = newCredits.first {
                            onCreditCreated(newCredit.creditUniqueID)
                            dismiss()
                        }
                    }
                }
            }
    }
}

private struct FinanceInvestmentEditorWrapper: View {
    @ObservedObject var investmentViewModel: InvestmentViewModel
    @Environment(\.dismiss) private var dismiss
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
                        dismiss()
                    }
                }
            }
            .onChange(of: investmentViewModel.state.showInvestmentEditor) { oldValue, newValue in
                if wasNewInvestment && oldValue == true && newValue == false {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        let newInvestments = investmentViewModel.state.investments.filter { !initialInvestmentIDs.contains($0.investmentUniqueID) }
                        if let newInvestment = newInvestments.first {
                            onInvestmentCreated(newInvestment.investmentUniqueID)
                            dismiss()
                        }
                    }
                }
            }
    }
}

// MARK: - Finance Edit Views

private struct FinanceEditCardView: View {
    let card: Card
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var cardViewModel: CardViewModel?
    
    var body: some View {
        Group {
            if let cardViewModel = cardViewModel {
                CardEditorView(viewModel: cardViewModel)
                    .onChange(of: cardViewModel.state.showCardEditor) { oldValue, newValue in
                        if oldValue == true && newValue == false {
                            // Редактор закрыт, обновляем данные
                            viewModel.handle(.loadAccounts)
                            viewModel.handle(.loadGroups)
                            // Пересчитываем суммы всех групп
                            Task {
                                await recalculateAllGroupTotals()
                            }
                            dismiss()
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
        // Также пересчитываем общую сумму
        await viewModel.calculateTotalAmountAsync()
    }
}

private struct FinanceEditCreditView: View {
    let credit: Credit
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var creditViewModel: CreditViewModel?
    
    var body: some View {
        Group {
            if let creditViewModel = creditViewModel {
                CreditEditorView(viewModel: creditViewModel)
                    .onChange(of: creditViewModel.state.showCreditEditor) { oldValue, newValue in
                        if oldValue == true && newValue == false {
                            // Редактор закрыт, обновляем данные
                            viewModel.handle(.loadAccounts)
                            viewModel.handle(.loadGroups)
                            // Пересчитываем суммы всех групп
                            Task {
                                await recalculateAllGroupTotals()
                            }
                            dismiss()
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
        // Также пересчитываем общую сумму
        await viewModel.calculateTotalAmountAsync()
    }
}

private struct FinanceEditInvestmentView: View {
    let investment: Investment
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var investmentViewModel: InvestmentViewModel?
    
    var body: some View {
        Group {
            if let investmentViewModel = investmentViewModel {
                InvestmentEditorView(viewModel: investmentViewModel)
                    .onChange(of: investmentViewModel.state.showInvestmentEditor) { oldValue, newValue in
                        if oldValue == true && newValue == false {
                            // Редактор закрыт, обновляем данные
                            viewModel.handle(.loadAccounts)
                            viewModel.handle(.loadGroups)
                            // Пересчитываем суммы всех групп
                            Task {
                                await recalculateAllGroupTotals()
                            }
                            dismiss()
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
        // Также пересчитываем общую сумму
        await viewModel.calculateTotalAmountAsync()
    }
}

// MARK: - Finance Create Card View

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
                        // Отслеживаем создание новой карты
                        if oldValue == nil && newValue != nil {
                            createdCardID = newValue?.cardUniqueID
                        }
                    }
                    .onDisappear {
                        // После закрытия sheet добавляем карту в группу, если она была создана
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

// MARK: - Finance Create Credit View

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
                        // Отслеживаем создание нового кредита
                        if oldValue == nil && newValue != nil {
                            createdCreditID = newValue?.creditUniqueID
                        }
                    }
                    .onDisappear {
                        // После закрытия sheet добавляем кредит в группу, если он был создан
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

// MARK: - Finance Create Investment View

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
                        // Отслеживаем создание нового актива
                        if oldValue == nil && newValue != nil {
                            createdInvestmentID = newValue?.investmentUniqueID
                        }
                    }
                    .onDisappear {
                        // После закрытия sheet добавляем актив в группу, если он был создан
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
    @State private var availableCurrencies: [String] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                if isLoading {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                } else {
                    List {
                        ForEach(availableCurrencies, id: \.self) { currency in
                            Button {
                                viewModel.handle(.setDisplayCurrency(currency))
                                dismiss()
                            } label: {
                                HStack {
                                    Text(currency)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
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
                            .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Валюта отображения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
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
            .task {
                await loadAvailableCurrencies()
            }
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
    }
}

