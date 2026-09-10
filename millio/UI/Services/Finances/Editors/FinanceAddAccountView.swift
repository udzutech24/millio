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
    let incomingStatementController: CashflowStatementImportController?
    @Environment(\.dismiss) var dismiss
    @Environment(\.locale) var locale
    @Environment(AppState.self) var appState
    @Environment(AppRouter.self) var router
    @Environment(\.diContainer) var diContainer

    init(
        viewModel: FinanceViewModel,
        preselectedGroup: AccountGroup? = nil,
        preselectedAccountType: FinanceAccountType? = nil,
        presentationStyle: FinanceEditorPresentationStyle = .modal,
        incomingStatementController: CashflowStatementImportController? = nil
    ) {
        self.viewModel = viewModel
        self.preselectedGroup = preselectedGroup
        self.preselectedAccountType = preselectedAccountType
        self.presentationStyle = presentationStyle
        self.incomingStatementController = incomingStatementController
    }
    
    @State var selectedAccountType: FinanceAccountType = .card
    @State var selectedGroupID: String? = nil
    @State var selectedInvestmentCategory: InvestmentCategory = .other
    @State var selectedProductTypeTitle: String = FinanceAccountType.card.displayName
    @State var selectedInvestmentPreset: FinanceAddAccountInvestmentPreset = .asset
    @State var showCreateGroup = false
    @State var cardData: InlineCardDraft?
    /// Условия договора кредита (Ф3) — отдельно от `creditData`: легаси-кортеж их не вмещает.
    @State var loanTermsDraft: LoanTermsDraft?
    @State var creditData: (name: String, amount: Double, monthlyPayment: Double, endDate: Date, remainingAmount: Double, currency: String, bank: Bank, creditType: CreditType, isFavorite: Bool, paymentMode: CreditPaymentMode, paymentDayOfMonth: Int?, nextPaymentDate: Date?, reminderEnabled: Bool, reminderDaysBefore: Int?, reminderTime: Date?, includeInTotal: Bool)?
    @State var investmentData: (name: String, investmentType: InvestmentType, category: InvestmentCategory, amount: Double, currency: String, includeInTotal: Bool, isFavorite: Bool, marketData: InvestmentMarketData?, createCashflowTransaction: Bool)?
    /// Данные формы «Вклад»/«Накопительный счёт» нового ядра (Фаза 3) — `nil` для остальных пресетов.
    @State var depositData: DepositFormData?
    @State var selectedArchivedAccountID: String? = nil
    @State var accountName: String = ""
    @FocusState var isNameFieldFocused: Bool
    @State var areHintsHidden: Bool = false
    @State var showPaywallAlert = false
    @State var paywallMessage: LocalizedTextResolver = .empty
    @State var groupIDsBeforeCreate: Set<String> = []
    @State var showProductPicker = false
    @State var hasConfirmedProductSelection = false
    @State var didInitializePresentationState = false
    /// Список счетов нужен форме один раз — на возврате с пушенного экрана `onAppear`
    /// срабатывает снова и без этого флага перечитывал бы весь стор заново.
    @State var didLoadAccounts = false
    @State var draftIconName: String? = nil
    @State var draftIconColor: String? = nil
    @State var showIconPicker = false
    @State var realEstatePropertyType: RealEstatePropertyType = .apartment
    @State var realEstatePhotoItems: [PhotosPickerItem] = []
    @State var realEstatePhotoData: [Data] = []
    @State var isProcessingRealEstatePhotos = false
    @State var realEstatePhotoError: String?
    @State var statementDraft: AccountStatementCreateDraft?
    @State var showStatementOnboarding = false

    enum HintsPrefs {
        static let hiddenKey = "finance_add_account_hints_hidden"
    }

    struct ValidationHint: Identifiable {
        enum Kind {
            case required
            case recommended
        }

        let id = UUID()
        let text: String
        let kind: Kind
    }

    var localizationLocale: Locale {
        AppLocalization.currentAppLocale
    }

    func localized(_ key: String, fallback: String? = nil) -> String {
        AppLocalization.string(key, locale: localizationLocale, fallback: fallback)
    }
    
    var navigationTitle: String {
        guard !showProductPicker else { return "" }
        return localized("finances.add_account.nav.new")
    }
    
    var resolvedGroup: AccountGroup? {
        FinanceAddAccountGroupSelection.resolveSelectedGroup(
            selectedGroupID: selectedGroupID,
            preselectedGroupID: preselectedGroup?.groupUniqueID ?? viewModel.state.selectedGroupForAccount?.groupUniqueID,
            groups: viewModel.state.groups
        )
    }

    var targetGroup: AccountGroup? {
        resolvedGroup
    }
    
    var scrollContent: some View {
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
                    statementOnboardingSection
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

    @ViewBuilder
    var navigationContent: some View {
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
        .sheet(isPresented: $showStatementOnboarding) {
            if let statementDraft {
                AccountStatementOnboardingFlow(
                    draft: statementDraft,
                    modelContext: viewModel.modelContext,
                    statementClient: statementImportClient,
                    existingController: incomingStatementController,
                    onComplete: { dismiss() }
                )
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
            if !didLoadAccounts {
                didLoadAccounts = true
                viewModel.handle(.loadAccounts)
            }
        }
        .premiumUpsellAlert(
            isPresented: $showPaywallAlert,
            titleKey: "monetization.free_plan.title",
            message: paywallMessage,
            onSubscribe: { router.push(.subscription) }
        )
    }

    @ViewBuilder
    var productPickerOverlay: some View {
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
                // Баг 2 (второй экземпляр): SwiftUI сбрасывает `@State` ДОЧЕРНЕЙ формы при смене
                // типа (structural identity — форма-класс в `switch` меняется), но РОДИТЕЛЬСКИЕ
                // `@State` этого экрана (`cardData`/`investmentData`/…) остаются от брошенной формы.
                // `cardData?.x ?? investmentData?.x` в `+CoreCreate.swift` тогда молча брал значение
                // из формы, которую пользователь уже покинул (напр. избранное с формы «Карта» для
                // только что выбранного «Счёта»). Без явного сброса здесь неоднозначность остаётся.
                cardData = nil
                investmentData = nil
                creditData = nil
                depositData = nil
                focusNameFieldIfNeeded()
            }
            .onChange(of: selectedInvestmentPreset) { _, _ in
                // Тот же Баг 2 внутри `.investment`: «Наличные»/«Счёт»/«Долг» (нужный `if/else` в
                // `createFormSections` пересоздаёт форму) и «Вклад» (другой View-тип) — переключение
                // между ними меняет `selectedInvestmentPreset`, а не `selectedAccountType`, так что
                // сброс выше не срабатывал. Путь «Наличные → Вклад → Счёт» брал избранное и сумму
                // «Наличных» для нового «Счёта» (ревью round 2). Смена ТОЛЬКО категории при том же
                // пресете (напр. «Долг» ↔ «Недвижимость») этой правкой не покрыта — там форма та же
                // самая, её решает уже сама форма, а не этот экран (отдельная задача).
                cardData = nil
                investmentData = nil
                creditData = nil
                depositData = nil
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

// Не `private`: после разрезания формы на расширения хелпер читают файлы
// `FinanceAddAccountView+Validation` и `+Entitlements`, а `private` не проходит границу файла.
extension InvestmentCategory {
    var isMarketTickerCategory: Bool {
        self == .stocks || self == .crypto
    }
}
