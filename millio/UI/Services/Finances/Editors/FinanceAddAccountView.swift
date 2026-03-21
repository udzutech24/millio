//
//  FinanceAddAccountView.swift
//  millio
//

import SwiftUI
import SwiftData

// MARK: - Finance Add Account View

struct FinanceAddAccountView: View {
    @ObservedObject var viewModel: FinanceViewModel
    let editingCard: Card?
    let editingCredit: Credit?
    let editingInvestment: Investment?
    let preselectedGroup: FinanceGroup?
    let preselectedAccountType: FinanceAccountType?
    let presentationStyle: FinanceEditorPresentationStyle
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    init(
        viewModel: FinanceViewModel,
        editingCard: Card? = nil,
        editingCredit: Credit? = nil,
        editingInvestment: Investment? = nil,
        preselectedGroup: FinanceGroup? = nil,
        preselectedAccountType: FinanceAccountType? = nil,
        presentationStyle: FinanceEditorPresentationStyle = .modal
    ) {
        self.viewModel = viewModel
        self.editingCard = editingCard
        self.editingCredit = editingCredit
        self.editingInvestment = editingInvestment
        self.preselectedGroup = preselectedGroup
        self.preselectedAccountType = preselectedAccountType
        self.presentationStyle = presentationStyle
    }
    
    private enum AddAccountMode: String, CaseIterable, Identifiable {
        case create
        case archived
        
        var id: String { rawValue }
        
        var title: String {
            switch self {
            case .create:
                String(localized: "finances.add_account.mode.create")
            case .archived:
                String(localized: "finances.add_account.mode.archived")
            }
        }
    }
    
