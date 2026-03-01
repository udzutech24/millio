//
//  FinanceAddAccountView.swift
//  millio
//

import SwiftUI
import SwiftData

// MARK: - Finance Add Account View

struct FinanceAddAccountView: View {
    @ObservedObject var viewModel: FinanceViewModel
    let editingInvestment: Investment?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    init(viewModel: FinanceViewModel, editingInvestment: Investment? = nil) {
        self.viewModel = viewModel
        self.editingInvestment = editingInvestment
    }
    
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
    @State private var selectedInvestmentCategory: InvestmentCategory = .other
    @State private var selectedProductTypeTitle: String = FinanceAccountType.card.displayName
    @State private var showCreateGroup = false
    @State private var cardViewModel: CardViewModel?
    @State private var creditViewModel: CreditViewModel?
    @State private var investmentViewModel: InvestmentViewModel?
    @State private var cardData: Card?
    @State private var creditData: (name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, paymentMode: CreditPaymentMode, paymentDayOfMonth: Int?, nextPaymentDate: Date?, reminderEnabled: Bool, reminderDaysBefore: Int?, reminderTime: Date?, includeInTotal: Bool)?
    @State private var investmentData: (name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool, marketData: InvestmentMarketData?, createCashflowTransaction: Bool)?
    @State private var selectedArchivedAccountID: String? = nil
    @State private var accountName: String = ""
    @FocusState private var isNameFieldFocused: Bool
    @State private var areHintsHidden: Bool = false

    private enum HintsPrefs {
        static let hiddenKey = "finance_add_account_hints_hidden"
    }

    private struct ValidationHint: Identifiable {
        enum Kind {
            case required
            case recommended
        }

        let id = UUID()
        let text: String
        let kind: Kind
    }
    
