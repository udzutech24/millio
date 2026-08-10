//
//  FinanceAddAccountView.swift
//  millio
//

import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Finance Add Account View

struct FinanceAddAccountView: View {
    @ObservedObject var viewModel: FinanceViewModel
    let preselectedGroup: AccountGroup?
    let preselectedAccountType: FinanceAccountType?
    let presentationStyle: FinanceEditorPresentationStyle
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    init(
        viewModel: FinanceViewModel,
        preselectedGroup: AccountGroup? = nil,
        preselectedAccountType: FinanceAccountType? = nil,
        presentationStyle: FinanceEditorPresentationStyle = .modal
    ) {
        self.viewModel = viewModel
        self.preselectedGroup = preselectedGroup
        self.preselectedAccountType = preselectedAccountType
        self.presentationStyle = presentationStyle
    }
    
    @State private var selectedAccountType: FinanceAccountType = .card
    @State private var selectedGroupID: String? = nil
    @State private var selectedInvestmentCategory: InvestmentCategory = .other
    @State private var selectedProductTypeTitle: String = FinanceAccountType.card.displayName
    @State private var selectedInvestmentPreset: FinanceAddAccountInvestmentPreset = .asset
    @State private var showCreateGroup = false
    @State private var cardData: InlineCardDraft?
    @State private var creditData: (name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, paymentMode: CreditPaymentMode, paymentDayOfMonth: Int?, nextPaymentDate: Date?, reminderEnabled: Bool, reminderDaysBefore: Int?, reminderTime: Date?, includeInTotal: Bool)?
    @State private var investmentData: (name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, priority: InvestmentPriority, isFavorite: Bool, marketData: InvestmentMarketData?, createCashflowTransaction: Bool)?
    /// Данные формы «Вклад»/«Накопительный счёт» нового ядра (Фаза 3) — `nil` для остальных пресетов.
    @State private var depositData: DepositFormData?
    @State private var selectedArchivedAccountID: String? = nil
    @State private var accountName: String = ""
    @FocusState private var isNameFieldFocused: Bool
    @State private var areHintsHidden: Bool = false
    @State private var showPaywallAlert = false
    @State private var paywallMessage: LocalizedTextResolver = .empty
    @State private var groupIDsBeforeCreate: Set<String> = []
    @State private var showProductPicker = false
    @State private var hasConfirmedProductSelection = false
    @State private var didInitializePresentationState = false
    @State private var draftIconName: String? = nil
    @State private var draftIconColor: String? = nil
    @State private var showIconPicker = false
    @State private var realEstatePropertyType: RealEstatePropertyType = .apartment
    @State private var realEstatePhotoItems: [PhotosPickerItem] = []
    @State private var realEstatePhotoData: [Data] = []
    @State private var isProcessingRealEstatePhotos = false
    @State private var realEstatePhotoError: String?

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

    private var localizationLocale: Locale {
        AppLocalization.currentAppLocale
    }

    private func localized(_ key: String, fallback: String? = nil) -> String {
        AppLocalization.string(key, locale: localizationLocale, fallback: fallback)
    }
    
    private var navigationTitle: String {
        guard !showProductPicker else { return "" }
        return localized("finances.add_account.nav.new")
    }
    
    private var resolvedGroup: AccountGroup? {
        FinanceAddAccountGroupSelection.resolveSelectedGroup(
            selectedGroupID: selectedGroupID,
            preselectedGroupID: preselectedGroup?.groupUniqueID ?? viewModel.state.selectedGroupForAccount?.groupUniqueID,
            groups: viewModel.state.groups
        )
    }

    var targetGroup: AccountGroup? {
        resolvedGroup
    }
    
    // MARK: - Form Sections
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.add_account.section.name"))
            FinancesGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Button { showIconPicker = true } label: {
                            AccountIconBadgeView(
                                iconName: draftIconName,
                                iconColor: draftIconColor,
                                fallback: iconForSelectedType,
                                size: 32
                            )
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showIconPicker) {
                            AccountIconPickerSheet(
                                iconName: $draftIconName,
                                iconColor: $draftIconColor
                            )
                        }

