//
//  FinanceAddAccountView.swift
//  millio
//

import SwiftUI
import SwiftData

// MARK: - Finance Add Account View

struct FinanceAddAccountView: View {
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
    @State private var investmentData: (name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool, marketData: InvestmentMarketData?, createCashflowTransaction: Bool)?
    @State private var selectedArchivedAccountID: String? = nil
    @State private var accountName: String = ""
    
    private var navigationTitle: String {
        switch selectedAccountType {
        case .card: return "Новая карта"
        case .credit: return "Новый кредит"
        case .investment: return "Новый актив"
        }
    }
    
    private var resolvedGroup: FinanceGroup? {
        FinanceAddAccountGroupSelection.resolveSelectedGroup(
            selectedGroupID: selectedGroupID,
            preselectedGroupID: viewModel.state.selectedGroupForAccount?.groupUniqueID,
            groups: viewModel.state.groups
        )
    }
    
    var targetGroup: FinanceGroup? {
        resolvedGroup
    }
    
    // MARK: - Form Sections
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Название")
            FinancesGlassCard {
                HStack(spacing: 12) {
                    Image(systemName: iconForSelectedType)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 22)
                    
                    TextField(placeholderForSelectedType, text: $accountName)
                        .foregroundStyle(AppColors.textPrimary)
                        .textInputAutocapitalization(selectedAccountType == .card ? .words : .sentences)
                        .submitLabel(.done)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
        }
    }
    
    private var iconForSelectedType: String {
        switch selectedAccountType {
        case .card: return "creditcard"
        case .credit: return "doc.text"
        case .investment: return "chart.pie.fill"
        }
    }
    
    private var placeholderForSelectedType: String {
        switch selectedAccountType {
        case .card: return "Например, Тинькофф Black"
        case .credit: return "Например, Потребительский кредит"
        case .investment: return "Например, Наличные"
        }
    }
    
    private var accountTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Тип")
            FinancesGlassCard {
                Menu {
                    ForEach(FinanceAccountType.allCases, id: \.self) { type in
                        Button {
                            selectedAccountType = type
                        } label: {
                            Label(type.displayName, systemImage: type.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text("Тип продукта")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Spacer()
                        
                        Text(selectedAccountType.displayName)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
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
                let currentGroupID = resolvedGroup?.groupUniqueID
                let currentGroupName = resolvedGroup?.name ?? "Не выбрано"
                
                FinancesGlassCard {
                    Menu {
                        ForEach(viewModel.state.groups) { group in
                            Button {
                                selectedGroupID = group.groupUniqueID
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(group.color)
                                        .frame(width: 12, height: 12)
                                    
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
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Text("Группа")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            
                            Spacer()
                            
                            Text(currentGroupName)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: AppColors.financesGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
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
                    name: $accountName,
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
                    name: $accountName,
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
                    name: $accountName,
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
                if addAccountMode == .create {
                    nameSection
                }
                
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
        .navigationTitle(navigationTitle)
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
        
        // Базовая проверка имени для всех типов
        guard !accountName.isEmpty else { return false }
        
        switch selectedAccountType {
        case .card:
            return cardData != nil
        case .credit:
            return creditData != nil
        case .investment:
            return investmentData != nil
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
            marketData: investmentData.marketData,
            createCashflowTransaction: investmentData.createCashflowTransaction,
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

// MARK: - Group Selection Helper

enum FinanceAddAccountGroupSelection {
    static func resolveSelectedGroup(
        selectedGroupID: String?,
        preselectedGroupID: String?,
        groups: [FinanceGroup]
    ) -> FinanceGroup? {
        if let selectedGroupID,
           let selectedGroup = groups.first(where: { $0.groupUniqueID == selectedGroupID }) {
            return selectedGroup
        }
        
        if let preselectedGroupID,
           let preselectedGroup = groups.first(where: { $0.groupUniqueID == preselectedGroupID }) {
            return preselectedGroup
        }
        
        return groups.first
    }
}
