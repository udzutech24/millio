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
        .navigationTitle("Финансы")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .task {
            await viewModel.refreshRates()
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
                VStack(spacing: 12) {
                    ForEach(viewModel.state.groups) { group in
                        FinanceGroupRow(
                            group: group,
                            viewModel: viewModel
                        )
                    }
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
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0.00"
    }
}

// MARK: - Finance Group Row

private struct FinanceGroupRow: View {
    let group: FinanceGroup
    @ObservedObject var viewModel: FinanceViewModel
    @State private var isExpanded: Bool = false
    @State private var groupTotal: Double = 0.0
    @State private var showDeleteConfirmation = false
    
    var isDefaultGroup: Bool {
        group.name == "Без группы"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Заголовок группы
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        // Цветная полоска
                        RoundedRectangle(cornerRadius: 2)
                            .fill(group.color)
                            .frame(width: 4, height: 40)
                        
                        // Название группы
                        Text(group.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Сумма группы
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formatBalance(groupTotal))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            
                            Text(viewModel.state.displayCurrency)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                        
                        // Иконка раскрытия
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                
                // Кнопки действий (только для не дефолтной группы)
                if !isDefaultGroup {
                    Menu {
                        Button {
                            viewModel.handle(.editGroup(group))
                        } label: {
                            Label("Редактировать", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Аккордеон с счетами
            if isExpanded {
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
                                    accountType: account.accountType
                                ) {
                                    viewModel.handle(.removeAccountFromGroup(account))
                                }
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
                    
                    // Кнопка добавления счета в группу
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
                .padding(.bottom, 12)
                }
        }
        .background {
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
        .confirmationDialog("Удалить группу?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                viewModel.handle(.deleteGroup(group))
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все счета из группы будут перемещены в группу \"Без группы\".")
        }
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
    }
    
    private func loadGroupTotal() async {
        groupTotal = await viewModel.calculateGroupTotal(
            group: group,
            in: viewModel.state.displayCurrency
        )
    }
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0.00"
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
    let onDelete: () -> Void
    
    @State private var showDeleteConfirmation = false
    
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
            
            // Сумма
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatBalance(amount))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(amount >= 0 ? AppColors.textPrimary : AppColors.error)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Text(currency)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }
            
            // Кнопка удаления
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.error)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .confirmationDialog("Удалить счет из группы?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                onDelete()
            }
            Button("Отмена", role: .cancel) {}
        }
    }
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
    }
}

// MARK: - Finance Group Editor View

private struct FinanceGroupEditorView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var selectedColor: Color = Color.blue
    
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
                    selectedColor = editing.color
                }
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty
    }
    
    private func saveGroup() {
        let colorHex = selectedColor.toHex()
        viewModel.handle(.updateGroup(name: name, colorHex: colorHex))
        dismiss()
    }
}

// MARK: - Finance Add Account View

private struct FinanceAddAccountView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedAccountType: FinanceAccountType = .card
    @State private var selectedCardID: String? = nil
    @State private var selectedCreditID: String? = nil
    @State private var selectedInvestmentID: String? = nil
    @State private var selectedGroupID: String? = nil
    
    var targetGroup: FinanceGroup? {
        if let selectedGroupID = selectedGroupID {
            return viewModel.state.groups.first { group in
                group.groupUniqueID == selectedGroupID
            }
        }
        return viewModel.state.selectedGroupForAccount ?? viewModel.state.defaultGroup
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
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
                    
                    Section {
                        Picker("Группа", selection: Binding(
                            get: { selectedGroupID ?? (viewModel.state.defaultGroup?.groupUniqueID ?? "") },
                            set: { selectedGroupID = $0.isEmpty ? nil : $0 }
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
                    } header: {
                        Text("Группа")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        if selectedAccountType == .card {
                            if viewModel.state.availableCards.isEmpty {
                                Button {
                                    viewModel.handle(.showCreateCardSheet)
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Создать карту")
                                    }
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.financesGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                }
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
                                
                                Button {
                                    viewModel.handle(.showCreateCardSheet)
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Создать новую карту")
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
                        } else if selectedAccountType == .credit {
                            if viewModel.state.availableCredits.isEmpty {
                                Button {
                                    viewModel.handle(.showCreateCreditSheet)
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Создать кредит")
                                    }
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.financesGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                }
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
                                
                                Button {
                                    viewModel.handle(.showCreateCreditSheet)
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Создать новый кредит")
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
                        } else if selectedAccountType == .investment {
                            if viewModel.state.availableInvestments.isEmpty {
                                Button {
                                    viewModel.handle(.showCreateInvestmentSheet)
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Создать актив")
                                    }
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.financesGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                }
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
                                
                                Button {
                                    viewModel.handle(.showCreateInvestmentSheet)
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Создать новый актив")
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
                    } header: {
                        Text("Счет")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Добавить счет")
            .navigationBarTitleDisplayMode(.inline)
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
                } else if let defaultGroup = viewModel.state.defaultGroup {
                    selectedGroupID = defaultGroup.groupUniqueID
                }
            }
        }
    }
    
    private var isValid: Bool {
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
                           let targetGroup = viewModel.state.selectedGroupForAccount ?? viewModel.state.defaultGroup {
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
                           let targetGroup = viewModel.state.selectedGroupForAccount ?? viewModel.state.defaultGroup {
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
                           let targetGroup = viewModel.state.selectedGroupForAccount ?? viewModel.state.defaultGroup {
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