                        TextField(placeholderForSelectedType, text: $accountName)
                            .foregroundStyle(AppColors.textPrimary)
                            .focused($isNameFieldFocused)
                            .textInputAutocapitalization(selectedAccountType == .card ? .words : .sentences)
                            .submitLabel(.done)
                            .disabled(isTickerDrivenName)
                            .opacity(isTickerDrivenName ? 0.75 : 1.0)
                    }
                    
                    if isTickerDrivenName {
                        Text(L("finances.add_account.name.autofill_hint"))
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
            return L("finances.add_account.placeholder.card")
        case .credit:
            return L("finances.add_account.placeholder.credit")
        case .investment:
            if isTickerDrivenName {
                return L("finances.add_account.placeholder.market")
            }
            if selectedInvestmentCategory == .other, selectedInvestmentPreset == .account {
                return L("finances.add_account.placeholder.account")
            }
            switch selectedInvestmentCategory {
            case .house:
                return L("finances.add_account.placeholder.investment.house")
            case .stocks:
                return L("finances.add_account.placeholder.investment.stocks")
            case .business:
                return L("finances.add_account.placeholder.investment.business")
            case .debt:
                return L("finances.add_account.placeholder.investment.debt")
            case .crypto:
                return L("finances.add_account.placeholder.investment.crypto")
            case .car:
                return L("finances.add_account.placeholder.investment.car")
            case .bonds:
                return L("finances.add_account.placeholder.investment.bonds")
            case .metals:
                return L("finances.add_account.placeholder.investment.metals")
            case .other:
                return L("finances.add_account.placeholder.investment.other")
            }
        }
    }

    private var isTickerDrivenName: Bool {
        selectedAccountType == .investment && (selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto)
    }
    
    private var accountTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.add_account.section.type"))
            FinancesGlassCard {
                Button {
                    showProductPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Text(L("finances.add_account.product.type"))
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
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var visibleInvestmentCategories: [InvestmentCategory] {
        [.house, .stocks, .business, .debt, .crypto, .other]
    }

    private var selectedProductOption: FinanceAddAccountProductOption {
        FinanceAddAccountProductOption.currentSelection(
            accountType: selectedAccountType,
            investmentCategory: selectedInvestmentCategory,
            investmentPreset: selectedInvestmentPreset
        )
    }

    private var groupRecommendations: [FinanceAddAccountGroupRecommendation] {
        guard hasConfirmedProductSelection else { return [] }
        return Array(selectedProductOption.groupRecommendations.prefix(2))
    }
    
    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("finances.add_account.section.group"))
            
            if viewModel.state.groups.isEmpty {
                FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                    VStack(spacing: 12) {
                        Text(L("finances.add_account.group.default_hint"))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Button {
                            presentCreateGroup()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.plus")
                                Text(L("finances.add_account.group.create"))
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
                let currentGroupName = resolvedGroup?.name ?? L("finances.group.ungrouped")
                let selectableGroups = viewModel.state.groups.filter { $0.name != L("finances.group.ungrouped") }
                
                FinancesGlassCard {
                    Menu {
                        Button {
                            selectedGroupID = nil
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .foregroundStyle(AppColors.textTertiary)
                                    .frame(width: 12, height: 12)

                                Text(L("finances.group.ungrouped"))
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
                            Text(L("finances.add_account.section.group"))
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
                        Text(L("finances.add_account.group.create_new"))
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

                if !groupRecommendations.isEmpty {
                    recommendedGroupsSection
                }
            }
        }
    }

    private var recommendedGroupsSection: some View {
        HStack(spacing: 10) {
            ForEach(groupRecommendations) { recommendation in
                recommendedGroupButton(recommendation)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recommendedGroupButton(_ recommendation: FinanceAddAccountGroupRecommendation) -> some View {
        let isSelected = resolvedGroup?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare(recommendation.title(locale: locale)) == .orderedSame

        return Button {
            applyGroupRecommendation(recommendation)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: recommendation.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: recommendation.accentHex))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: recommendation.accentHex).opacity(0.14))
                    )

                Text(recommendation.title(locale: locale))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: recommendation.accentHex))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.085 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        Color(hex: recommendation.accentHex).opacity(isSelected ? 0.38 : 0.18),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func presentCreateGroup() {
        groupIDsBeforeCreate = Set(viewModel.state.groups.map(\.groupUniqueID))
        showCreateGroup = true
    }

    private func applyGroupRecommendation(_ recommendation: FinanceAddAccountGroupRecommendation) {
        let suggestedName = recommendation.title(locale: locale).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suggestedName.isEmpty else { return }

        if let existingGroup = viewModel.state.groups.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(suggestedName) == .orderedSame
        }) {
            selectedGroupID = existingGroup.groupUniqueID
            return
        }

        let maxOrder = viewModel.state.groups.map(\.order).max() ?? -1
        let newGroup = AccountGroup(name: suggestedName, colorHex: recommendation.accentHex, order: maxOrder + 1)
        viewModel.modelContext.insert(newGroup)

        do {
            try viewModel.modelContext.save()
            viewModel.handle(.loadGroups)
            selectedGroupID = newGroup.groupUniqueID
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to create recommended group: \(error.localizedDescription)")
        }
    }
    
    @ViewBuilder
    private var createFormSections: some View {
        switch selectedAccountType {
        case .card:
            InlineCardCreateForm(
                name: $accountName,
                allowsTypeSwitching: true,
                selectedProductTitle: selectedProductTypeTitle,
                onOpenProductPicker: {
                    showProductPicker = true
                },
                onCardDataChanged: { card in
                    self.cardData = card
                }
            ) {
                groupSection
            }
        case .credit:
            InlineCreditCreateForm(
                name: $accountName,
                onCreditDataChanged: { data in
                    self.creditData = data
                }
            ) {
                groupSection
            }
        case .investment:
            if selectedInvestmentPreset == .deposit {
                // Вклад/накопительный счёт — новое ядро event-sourcing (Фаза 3), НЕ старый Investment(isDeposit:).
                InlineDepositCreateForm(
                    name: $accountName,
                    onDepositDataChanged: { data in self.depositData = data }
                ) {
                    groupSection
                }
            } else {
                InlineInvestmentCreateForm(
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
        if !validationHints.isEmpty, !areHintsHidden {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    FinancesSectionHeader(title: L("finances.add_account.section.hints"))
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
                    .accessibilityLabel(L("finances.add_account.hints.hide"))
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

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                if hasConfirmedProductSelection {
                    // [Вариант А, тикер-driven типы, 2026-07-18] Для акций/крипты имя авто-
                    // заполняется из тикера и уже показывается в `tickerDrivenNameSection`
                    // ПОСЛЕ выбора тикера (порядок Тип→Тикер→Название(авто)→Позиция) — общий
                    // `nameSection` сверху для них не рендерим, иначе получаем два поля с
                    // одним и тем же именем на экране одновременно.
                    if !isTickerDrivenName {
                        nameSection
                    }

                    if selectedAccountType != .card {
                        accountTypeSection
                    }

                    // Общий баннер подсказок дублирует точечные required/optional маркеры,
                    // которые тикер-driven форма уже показывает у самих полей (тикер/количество/
                    // цена) — вместо баннера оставляем маркеры. Мягкие рекомендации (группа,
                    // остаток бесплатных тикеров) при этом теряются здесь, но не блокируют
                    // сохранение — жёсткая проверка лимита тикеров всё равно есть в
                    // `validateEntitlementsForSave()` независимо от баннера.
                    if !isTickerDrivenName {
                        validationHintsSection
                    }
                    createFormSections
                    if selectedProductOption == .house {
                        realEstateCreationSection
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.immediately)
        .dismissKeyboardOnTap()
        .scrollIndicators(.hidden)
    }

    private var realEstateCreationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: L("real_estate.edit.object"))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Picker(L("real_estate.about.type"), selection: $realEstatePropertyType) {
                        ForEach(RealEstatePropertyType.allCases) { type in
                            Text(type.localizedTitle).tag(type)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    FinancesRowDivider(leadingPadding: 16)
                    PhotosPicker(
                        selection: $realEstatePhotoItems,
                        maxSelectionCount: AccountAttachmentPolicy.maximumPhotos,
                        matching: .images
                    ) {
                        HStack {
                            Label(L("real_estate.photo.add"), systemImage: "photo.badge.plus")
                            Spacer()
                            if isProcessingRealEstatePhotos { ProgressView() }
                            Text("\(realEstatePhotoData.count)/\(AccountAttachmentPolicy.maximumPhotos)")
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                    }
                    .disabled(isProcessingRealEstatePhotos)
                    if let realEstatePhotoError {
                        Text(realEstatePhotoError)
                            .font(.millioCaptionRegular)
                            .foregroundStyle(AppColors.error)
                            .padding(.horizontal, 16).padding(.bottom, 12)
                    }
                }
            }
        }
        .onChange(of: realEstatePhotoItems) { _, items in
            Task { await processRealEstateDraftPhotos(items) }
        }
    }

    private func processRealEstateDraftPhotos(_ items: [PhotosPickerItem]) async {
        await MainActor.run { isProcessingRealEstatePhotos = true; realEstatePhotoError = nil }
        do {
            var processed: [Data] = []
            for item in items.prefix(AccountAttachmentPolicy.maximumPhotos) {
                guard let source = try await item.loadTransferable(type: Data.self) else {
                    throw AccountPhotoProcessorError.invalidImage
                }
                processed.append(try await AccountPhotoProcessor().process(source))
            }
            await MainActor.run { realEstatePhotoData = processed; isProcessingRealEstatePhotos = false }
        } catch {
            await MainActor.run {
                realEstatePhotoData = []
                realEstatePhotoError = error.localizedDescription
                isProcessingRealEstatePhotos = false
            }
        }
    }
    
    @ViewBuilder
    private var navigationContent: some View {
        ZStack {
            GradientBackground()
            scrollContent
        }
        .overlay {
            productPickerOverlay
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
            if presentationStyle.showsDismissButton, !showProductPicker {
                ToolbarItem(placement: .navigationBarLeading) {
                    ToolbarGlassIconButton(
                        systemName: "xmark",
                        accessibilityLabel: L("finances.common.cancel")
                    ) {
                        dismiss()
                    }
                }
            }
            if !showProductPicker {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if hasConfirmedProductSelection, areHintsHidden, !validationHints.isEmpty {
                        Button {
                            areHintsHidden = false
                            UserDefaults.standard.set(false, forKey: HintsPrefs.hiddenKey)
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.textTertiary)
                        .accessibilityLabel(localized("finances.add_account.hints.show"))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ToolbarGlassIconButton(
                        systemName: "checkmark",
                        accessibilityLabel: localized("finances.common.add"),
                        isEnabled: hasConfirmedProductSelection && isValid,
                        isHighlighted: hasConfirmedProductSelection && isValid
                    ) {
                        addAccount()
                    }
                }
            }
        }
        .onAppear {
            areHintsHidden = UserDefaults.standard.bool(forKey: HintsPrefs.hiddenKey)
            if !didInitializePresentationState {
                didInitializePresentationState = true
                if let preselectedAccountType {
                    hasConfirmedProductSelection = true
                    selectedAccountType = preselectedAccountType
                    switch preselectedAccountType {
                    case .card:
                        selectedProductTypeTitle = FinanceAddAccountPreselection.productTitle(for: .card, locale: localizationLocale)
                    case .credit:
                        selectedProductTypeTitle = FinanceAddAccountPreselection.productTitle(for: .credit, locale: localizationLocale)
                    case .investment:
                        selectedInvestmentCategory = .other
                        selectedInvestmentPreset = .asset
                        selectedProductTypeTitle = FinanceAddAccountPreselection.productTitle(for: .investment, locale: localizationLocale)
                    }
                } else {
                    hasConfirmedProductSelection = false
                    showProductPicker = FinanceAddAccountPresentationPolicy.shouldAutoPresentTypePicker(
                        isEditingMode: false,
                        preselectedAccountType: preselectedAccountType
                    )
                }
            }
            if let preselectedGroup {
                selectedGroupID = preselectedGroup.groupUniqueID
            } else if let preselectedGroup = viewModel.state.selectedGroupForAccount {
                selectedGroupID = preselectedGroup.groupUniqueID
            } else {
                selectedGroupID = nil
            }
            viewModel.handle(.loadAccounts)
        }
        .premiumUpsellAlert(
            isPresented: $showPaywallAlert,
            titleKey: "monetization.free_plan.title",
            message: paywallMessage,
            onSubscribe: { router.push(.subscription) }
        )
    }

    @ViewBuilder
    private var productPickerOverlay: some View {
        if showProductPicker {
            GeometryReader { proxy in
                ZStack {
                    Color.black.opacity(0.58)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if hasConfirmedProductSelection {
                                showProductPicker = false
                            }
                        }

                    FinanceAddAccountProductPickerSheet(
                        availableSize: proxy.size,
                        onClose: {
                            if hasConfirmedProductSelection {
                                showProductPicker = false
                            } else {
                                dismiss()
                            }
                        },
                        onSelect: handleProductOptionSelection
                    )
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 598)
                    .padding(.top, max(12, proxy.safeAreaInsets.top + 6))
                    .padding(.bottom, max(12, proxy.safeAreaInsets.bottom + 6))
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: 18)
                                .combined(with: .scale(scale: 0.97, anchor: .center))
                                .combined(with: .opacity),
                            removal: .offset(y: 12)
                                .combined(with: .scale(scale: 0.985, anchor: .center))
                                .combined(with: .opacity)
                        )
                    )
                }
                .allowsHitTesting(true)
                .animation(.spring(response: 0.42, dampingFraction: 0.88), value: showProductPicker)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .ignoresSafeArea()
        }
    }
    
    var body: some View {
        let content = navigationContent
            .modifier(SelectedAccountTypeChangeHandler(selectedAccountType: $selectedAccountType, selectedArchivedAccountID: $selectedArchivedAccountID))
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
        if selectedProductOption == .house, isProcessingRealEstatePhotos { return false }

        switch selectedAccountType {
        case .card:
            guard let cardData else { return false }
            if cardData.cardType == .credit {
                guard let limit = cardData.creditLimit, limit > 0 else { return false }
                let last4 = cardData.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                return last4.isEmpty || (last4.count == 4 && last4.allSatisfy(\.isNumber))
            }
            return true
        case .credit:
            return creditData != nil
        case .investment:
            if selectedInvestmentPreset == .deposit {
                return depositData != nil
            }
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
            if selectedInvestmentPreset == .deposit {
                return (depositData?.amount ?? 0) != 0
            }
            guard let investmentData else { return false }
            if selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto {
                return (investmentData.marketData?.quantity ?? 0) != 0
            }
            return investmentData.amount != 0
        }
    }

    private var requiredHints: [ValidationHint] {
        var hints: [ValidationHint] = []

        if isTickerDrivenName {
                let selectedSymbol = investmentData?.marketData?.symbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if selectedSymbol.isEmpty {
                    let tickerHint = selectedInvestmentCategory == .crypto
                    ? L("finances.add_account.hint.select_coin_or_pair")
                    : L("finances.add_account.hint.select_ticker")
                    hints.append(ValidationHint(text: tickerHint, kind: .required))
                }
            } else if trimmedAccountName.isEmpty {
            hints.append(ValidationHint(text: L("finances.add_account.hint.fill_name"), kind: .required))
        }

        return hints
    }

    private var recommendedHints: [ValidationHint] {
        var hints: [ValidationHint] = []
        if !hasEnteredPrimaryAmount {
            let amountHint: String
            switch selectedAccountType {
            case .card:
                amountHint = cardData?.cardType == .credit
                ? L("finances.add_account.hint.recommended_credit_limit")
                : L("finances.add_account.hint.recommended_amount")
            case .credit:
                amountHint = L("finances.add_account.hint.recommended_credit_amount")
            case .investment:
                if selectedInvestmentCategory == .stocks || selectedInvestmentCategory == .crypto {
                    amountHint = L("finances.add_account.hint.recommended_quantity")
                } else {
                    amountHint = L("finances.add_account.hint.recommended_amount")
                }
            }
            hints.append(ValidationHint(text: amountHint, kind: .recommended))
        }
        if targetGroup == nil {
            hints.append(ValidationHint(text: L("finances.add_account.hint.recommended_group"), kind: .recommended))
        }
        if selectedAccountType == .investment,
           selectedInvestmentCategory.isMarketTickerCategory,
           canUseMarketCategory(selectedInvestmentCategory),
           EntitlementPolicy.hasTrackedTickerLimit(isPro: appState.isPro) {
            let remaining = max(0, EntitlementPolicy.freeTrackedTickerLimit - currentTrackedTickerCount)
            if !appState.isPro {
                hints.append(
                    ValidationHint(
                        text: String(
                            format: L("monetization.ticker.limit.remaining_format"),
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
        guard hasConfirmedProductSelection, !isTickerDrivenName else {
            isNameFieldFocused = false
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            isNameFieldFocused = true
        }
    }
    
    /// kind нового ядра для текущего выбора пресета «Карта»/«Счёт» — `nil` для остальных
    /// пресетов (вклад/инвестиции/… — свои резолверы). Форма теперь только для СОЗДАНИЯ:
    /// EDIT-путь легаси снесён (6b Ф5c.3), поэтому `isEditingLegacy: false`. Защитный гуард
    /// `isEditingLegacy` в мосте сохранён (гард-тест `AllPresetsOnNewCoreTests`, анамнез Фазы 6a).
    private var newCoreMoneyKindForCurrentSelection: AccountKind? {
        return AccountsCoreAdditionBridge.moneyKind(
            accountType: selectedAccountType,
            investmentPreset: selectedInvestmentPreset,
            bank: cardData?.bank ?? .other,
            isEditingLegacy: false
        )
    }

    /// kind нового ядра для пресетов «Кредит»/«Долг» (Фаза 2) — `nil` для остальных пресетов
    /// и для режима редактирования (та же причина и фикс Фазы 6a, см. `newCoreMoneyKindForCurrentSelection`).
    private var newCoreObligationKindForCurrentSelection: AccountKind? {
        return AccountsCoreAdditionBridge.obligationKind(
            accountType: selectedAccountType,
            investmentCategory: selectedInvestmentCategory,
            isEditingLegacy: false
        )
    }

    /// kind нового ядра для пресета «Вклад»/«Накопительный счёт» (Фаза 3) — `nil` для остальных
    /// пресетов и для режима редактирования (правка depositMeta — через `AccountDetailView`, не эту форму).
    private var newCoreDepositKindForCurrentSelection: AccountKind? {
        return AccountsCoreAdditionBridge.depositKind(
            accountType: selectedAccountType,
            investmentPreset: selectedInvestmentPreset,
            isEditingLegacy: false
        )
    }

    /// kind нового ядра для пресетов «Акции»/«Крипта»/«Недвижимость»/«Бизнес»/«Другое»/«Инвестиция»
    /// (Фаза 4) — `nil` для остальных пресетов (карта/счёт/вклад/кредит/долг — уже обработаны выше)
    /// и для режима редактирования. «Долг» сюда НЕ попадает — обработан `newCoreObligationKindForCurrentSelection`.
    private var newCoreAssetKindForCurrentSelection: AccountKind? {
        let hasTicker = investmentData?.marketData?.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return AccountsCoreAdditionBridge.assetKind(
            accountType: selectedAccountType,
            investmentCategory: selectedInvestmentCategory,
            investmentPreset: selectedInvestmentPreset,
            hasTicker: hasTicker,
            isEditingLegacy: false
        )
    }

    /// Создание вклада/накопительного счёта на новом ядре (Фаза 3): создаёт счёт + сразу генерирует
    /// БУДУЩИЕ interest-события по расписанию капитализации (`DepositInterestScheduler`) — карточка
    /// счёта открывается уже с прогнозом «в месяц»/«за срок», без отдельного шага «посчитать».
    private func createDepositAccountOnNewCore() {
        guard let depositData else { return }
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? selectedProductTypeTitle : trimmedName
        let group = targetGroup  // [Ф5c.7 contract] targetGroup уже core AccountGroup — bridge-резолв по имени не нужен
        let factory = AccountProductFactory(modelContext: viewModel.modelContext)

        let meta = AccountsCoreAdditionBridge.depositMeta(
            rate: Decimal(depositData.rate),
            capitalization: depositData.capitalization,
            termEnd: depositData.termEnd,
            allowsTopUp: depositData.allowsTopUp,
            allowsEarlyClose: depositData.allowsEarlyClose,
            earlyClosePenaltyShare: Decimal(depositData.earlyClosePenaltyPercent / 100),
            remindEnd: depositData.remindEnd,
            autoRollover: depositData.autoRollover
        )

        do {
            let command = try FinanceProductCreationCommandResolver.resolve(.init(
                option: .deposit,
                name: resolvedName,
                currency: depositData.currency,
                amount: Decimal(depositData.amount),
                groupID: group?.id,
                depositMeta: meta,
                note: depositData.comment.isEmpty ? nil : depositData.comment
            ))
            _ = try factory.create(command)
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось создать вклад нового ядра: \(error)")
        }
    }

    /// Создание денежного счёта («Карта»/«Счёт») на новом ядре event-sourcing (Фаза 1a-ui).
    /// Никогда не создаёт старый `Card`/`Investment` — единственная точка записи: `AccountsCoreService`.
    private func createMoneyAccountOnNewCore(kind: AccountKind) {
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? selectedProductTypeTitle : trimmedName

        let currency: String
        let openingBalance: Decimal
        var cardMeta: CardMeta?

        switch kind {
        case .cash, .debitCard:
            guard let cardData else { return }
            currency = cardData.currency
            openingBalance = Decimal(cardData.balance)
            cardMeta = CardMeta(
                bank: cardData.bank == .other ? nil : cardData.bank.rawValue,
                last4: cardData.cardNumber.isEmpty ? nil : cardData.cardNumber,
                creditLimit: cardData.cardType == .credit ? cardData.creditLimit.map { Decimal($0) } : nil
            )
        default: // .bankAccount
            guard let investmentData else { return }
            currency = investmentData.currency
            openingBalance = Decimal(investmentData.amount)
        }

        let group = targetGroup  // [Ф5c.7 contract] targetGroup уже core AccountGroup — bridge-резолв по имени не нужен
        let factory = AccountProductFactory(modelContext: viewModel.modelContext)
        do {
            let command = try FinanceProductCreationCommandResolver.resolve(.init(
                option: selectedProductOption,
                name: resolvedName,
                currency: currency,
                amount: openingBalance,
                includeInTotal: cardData?.includeInTotal ?? investmentData?.includeInTotal ?? true,
                groupID: group?.id,
                cardType: cardData?.cardType,
                bank: cardData?.bank,
                cardLast4: cardData?.cardNumber,
                creditLimit: cardMeta?.creditLimit,
                statementDay: cardData?.statementDay,
                dueDay: cardData?.dueDay,
                minPayment: cardData?.minPayment.map { Decimal($0) },
                graceDays: cardData?.graceDays,
                note: cardData?.note
            ))
            _ = try factory.create(command)
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось создать денежный счёт нового ядра: \(error)")
        }
    }

    /// Создание обязательства («Кредит»/«Долг») на новом ядре event-sourcing (Фаза 2).
    /// Никогда не создаёт старый `Credit`/`Investment(debt)` — единственная точка записи: `AccountsCoreService`.
    private func createObligationAccountOnNewCore(kind: AccountKind) {
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? selectedProductTypeTitle : trimmedName
        let group = targetGroup  // [Ф5c.7 contract] targetGroup уже core AccountGroup — bridge-резолв по имени не нужен
        let factory = AccountProductFactory(modelContext: viewModel.modelContext)

        do {
            switch kind {
            case .loan:
                guard let creditData else { return }
                let meta = AccountsCoreAdditionBridge.loanMeta(
                    principal: Decimal(creditData.amount),
                    monthlyPayment: creditData.monthlyPayment > 0 ? Decimal(creditData.monthlyPayment) : nil,
                    paymentDay: creditData.paymentDayOfMonth,
                    termEnd: creditData.endDate
                )
                // openingBalance — ТЕКУЩИЙ остаток долга (remainingAmount), не первоначальная сумма
                // (principal хранится отдельно в loanMeta для отображения) — движок C сам сделает знак минус.
                let command = try FinanceProductCreationCommandResolver.resolve(.init(
                    option: .credit,
                    name: resolvedName,
                    currency: creditData.currency,
                    amount: Decimal(creditData.remainingAmount),
                    includeInTotal: creditData.includeInTotal,
                    groupID: group?.id,
                    loanMeta: meta
                ))
                _ = try factory.create(command)
            case .debt:
                guard let investmentData else { return }
                let direction: DebtDirection = investmentData.investmentType == .positive ? .owedToMe : .owedByMe
                let command = try FinanceProductCreationCommandResolver.resolve(.init(
                    option: .debt,
                    name: resolvedName,
                    currency: investmentData.currency,
                    amount: Decimal(investmentData.amount),
                    includeInTotal: investmentData.includeInTotal,
                    groupID: group?.id,
                    debtDirection: direction
                ))
                _ = try factory.create(command)
            default:
                return
            }
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось создать обязательство нового ядра: \(error)")
        }
    }

    /// Создание рыночного/ручного актива на новом ядре event-sourcing (Фаза 4). Никогда не создаёт
    /// старый `Investment` — единственная точка записи: `AccountsCoreService`.
    private func createAssetAccountOnNewCore(kind: AccountKind) {
        guard let investmentData else { return }
        let trimmedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? selectedProductTypeTitle : trimmedName
        let group = targetGroup  // [Ф5c.7 contract] targetGroup уже core AccountGroup — bridge-резолв по имени не нужен
        let factory = AccountProductFactory(modelContext: viewModel.modelContext)

        do {
            switch kind {
            case .marketInvestment:
                guard let marketData = investmentData.marketData,
                      let symbol = marketData.symbol?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !symbol.isEmpty,
                      let quantity = marketData.quantity else { return }
                // Цена ПОКУПКИ — приоритет `purchaseUnitPrice` (пользователь ввёл вручную), иначе
                // последняя известная рыночная цена на момент выбора тикера (брифинг Фазы 4, задача 1).
                let unitPrice = Decimal(marketData.purchaseUnitPrice ?? marketData.unitPrice ?? 0)
                let currency = (marketData.currency?.isEmpty == false) ? marketData.currency! : investmentData.currency
                let command = try FinanceProductCreationCommandResolver.resolve(.init(
                    option: selectedProductOption,
                    name: resolvedName,
                    currency: currency,
                    amount: Decimal(investmentData.amount),
                    includeInTotal: investmentData.includeInTotal,
                    groupID: group?.id,
                    marketSymbol: symbol,
                    marketQuantity: Decimal(quantity),
                    marketUnitPrice: unitPrice
                ))
                _ = try factory.create(command)
            case .manualAsset:
                let command = try FinanceProductCreationCommandResolver.resolve(.init(
                    option: selectedProductOption,
                    name: resolvedName,
                    currency: investmentData.currency,
                    amount: Decimal(investmentData.amount),
                    includeInTotal: investmentData.includeInTotal,
                    groupID: group?.id,
                    marketSymbol: nil
                ))
                if selectedProductOption == .house {
                    let propertyType = realEstatePropertyType
                    let photoData = realEstatePhotoData
                    _ = try factory.create(command, graphEnricher: { graph, transactionContext in
                        transactionContext.insert(RealEstateProfile(
                            accountID: graph.account.id,
                            propertyType: propertyType
                        ))
                        for (index, data) in photoData.enumerated() {
                            transactionContext.insert(AccountAttachment(
                                accountID: graph.account.id,
                                order: index,
                                isCover: index == 0,
                                mediaData: data
                            ))
                        }
                    })
                } else {
                    _ = try factory.create(command)
                }
            default:
                return
            }
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Не удалось создать актив нового ядра: \(error)")
        }
    }

    private func addAccount() {
        guard validateEntitlementsForSave() else { return }

        if let newCoreKind = newCoreMoneyKindForCurrentSelection {
            createMoneyAccountOnNewCore(kind: newCoreKind)
            return
        }

        if newCoreDepositKindForCurrentSelection != nil {
            createDepositAccountOnNewCore()
            return
        }

        if let newCoreObligationKind = newCoreObligationKindForCurrentSelection {
            createObligationAccountOnNewCore(kind: newCoreObligationKind)
            return
        }

        if let newCoreAssetKind = newCoreAssetKindForCurrentSelection {
            createAssetAccountOnNewCore(kind: newCoreAssetKind)
            return
        }

        // Все 11 create-пресетов резолвятся в один core-kind выше (гард-тест
        // `AllPresetsOnNewCoreTests`) — легаси-writer'ы (Card/Credit/Investment) недостижимы
        // после сноса EDIT-пути (6b Ф5c.3). Сюда управление в норме не доходит.
    }

    // [Ф5c.7 Gate C] Не `private` — минимально доступная точка для characterization-тестов
    // (SwiftUI View как обычный struct, `@testable import` не видит `private`). Поведение не менялось.
    //
    // Дедуп twin-пар (легаси↔core) «по построению»: конвертированный легаси архивируется
    // (`archivedAt` выставлен мигратором) и поэтому исключён из `available*` (эти массивы уже не
    // включают архивные — см. `FinanceAccountService.loadAccounts`); core-двойник учтён через
    // `state.coreAccounts`, который заполняется `participates(on:)`-фильтром (`archivedAt`+
    // `includeInTotal`, `FinanceViewModel.loadCoreEntities`) — тот же принцип исключения архива,
    // что и у `available*`. Одна и та же учётная единица не может одновременно быть в обоих
    // множествах — сложение без пересечения.
    var currentTrackedTickerCount: Int {
        let legacyCount = viewModel.state.availableInvestments.reduce(into: 0) { partialResult, investment in
            if investment.category.isMarketTickerCategory {
                partialResult += 1
            }
        }
        // Паритет с легаси: считаются ТОЛЬКО акции/крипта (`isMarketTickerCategory`), не
        // облигации/металлы — те же 2 из 4 `MarketAssetClass`, что и `InvestmentCategory`.
        let coreCount = viewModel.state.accounts.filter { account in
            guard account.kind == .marketInvestment, let assetClass = account.marketMeta?.assetClass else {
                return false
            }
            return assetClass == .stock || assetClass == .crypto
        }.count
        return legacyCount + coreCount
    }

    var currentFinanceProductCount: Int {
        viewModel.state.availableCards.count
        + viewModel.state.availableCredits.count
        + viewModel.state.availableInvestments.count
        + viewModel.state.accounts.count
    }

    private var isCreatingNewTrackedTicker: Bool {
        guard selectedAccountType == .investment else { return false }
        guard selectedInvestmentCategory.isMarketTickerCategory else { return false }
        return true
    }

    private func validateEntitlementsForSave() -> Bool {
        let canAddProduct = EntitlementPolicy.canAddFinanceProduct(
            isPro: appState.isPro,
            currentProducts: currentFinanceProductCount
        )
        guard canAddProduct else {
            paywallMessage = LocalizedTextResolver { locale in
                String(
                    format: AppLocalization.string("monetization.finance.products.limit.hard_format", locale: locale),
                    locale: locale,
                    EntitlementPolicy.freeFinanceProductLimit
                )
            }
            showPaywallAlert = true
            return false
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
            paywallMessage = LocalizedTextResolver { locale in
                String(
                    format: AppLocalization.string("monetization.ticker.limit.hard_format", locale: locale),
                    locale: locale,
                    EntitlementPolicy.freeTrackedTickerLimit
                )
            }
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

    private func marketCategoryPaywallMessage(for category: InvestmentCategory) -> LocalizedTextResolver {
        switch category {
        case .stocks:
            return .key("monetization.finance.stocks.pro_only")
        case .crypto:
            return .key("monetization.finance.crypto.pro_only")
        default:
            return .key("monetization.finance.market_assets.pro_only")
        }
    }

    private func handleProductOptionSelection(_ option: FinanceAddAccountProductOption) {
        let selection = option.selection(locale: localizationLocale)

        if selection.investmentCategory.isMarketTickerCategory,
           !canUseMarketCategory(selection.investmentCategory) {
            paywallMessage = marketCategoryPaywallMessage(for: selection.investmentCategory)
            showPaywallAlert = true
            return
        }

        selectedAccountType = selection.accountType
        selectedInvestmentCategory = selection.investmentCategory
        selectedInvestmentPreset = selection.investmentPreset
        selectedProductTypeTitle = selection.title
        hasConfirmedProductSelection = true
        showProductPicker = false
        focusNameFieldIfNeeded()
    }

}

// MARK: - ViewModifier Helpers for FinanceAddAccountView

private struct SelectedAccountTypeChangeHandler: ViewModifier {
    @Binding var selectedAccountType: FinanceAccountType
    @Binding var selectedArchivedAccountID: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: selectedAccountType) { oldValue, newValue in
                if oldValue != newValue {
                    // Смена типа сбрасывает выбор архивного счёта; формы пересоздаются
                    // самим switch по selectedAccountType (structural identity → @State reset).
                    selectedArchivedAccountID = nil
                }
            }
    }
}

// MARK: - Group Selection Helper

enum FinanceAddAccountGroupSelection {
    static func resolveSelectedGroup(
        selectedGroupID: String?,
        preselectedGroupID: String?,
        groups: [AccountGroup]
    ) -> AccountGroup? {
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