    private var navigationTitle: String {
        editingInvestment == nil ? "Новый продукт" : "Редактирование продукта"
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: iconForSelectedType)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 22)
                        
                        TextField(placeholderForSelectedType, text: $accountName)
                            .foregroundStyle(AppColors.textPrimary)
                            .focused($isNameFieldFocused)
                            .textInputAutocapitalization(selectedAccountType == .card ? .words : .sentences)
                            .submitLabel(.done)
                            .disabled(isTickerDrivenName)
                            .opacity(isTickerDrivenName ? 0.75 : 1.0)
                    }
                    
                    if isTickerDrivenName {
                        Text("Название подставится автоматически после выбора тикера/пары")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                            .padding(.leading, 34)
                    }
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
        case .card:
            return "Например, Основная карта"
        case .credit:
            return "Например, Потребительский кредит"
        case .investment:
            if isTickerDrivenName {
                return "Название из тикера/пары"
            }
            if selectedProductTypeTitle == "Счет" {
                return "Например, Резервный счет"
            }
            switch selectedInvestmentCategory {
            case .house:
                return "Например, Квартира для аренды"
            case .stocks:
                return "Например, Портфель ETF"
            case .business:
                return "Например, Доля в бизнесе"
            case .debt:
                return "Например, Займ знакомому"
            case .crypto:
                return "Например, Портфель криптовалют"
            case .car:
                return "Например, Семейный автомобиль"
            case .bonds:
                return "Например, Портфель облигаций"
            case .metals:
                return "Например, Инвестиции в золото"
            case .other:
                return "Например, Наличные"
            }
        }
    }

    private var isTickerDrivenName: Bool {
        selectedAccountType == .investment && (selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto)
    }
    
    private var accountTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Тип")
            FinancesGlassCard {
                Menu {
                    Button {
                        selectedAccountType = .card
                        selectedProductTypeTitle = "Карта"
                    } label: {
                        Label(FinanceAccountType.card.displayName, systemImage: FinanceAccountType.card.icon)
                    }
                    Button {
                        selectedAccountType = .investment
                        selectedInvestmentCategory = .other
                        selectedProductTypeTitle = "Счет"
                    } label: {
                        Label("Счет", systemImage: "building.columns.fill")
                    }

                    Button {
                        selectedAccountType = .credit
                        selectedProductTypeTitle = "Кредит"
                    } label: {
                        Label(FinanceAccountType.credit.displayName, systemImage: FinanceAccountType.credit.icon)
                    }

                    if addAccountMode == .create {
                        Button {
                            selectedAccountType = .investment
                            selectedInvestmentCategory = .other
                            selectedProductTypeTitle = "Актив"
                        } label: {
                            Label("Актив", systemImage: FinanceAccountType.investment.icon)
                        }

                        ForEach(visibleInvestmentCategories, id: \.self) { category in
                            Button {
                                selectedAccountType = .investment
                                selectedInvestmentCategory = category
                                selectedProductTypeTitle = category.displayName
                            } label: {
                                Label(category.displayName, systemImage: category.icon)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text("Тип продукта")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Spacer()
                        
                        Text(selectedProductTypeTitle)
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

    private var visibleInvestmentCategories: [InvestmentCategory] {
        [.house, .stocks, .business, .debt, .crypto, .other]
    }
    
    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Группа")
            
            if viewModel.state.groups.isEmpty {
                FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                    VStack(spacing: 12) {
                        Text("Продукт будет добавлен в «Без группы»")
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
                let currentGroupName = resolvedGroup?.name ?? "Без группы"
                let selectableGroups = viewModel.state.groups.filter { $0.name != "Без группы" }
                
                FinancesGlassCard {
                    Menu {
                        Button {
                            selectedGroupID = nil
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .foregroundStyle(AppColors.textTertiary)
                                    .frame(width: 12, height: 12)

                                Text("Без группы")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)

                                Spacer()

                                if currentGroupID == nil {
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

                        ForEach(selectableGroups) { group in
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
        EmptyView()
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
                    selectedProductType: selectedAccountType,
                    selectedInvestmentCategory: selectedInvestmentCategory,
                    onProductTypeSelected: { selectedAccountType = $0 },
                    onProductTitleSelected: { selectedProductTypeTitle = $0 },
                    onInvestmentCategorySelected: { category in
                        selectedInvestmentCategory = category
                    },
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
                    FinancesSectionHeader(title: editingInvestment == nil ? "Создать актив" : "Редактировать актив")
                    FinancesGlassCard(contentPadding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)) {
                        ProgressView()
                            .tint(AppColors.textPrimary)
                            .task {
                                let vm = InvestmentViewModel(modelContext: modelContext)
                                if let editingInvestment {
                                    vm.handle(.editInvestment(editingInvestment))
                                } else {
                                    vm.handle(.addInvestment)
                                }
                                investmentViewModel = vm
                            }
                    }
                }
                groupSection
            } else if let vm = investmentViewModel {
                InlineInvestmentCreateForm(
                    viewModel: vm,
                    name: $accountName,
                    selectedCategory: $selectedInvestmentCategory,
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
    private var validationHintsSection: some View {
        if addAccountMode == .create, !validationHints.isEmpty, !areHintsHidden {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    FinancesSectionHeader(title: "Подсказки")
                    Spacer()
                    Button {
                        areHintsHidden = true
                        UserDefaults.standard.set(true, forKey: HintsPrefs.hiddenKey)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Скрыть подсказки")
                }
                FinancesGlassCard(accentColor: warningAccentColor, contentPadding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(validationHints) { hint in
                            HStack(spacing: 8) {
                                Image(systemName: hint.kind == .required ? "exclamationmark.triangle.fill" : "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(hint.kind == .required ? warningAccentColor : recommendationAccentColor)
                                    .frame(width: 14)
                                Text(hint.text)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.black.opacity(0.28))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(
                                                (hint.kind == .required ? warningAccentColor : recommendationAccentColor).opacity(0.65),
                                                lineWidth: 1
                                            )
                                    )
                            )
                        }
                    }
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
                nameSection
                
                if selectedAccountType != .card {
                    accountTypeSection
                }
                addAccountModeSection

                validationHintsSection
                createFormSections
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
        .dismissKeyboardOnTap()
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
                if areHintsHidden, !validationHints.isEmpty {
                    Button {
                        areHintsHidden = false
                        UserDefaults.standard.set(false, forKey: HintsPrefs.hiddenKey)
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.textTertiary)
                    .accessibilityLabel("Показать подсказки")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(editingInvestment == nil ? "Добавить" : "Сохранить") { addAccount() }
                    .foregroundStyle(
                        isValid
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [Color(red: 0.22, green: 1.0, blue: 0.56), Color(red: 0.13, green: 0.79, blue: 0.38)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        : AnyShapeStyle(Color.white.opacity(0.28))
                    )
                    .disabled(!isValid)
            }
        }
        .onAppear {
            areHintsHidden = UserDefaults.standard.bool(forKey: HintsPrefs.hiddenKey)
            if let editingInvestment {
                selectedAccountType = .investment
                selectedInvestmentCategory = editingInvestment.category
                selectedProductTypeTitle = editingInvestment.category.displayName
                accountName = editingInvestment.name
            }
            if let preselectedGroup = viewModel.state.selectedGroupForAccount {
                selectedGroupID = preselectedGroup.groupUniqueID
            } else if let editingInvestment {
                let editingID = editingInvestment.investmentUniqueID
                let descriptor = FetchDescriptor<FinanceAccount>()
                let accountLink = (try? modelContext.fetch(descriptor))?.first(where: {
                    $0.accountType == .investment && $0.accountID == editingID
                })
                selectedGroupID = accountLink?.group?.groupUniqueID
            } else {
                selectedGroupID = nil
            }
            viewModel.handle(.loadAccounts)
        }
    }
    
    var body: some View {
        NavigationStack {
            navigationContent
                .modifier(SelectedAccountTypeChangeHandler(selectedAccountType: $selectedAccountType, cardViewModel: $cardViewModel, creditViewModel: $creditViewModel, investmentViewModel: $investmentViewModel, selectedArchivedAccountID: $selectedArchivedAccountID))
                .onChange(of: selectedAccountType) { _, _ in
                    focusNameFieldIfNeeded()
                }
                .onChange(of: selectedInvestmentCategory) { _, _ in
                    if isTickerDrivenName {
                        let selectedSymbol = investmentData?.marketData?.symbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if selectedSymbol.isEmpty {
                            accountName = ""
                        }
                    }
                    focusNameFieldIfNeeded()
                }
                .onAppear {
                    focusNameFieldIfNeeded()
                }
        }
    }
    
    private var isValid: Bool {
        guard requiredHints.isEmpty else { return false }

        switch selectedAccountType {
        case .card:
            return cardData != nil
        case .credit:
            return creditData != nil
        case .investment:
            return investmentData != nil
        }
    }

    private var warningAccentColor: Color {
        Color(red: 1.0, green: 0.37, blue: 0.35)
    }

    private var recommendationAccentColor: Color {
        Color(red: 0.18, green: 0.95, blue: 0.45)
    }

    private var trimmedAccountName: String {
        accountName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasEnteredPrimaryAmount: Bool {
        switch selectedAccountType {
        case .card:
            guard let cardData else { return false }
            if cardData.cardType == .credit {
                return cardData.creditLimit != nil
            }
            return cardData.balance != 0
        case .credit:
            guard let creditData else { return false }
            return creditData.amount != 0
        case .investment:
            guard let investmentData else { return false }
            if selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto {
                return (investmentData.marketData?.quantity ?? 0) != 0
            }
            return investmentData.amount != 0
        }
    }

    private var requiredHints: [ValidationHint] {
        guard addAccountMode == .create else { return [] }
        var hints: [ValidationHint] = []

        if isTickerDrivenName {
            let selectedSymbol = investmentData?.marketData?.symbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if selectedSymbol.isEmpty {
                let tickerHint = selectedInvestmentCategory == .crypto
                    ? "Выберите монету или пару"
                    : "Выберите тикер"
                hints.append(ValidationHint(text: tickerHint, kind: .required))
            }
        } else if trimmedAccountName.isEmpty {
            hints.append(ValidationHint(text: "Заполните название продукта", kind: .required))
        }

        return hints
    }

    private var recommendedHints: [ValidationHint] {
        guard addAccountMode == .create else { return [] }
        var hints: [ValidationHint] = []
        if !hasEnteredPrimaryAmount {
            let amountHint: String
            switch selectedAccountType {
            case .card:
                amountHint = cardData?.cardType == .credit
                ? "Рекомендуется ввести кредитный лимит (можно 0)"
                : "Рекомендуется ввести сумму (можно 0)"
            case .credit:
                amountHint = "Рекомендуется ввести сумму кредита (можно 0)"
            case .investment:
                if selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto {
                    amountHint = "Рекомендуется ввести количество (можно 0)"
                } else {
                    amountHint = "Рекомендуется ввести сумму (можно 0)"
                }
            }
            hints.append(ValidationHint(text: amountHint, kind: .recommended))
        }
        if targetGroup == nil {
            hints.append(ValidationHint(text: "Рекомендуется выбрать группу для удобной фильтрации", kind: .recommended))
        }
        return hints
    }

    private var validationHints: [ValidationHint] {
        requiredHints + recommendedHints
    }

    private func focusNameFieldIfNeeded() {
        guard addAccountMode == .create, !isTickerDrivenName else {
            isNameFieldFocused = false
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            isNameFieldFocused = true
        }
    }
    
    private func addAccount() {
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
                if let editingInvestment {
                    updateInvestmentAndGroup(
                        investmentViewModel: investmentViewModel,
                        investment: editingInvestment,
                        group: targetGroup
                    )
                } else {
                    createInvestmentAndAddToGroup(investmentViewModel: investmentViewModel, group: targetGroup)
                }
                return
            }
        }
    }
    
    private func createCardAndAddToGroup(cardViewModel: CardViewModel, group: FinanceGroup?) {
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
    
    private func createCreditAndAddToGroup(creditViewModel: CreditViewModel, group: FinanceGroup?) {
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
            paymentMode: creditData.paymentMode,
            paymentDayOfMonth: creditData.paymentDayOfMonth,
            nextPaymentDate: creditData.nextPaymentDate,
            reminderEnabled: creditData.reminderEnabled,
            reminderDaysBefore: creditData.reminderDaysBefore,
            reminderTime: creditData.reminderTime,
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
    
    private func createInvestmentAndAddToGroup(investmentViewModel: InvestmentViewModel, group: FinanceGroup?) {
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

    private func updateInvestmentAndGroup(
        investmentViewModel: InvestmentViewModel,
        investment: Investment,
        group: FinanceGroup?
    ) {
        guard let investmentData = investmentData else { return }

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
            uniqueID: investment.investmentUniqueID
        ))

        let investmentID = investment.investmentUniqueID
        let descriptor = FetchDescriptor<FinanceAccount>()
        let existingAccount = (try? modelContext.fetch(descriptor))?.first(where: {
            $0.accountType == .investment && $0.accountID == investmentID
        })
        if let existingAccount {
            existingAccount.group = group
        } else {
            let link = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
            link.group = group
            modelContext.insert(link)
        }

        do {
            try modelContext.save()
        } catch {
            AppLogger.log(.error, category: "FinanceAddAccount", "Failed to update group link for investment: \(error.localizedDescription)")
        }

        viewModel.handle(.loadAccounts)
        viewModel.handle(.loadGroups)
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
        
        return nil
    }
}