    @State private var selectedAccountType: FinanceAccountType = .card
    @State private var addAccountMode: AddAccountMode = .create
    @State private var selectedGroupID: String? = nil
    @State private var selectedInvestmentCategory: InvestmentCategory = .other
    @State private var selectedProductTypeTitle: String = FinanceAccountType.card.displayName
    @State private var selectedInvestmentPreset: FinanceAddAccountInvestmentPreset = .asset
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
    @State private var showPaywallAlert = false
    @State private var paywallMessage = ""
    @State private var groupIDsBeforeCreate: Set<String> = []

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
        (editingCard == nil && editingCredit == nil && editingInvestment == nil)
            ? String(localized: "finances.add_account.nav.new")
            : String(localized: "finances.add_account.nav.edit")
    }
    
    private var resolvedGroup: FinanceGroup? {
        FinanceAddAccountGroupSelection.resolveSelectedGroup(
            selectedGroupID: selectedGroupID,
            preselectedGroupID: preselectedGroup?.groupUniqueID ?? viewModel.state.selectedGroupForAccount?.groupUniqueID,
            groups: viewModel.state.groups
        )
    }
    
    var targetGroup: FinanceGroup? {
        resolvedGroup
    }
    
    // MARK: - Form Sections
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.name"))
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
                        Text(String(localized: "finances.add_account.name.autofill_hint"))
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
            return String(localized: "finances.add_account.placeholder.card")
        case .credit:
            return String(localized: "finances.add_account.placeholder.credit")
        case .investment:
            if isTickerDrivenName {
                return String(localized: "finances.add_account.placeholder.market")
            }
            if selectedInvestmentCategory == .other, selectedInvestmentPreset == .account {
                return String(localized: "finances.add_account.placeholder.account")
            }
            switch selectedInvestmentCategory {
            case .house:
                return String(localized: "finances.add_account.placeholder.investment.house")
            case .stocks:
                return String(localized: "finances.add_account.placeholder.investment.stocks")
            case .business:
                return String(localized: "finances.add_account.placeholder.investment.business")
            case .debt:
                return String(localized: "finances.add_account.placeholder.investment.debt")
            case .crypto:
                return String(localized: "finances.add_account.placeholder.investment.crypto")
            case .car:
                return String(localized: "finances.add_account.placeholder.investment.car")
            case .bonds:
                return String(localized: "finances.add_account.placeholder.investment.bonds")
            case .metals:
                return String(localized: "finances.add_account.placeholder.investment.metals")
            case .other:
                return String(localized: "finances.add_account.placeholder.investment.other")
            }
        }
    }

    private var isTickerDrivenName: Bool {
        selectedAccountType == .investment && (selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto)
    }
    
    private var accountTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.type"))
            FinancesGlassCard {
                Menu {
                    Button {
                        selectedAccountType = .card
                        selectedProductTypeTitle = FinanceAccountType.card.displayName
                    } label: {
                        Label(FinanceAccountType.card.displayName, systemImage: FinanceAccountType.card.icon)
                    }
                    Button {
                        selectedAccountType = .investment
                        selectedInvestmentCategory = .other
                        selectedInvestmentPreset = .account
                        selectedProductTypeTitle = String(localized: "finances.add_account.product.account")
                    } label: {
                        Label(String(localized: "finances.add_account.product.account"), systemImage: "building.columns.fill")
                    }

                    Button {
                        selectedAccountType = .credit
                        selectedProductTypeTitle = FinanceAccountType.credit.displayName
                    } label: {
                        Label(FinanceAccountType.credit.displayName, systemImage: FinanceAccountType.credit.icon)
                    }

                    if addAccountMode == .create {
                        Button {
                            selectedAccountType = .investment
                            selectedInvestmentCategory = .other
                            selectedInvestmentPreset = .asset
                            selectedProductTypeTitle = String(localized: "finances.account.type.investment")
                        } label: {
                            Label(String(localized: "finances.account.type.investment"), systemImage: FinanceAccountType.investment.icon)
                        }

                        ForEach(visibleInvestmentCategories, id: \.self) { category in
                            Button {
                                selectedAccountType = .investment
                                selectedInvestmentCategory = category
                                selectedInvestmentPreset = .category
                                selectedProductTypeTitle = category.displayName
                            } label: {
                                Label(category.displayName, systemImage: category.icon)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(String(localized: "finances.add_account.product.type"))
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
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.group"))
            
            if viewModel.state.groups.isEmpty {
                FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                    VStack(spacing: 12) {
                        Text(String(localized: "finances.add_account.group.default_hint"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Button {
                            presentCreateGroup()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.plus")
                                Text(String(localized: "finances.add_account.group.create"))
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
                let currentGroupName = resolvedGroup?.name ?? String(localized: "finances.group.ungrouped")
                let selectableGroups = viewModel.state.groups.filter { $0.name != String(localized: "finances.group.ungrouped") }
                
                FinancesGlassCard {
                    Menu {
                        Button {
                            selectedGroupID = nil
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .foregroundStyle(AppColors.textTertiary)
                                    .frame(width: 12, height: 12)

                                Text(String(localized: "finances.group.ungrouped"))
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
                            Text(String(localized: "finances.add_account.section.group"))
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
                    presentCreateGroup()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                        Text(String(localized: "finances.add_account.group.create_new"))
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

    private func presentCreateGroup() {
        groupIDsBeforeCreate = Set(viewModel.state.groups.map(\.groupUniqueID))
        showCreateGroup = true
    }
    
    private var addAccountModeSection: some View {
        EmptyView()
    }

    private var isEditingMode: Bool {
        editingCard != nil || editingCredit != nil || editingInvestment != nil
    }
    
    @ViewBuilder
    private var createFormSections: some View {
        switch selectedAccountType {
        case .card:
            if cardViewModel == nil {
                VStack(alignment: .leading, spacing: 10) {
                    FinancesSectionHeader(title: editingCard == nil ? String(localized: "finances.add_account.card.create") : String(localized: "finances.add_account.card.edit"))
                    FinancesGlassCard(contentPadding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)) {
                        ProgressView()
                            .tint(AppColors.textPrimary)
                            .task {
                                let vm = CardViewModel(modelContext: modelContext)
                                if let editingCard {
                                    vm.handle(.editCard(editingCard))
                                } else {
                                    vm.handle(.addCard)
                                }
                                cardViewModel = vm
                            }
                    }
                }
                groupSection
            } else if let vm = cardViewModel {
                InlineCardCreateForm(
                    viewModel: vm,
                    name: $accountName,
                    allowsTypeSwitching: !isEditingMode,
                    selectedProductType: selectedAccountType,
                    selectedInvestmentCategory: selectedInvestmentCategory,
                    onProductTypeSelected: { selectedAccountType = $0 },
                    onProductTitleSelected: { selectedProductTypeTitle = $0 },
                    onInvestmentPresetSelected: { selectedInvestmentPreset = $0 },
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
                    FinancesSectionHeader(title: editingCredit == nil ? String(localized: "finances.add_account.credit.create") : String(localized: "finances.add_account.credit.edit"))
                    FinancesGlassCard(contentPadding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)) {
                        ProgressView()
                            .tint(AppColors.textPrimary)
                            .task {
                                let vm = CreditViewModel(modelContext: modelContext)
                                if let editingCredit {
                                    vm.handle(.editCredit(editingCredit))
                                } else {
                                    vm.handle(.addCredit)
                                }
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
                    FinancesSectionHeader(title: editingInvestment == nil ? String(localized: "finances.add_account.investment.create") : String(localized: "finances.add_account.investment.edit"))
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
                    FinancesSectionHeader(title: String(localized: "finances.add_account.section.hints"))
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
                    .accessibilityLabel(String(localized: "finances.add_account.hints.hide"))
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
            FinancesSectionHeader(title: String(localized: "finances.add_account.section.archived"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    switch selectedAccountType {
                    case .card:
                        if viewModel.state.archivedCards.isEmpty {
                            Text(String(localized: "finances.add_account.archived.cards.empty"))
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
                            Text(String(localized: "finances.add_account.archived.credits.empty"))
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
                            Text(String(localized: "finances.add_account.archived.investments.empty"))
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
                
                if !isEditingMode && selectedAccountType != .card {
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
                    if let createdGroup = FinanceGroupCreationDetector.detectCreatedGroup(
                        previousGroupIDs: groupIDsBeforeCreate,
                        groups: viewModel.state.groups
                    ) {
                        selectedGroupID = createdGroup.groupUniqueID
                    }
                    groupIDsBeforeCreate = []
            }
        }
        .toolbar {
            if presentationStyle.showsDismissButton {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarGlassIconButton(
                        systemName: "xmark",
                        accessibilityLabel: String(localized: "finances.common.cancel")
                    ) {
                        dismiss()
                    }
                }
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
                    .accessibilityLabel(String(localized: "finances.add_account.hints.show"))
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                ToolbarGlassIconButton(
                    systemName: "checkmark",
                    accessibilityLabel: isEditingMode
                    ? String(localized: "finances.common.save")
                    : String(localized: "finances.common.add"),
                    isEnabled: isValid,
                    isHighlighted: isValid
                ) {
                    addAccount()
                }
            }
        }
        .onAppear {
            areHintsHidden = UserDefaults.standard.bool(forKey: HintsPrefs.hiddenKey)
            if let editingCard {
                selectedAccountType = .card
                selectedProductTypeTitle = FinanceAccountType.card.displayName
                accountName = editingCard.name
            } else if let editingCredit {
                selectedAccountType = .credit
                selectedProductTypeTitle = FinanceAccountType.credit.displayName
                accountName = editingCredit.name
            } else if let editingInvestment {
                selectedAccountType = .investment
                selectedInvestmentCategory = editingInvestment.category
                selectedInvestmentPreset = .category
                selectedProductTypeTitle = editingInvestment.category.displayName
                accountName = editingInvestment.name
            } else if let preselectedAccountType {
                selectedAccountType = preselectedAccountType
                switch preselectedAccountType {
                case .card:
                    selectedProductTypeTitle = FinanceAddAccountPreselection.productTitle(for: .card)
                case .credit:
                    selectedProductTypeTitle = FinanceAddAccountPreselection.productTitle(for: .credit)
                case .investment:
                    selectedInvestmentCategory = .other
                    selectedInvestmentPreset = .asset
                    selectedProductTypeTitle = FinanceAddAccountPreselection.productTitle(for: .investment)
                }
            }
            if let preselectedGroup {
                selectedGroupID = preselectedGroup.groupUniqueID
            } else if let preselectedGroup = viewModel.state.selectedGroupForAccount {
                selectedGroupID = preselectedGroup.groupUniqueID
            } else if let editingCard {
                let editingID = editingCard.cardUniqueID
                let descriptor = FetchDescriptor<FinanceAccount>()
                let accountLink = (try? modelContext.fetch(descriptor))?.first(where: {
                    $0.accountType == .card && $0.accountID == editingID
                })
                selectedGroupID = accountLink?.group?.groupUniqueID
            } else if let editingCredit {
                let editingID = editingCredit.creditUniqueID
                let descriptor = FetchDescriptor<FinanceAccount>()
                let accountLink = (try? modelContext.fetch(descriptor))?.first(where: {
                    $0.accountType == .credit && $0.accountID == editingID
                })
                selectedGroupID = accountLink?.group?.groupUniqueID
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
        .premiumUpsellAlert(
            isPresented: $showPaywallAlert,
            titleKey: "Ограничение Free-плана",
            message: paywallMessage,
            onSubscribe: { router.push(.subscription) }
        )
    }
    
    var body: some View {
        let content = navigationContent
            .modifier(SelectedAccountTypeChangeHandler(selectedAccountType: $selectedAccountType, cardViewModel: $cardViewModel, creditViewModel: $creditViewModel, investmentViewModel: $investmentViewModel, selectedArchivedAccountID: $selectedArchivedAccountID))
            .onChange(of: selectedAccountType) { _, _ in
                focusNameFieldIfNeeded()
            }
            .onChange(of: selectedInvestmentCategory) { _, newValue in
                if newValue == .stocks || newValue == .crypto {
                    if !canUseMarketCategory(newValue) {
                        paywallMessage = marketCategoryPaywallMessage(for: newValue)
                        showPaywallAlert = true
                        selectedInvestmentCategory = .other
                        return
                    }
                }
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

        if presentationStyle.wrapsInNavigationStack {
            NavigationStack {
                content
            }
        } else {
            content
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
                    ? String(localized: "finances.add_account.hint.select_coin_or_pair")
                    : String(localized: "finances.add_account.hint.select_ticker")
                    hints.append(ValidationHint(text: tickerHint, kind: .required))
                }
            } else if trimmedAccountName.isEmpty {
            hints.append(ValidationHint(text: String(localized: "finances.add_account.hint.fill_name"), kind: .required))
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
                ? String(localized: "finances.add_account.hint.recommended_credit_limit")
                : String(localized: "finances.add_account.hint.recommended_amount")
            case .credit:
                amountHint = String(localized: "finances.add_account.hint.recommended_credit_amount")
            case .investment:
                if selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto {
                    amountHint = String(localized: "finances.add_account.hint.recommended_quantity")
                } else {
                    amountHint = String(localized: "finances.add_account.hint.recommended_amount")
                }
            }
            hints.append(ValidationHint(text: amountHint, kind: .recommended))
        }
        if targetGroup == nil {
            hints.append(ValidationHint(text: String(localized: "finances.add_account.hint.recommended_group"), kind: .recommended))
        }
        if selectedAccountType == .investment,
           selectedInvestmentCategory.isMarketTickerCategory,
           canUseMarketCategory(selectedInvestmentCategory) {
            let remaining = max(0, EntitlementPolicy.freeTrackedTickerLimit - currentTrackedTickerCount)
            if !appState.isPro {
                hints.append(
                    ValidationHint(
                        text: String(
                            format: String(localized: "monetization.ticker.limit.remaining_format"),
                            remaining,
                            EntitlementPolicy.freeTrackedTickerLimit
                        ),
                        kind: .recommended
                    )
                )
            }
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
        guard validateEntitlementsForSave() else { return }

        switch selectedAccountType {
        case .card:
            if let cardViewModel = cardViewModel {
                if let editingCard {
                    updateCardAndGroup(
                        cardViewModel: cardViewModel,
                        card: editingCard,
                        group: targetGroup
                    )
                } else {
                    createCardAndAddToGroup(cardViewModel: cardViewModel, group: targetGroup)
                }
                return
            }
        case .credit:
            if let creditViewModel = creditViewModel {
                if let editingCredit {
                    updateCreditAndGroup(
                        creditViewModel: creditViewModel,
                        credit: editingCredit,
                        group: targetGroup
                    )
                } else {
                    createCreditAndAddToGroup(creditViewModel: creditViewModel, group: targetGroup)
                }
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

    private var currentTrackedTickerCount: Int {
        viewModel.state.availableInvestments.reduce(into: 0) { partialResult, investment in
            if investment.category.isMarketTickerCategory {
                partialResult += 1
            }
        }
    }

    private var currentFinanceProductCount: Int {
        viewModel.state.availableCards.count
        + viewModel.state.availableCredits.count
        + viewModel.state.availableInvestments.count
    }

    private var isCreatingNewTrackedTicker: Bool {
        guard selectedAccountType == .investment else { return false }
        guard selectedInvestmentCategory.isMarketTickerCategory else { return false }

        if let editingInvestment {
            return !editingInvestment.category.isMarketTickerCategory
        }
        return true
    }

    private func validateEntitlementsForSave() -> Bool {
        if addAccountMode == .create {
            let canAddProduct = EntitlementPolicy.canAddFinanceProduct(
                isPro: appState.isPro,
                currentProducts: currentFinanceProductCount
            )
            guard canAddProduct else {
                paywallMessage = String(
                    format: String(localized: "monetization.finance.products.limit.hard_format"),
                    EntitlementPolicy.freeFinanceProductLimit
                )
                showPaywallAlert = true
                return false
            }
        }

        if selectedAccountType == .investment,
           selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto,
           !canUseMarketCategory(selectedInvestmentCategory) {
            paywallMessage = marketCategoryPaywallMessage(for: selectedInvestmentCategory)
            showPaywallAlert = true
            return false
        }

        guard isCreatingNewTrackedTicker else { return true }

        let canAdd = EntitlementPolicy.canAddTrackedTicker(
            isPro: appState.isPro,
            currentTrackedTickers: currentTrackedTickerCount
        )
        guard canAdd else {
            paywallMessage = String(
                format: String(localized: "monetization.ticker.limit.hard_format"),
                EntitlementPolicy.freeTrackedTickerLimit
            )
            showPaywallAlert = true
            return false
        }
        return true
    }

    private func canUseMarketCategory(_ category: InvestmentCategory) -> Bool {
        switch category {
        case .stocks:
            return EntitlementPolicy.canUseFinanceStocks(isPro: appState.isPro)
        case .crypto:
            return EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro)
        default:
            return true
        }
    }

    private func marketCategoryPaywallMessage(for category: InvestmentCategory) -> String {
        switch category {
        case .stocks:
            return String(localized: "monetization.finance.stocks.pro_only")
        case .crypto:
            return String(localized: "monetization.finance.crypto.pro_only")
        default:
            return String(localized: "monetization.finance.market_assets.pro_only")
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

    private func updateCardAndGroup(cardViewModel: CardViewModel, card: Card, group: FinanceGroup?) {
        guard let cardData = cardData else { return }

        if cardData.uniqueID.isEmpty {
            cardData.uniqueID = card.uniqueID
        }

        cardViewModel.handle(.editCard(card))
        cardViewModel.handle(.updateCard(cardData))

        viewModel.handle(.addAccountToGroup(
            accountType: .card,
            accountID: card.cardUniqueID,
            group: group
        ))
        dismiss()
    }

    private func updateCreditAndGroup(creditViewModel: CreditViewModel, credit: Credit, group: FinanceGroup?) {
        guard let creditData = creditData else { return }

        creditViewModel.handle(.editCredit(credit))
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
            uniqueID: credit.creditUniqueID
        ))

        viewModel.handle(.addAccountToGroup(
            accountType: .credit,
            accountID: credit.creditUniqueID,
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

        viewModel.handle(.addAccountToGroup(
            accountType: .investment,
            accountID: investment.investmentUniqueID,
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
        
        return nil
    }
}

private extension InvestmentCategory {
    var isMarketTickerCategory: Bool {
        self == .stocks || self == .crypto
    }
}
