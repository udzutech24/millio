import SwiftUI
import SwiftData
import UIKit

struct QuickSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @FocusState private var focusedField: FocusField?
    @StateObject private var viewModel: QuickSetupViewModel
    @State private var showLanguageSheet = false
    @State private var showPrimaryCurrencySheet = false
    @State private var showFavoritesSheet = false
    @State private var showMarketSearchSheet = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showCelebrate = false
    @State private var productAmountDisplayText = ""
    @State private var productQuantityDisplayText = ""
    @State private var productPurchasePriceDisplayText = ""
    @State private var productCurrentPriceDisplayText = ""
    @State private var isGroupSetupCollapsed = false

    private let mode: QuickSetupFlowMode
    private let onCompleted: (() -> Void)?
    private let onSkipped: (() -> Void)?

    private enum FocusField: Hashable {
        case productName
        case productAmount
        case productQuantity
        case productPurchasePrice
    }

    private var expenseCategoryGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 90), spacing: 8),
            GridItem(.flexible(minimum: 90), spacing: 8),
            GridItem(.flexible(minimum: 90), spacing: 8)
        ]
    }

    private var productTypeGridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 84), spacing: 8),
            GridItem(.flexible(minimum: 84), spacing: 8),
            GridItem(.flexible(minimum: 84), spacing: 8)
        ]
    }

    init(
        appState: AppState,
        mode: QuickSetupFlowMode,
        onCompleted: (() -> Void)? = nil,
        onSkipped: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: QuickSetupViewModel(appState: appState))
        self.mode = mode
        self.onCompleted = onCompleted
        self.onSkipped = onSkipped
    }

    init(
        viewModel: QuickSetupViewModel,
        mode: QuickSetupFlowMode,
        onCompleted: (() -> Void)? = nil,
        onSkipped: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.mode = mode
        self.onCompleted = onCompleted
        self.onSkipped = onSkipped
    }

    private var quickSetupLocale: Locale {
        viewModel.selectedLanguage.locale ?? Locale.current
    }

    private func quickSetupText(ru: String, en: String) -> String {
        QuickSetupLocalization.text(locale: quickSetupLocale, ru: ru, en: en)
    }

    var body: some View {
        ZStack {
            quickSetupBackground

            VStack(spacing: 0) {
                header

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            progressBar
                            stepHero
                            stepContent
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, focusedField == nil ? 20 : 320)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .background(
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { focusedField = nil }
                    )
                    .onChange(of: focusedField) { _, newValue in
                        guard let newValue else { return }
                        DispatchQueue.main.async {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActions
                .padding(.top, 14)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .background(bottomBarBackground)
        }
        .navigationBarBackButtonHidden(mode == .onboarding)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(quickSetupText(ru: "Готово", en: "Done")) { focusedField = nil }
            }
        }
        .sheet(isPresented: $showLanguageSheet) {
            NavigationStack {
                LanguageSelectionView(
                    selectedLanguage: $viewModel.selectedLanguage,
                    availableLanguages: viewModel.availableLanguages
                )
            }
        }
        .sheet(isPresented: $showPrimaryCurrencySheet) {
            NavigationStack {
                QuickSetupPrimaryCurrencySheet(
                    primaryCurrencyCode: $viewModel.primaryCurrencyCode,
                    locale: quickSetupLocale,
                    suggestedCodes: viewModel.recommendedCurrencyCodes
                )
            }
        }
        .sheet(isPresented: $showFavoritesSheet) {
            NavigationStack {
                QuickSetupFavoriteCurrenciesSheet(
                    locale: quickSetupLocale,
                    primaryCurrencyCode: viewModel.primaryCurrencyCode,
                    selectedCodes: viewModel.favoriteCurrencyCodes,
                    suggestedCodes: viewModel.recommendedCurrencyCodes,
                    maxSelection: QuickSetupViewModel.maxFavoriteCurrencies,
                    onToggle: viewModel.toggleFavoriteCurrency
                )
            }
        }
        .sheet(isPresented: $showMarketSearchSheet) {
            MarketSymbolSearchSheet(filter: viewModel.productTypeForCreation == .crypto ? .crypto : .stocks) { symbol in
                viewModel.applySelectedMarketSymbol(symbol)
                Task {
                    await viewModel.refreshSelectedMarketQuote(forceRefresh: true)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert(quickSetupText(ru: "Не удалось применить настройку", en: "Couldn't apply setup"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )) {
            Button(quickSetupText(ru: "Ок", en: "OK"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: viewModel.currentStep) { _, newStep in
            focusedField = nil
            if newStep == .summary {
                triggerSummaryCelebration()
            }
        }
        .onChange(of: viewModel.selectedGroupDraftID) { oldValue, newValue in
            guard viewModel.currentStep == .products, oldValue != newValue, newValue != nil else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                isGroupSetupCollapsed = true
            }
            routeToProductCreation()
        }
        .onChange(of: productAmountDisplayText) { _, newValue in
            handleAmountDisplayChange(
                newValue,
                raw: viewModel.productAmountInput,
                setRaw: { viewModel.productAmountInput = $0 },
                setDisplay: { productAmountDisplayText = $0 }
            )
        }
        .onChange(of: productQuantityDisplayText) { _, newValue in
            handleAmountDisplayChange(
                newValue,
                raw: viewModel.productQuantityInput,
                setRaw: { viewModel.productQuantityInput = $0 },
                setDisplay: { productQuantityDisplayText = $0 }
            )
        }
        .onChange(of: productPurchasePriceDisplayText) { _, newValue in
            handleAmountDisplayChange(
                newValue,
                raw: viewModel.productPurchasePriceInput,
                setRaw: { viewModel.productPurchasePriceInput = $0 },
                setDisplay: { productPurchasePriceDisplayText = $0 }
            )
        }
        .onChange(of: productCurrentPriceDisplayText) { _, newValue in
            handleAmountDisplayChange(
                newValue,
                raw: viewModel.productCurrentPriceInput,
                setRaw: { viewModel.productCurrentPriceInput = $0 },
                setDisplay: { productCurrentPriceDisplayText = $0 }
            )
        }
        .onChange(of: viewModel.productAmountInput) { _, newValue in
            let formatted = AmountInputFormatter.display(AmountInputFormatter.sanitize(newValue))
            if formatted != productAmountDisplayText {
                productAmountDisplayText = formatted
            }
        }
        .onChange(of: viewModel.productQuantityInput) { _, newValue in
            let formatted = AmountInputFormatter.display(AmountInputFormatter.sanitize(newValue))
            if formatted != productQuantityDisplayText {
                productQuantityDisplayText = formatted
            }
        }
        .onChange(of: viewModel.productPurchasePriceInput) { _, newValue in
            let formatted = AmountInputFormatter.display(AmountInputFormatter.sanitize(newValue))
            if formatted != productPurchasePriceDisplayText {
                productPurchasePriceDisplayText = formatted
            }
        }
        .onChange(of: viewModel.productCurrentPriceInput) { _, newValue in
            let formatted = AmountInputFormatter.display(AmountInputFormatter.sanitize(newValue))
            if formatted != productCurrentPriceDisplayText {
                productCurrentPriceDisplayText = formatted
            }
        }
        .onAppear {
            syncAllAmountDisplayTexts()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                if mode == .settings {
                    dismiss()
                } else {
                    onSkipped?()
                }
            } label: {
                Image(systemName: mode == .settings ? "xmark" : "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.08)))
                    .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quickSetup.headerBackButton")

            Spacer()

            if mode == .onboarding {
                Button(quickSetupText(ru: "Пропустить", en: "Skip")) {
                    onSkipped?()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.brandPrimary)
                .accessibilityIdentifier("quickSetup.skipButton")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stepProgressText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppColors.quickSetupAccent, AppColors.quickSetupAccentMint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * viewModel.progress))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.progress)
                }
            }
            .frame(height: 6)
        }
    }

    private var stepHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.currentStep.title(for: quickSetupLocale))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text(viewModel.currentStep.subtitle(for: quickSetupLocale))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .localeAndCurrencies:
            localeAndCurrenciesStep
        case .expenseCategories:
            expenseCategoriesStep
        case .products:
            productsStep
        case .summary:
            summaryStep
        }
    }

    private var localeAndCurrenciesStep: some View {
        stepSectionCard {
            QuickSetupRowCard(
                title: quickSetupText(ru: "Язык", en: "Language"),
                value: viewModel.selectedLanguage.displayName,
                icon: "globe",
                gradient: AppColors.coursesGradient,
                isCompleted: isLanguageConfigured
            ) {
                showLanguageSheet = true
            }

            QuickSetupRowCard(
                title: quickSetupText(ru: "Основная валюта", en: "Primary currency"),
                value: viewModel.primaryCurrencyCode,
                icon: "dollarsign.circle.fill",
                gradient: AppColors.financesGradient,
                isCompleted: isPrimaryCurrencyConfigured
            ) {
                showPrimaryCurrencySheet = true
            }

            QuickSetupRowCard(
                title: quickSetupText(ru: "Избранные валюты", en: "Favorite currencies"),
                value: viewModel.favoriteCurrencyCodes.isEmpty ? quickSetupText(ru: "Не выбраны", en: "Not selected") : viewModel.favoriteCurrencyCodes.joined(separator: ", "),
                icon: "star.circle.fill",
                gradient: AppColors.cashbackGradient,
                isCompleted: isFavoriteCurrenciesConfigured
            ) {
                showFavoritesSheet = true
            }

            HStack(spacing: 8) {
                quickSetupTag(quickSetupText(ru: "Основная: \(viewModel.primaryCurrencyCode)", en: "Primary: \(viewModel.primaryCurrencyCode)"))
                quickSetupTag(quickSetupText(ru: "Избранных: \(viewModel.favoriteCurrencyCodes.count)/\(QuickSetupViewModel.maxFavoriteCurrencies)", en: "Favorites: \(viewModel.favoriteCurrencyCodes.count)/\(QuickSetupViewModel.maxFavoriteCurrencies)"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var expenseCategoriesStep: some View {
        stepSectionCard {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    quickActionChip(
                        title: quickSetupText(ru: "Рекомендуемые", en: "Recommended"),
                        systemImage: "sparkles",
                        prominence: .accent
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            viewModel.applyRecommendedExpenseCategories()
                        }
                    }

                    quickActionChip(
                        title: quickSetupText(ru: "Очистить", en: "Clear"),
                        systemImage: "xmark",
                        prominence: .secondary
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            viewModel.clearExpenseCategories()
                        }
                    }
                }
            }

            LazyVGrid(columns: expenseCategoryGridColumns, spacing: 8) {
                ForEach(expenseCategoryPresets) { category in
                    let isSelected = viewModel.selectedExpenseCategoryIDs.contains(category.id)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            viewModel.toggleExpenseCategory(raw: category.id)
                        }
                        fireSelectionHaptic()
                    } label: {
                        VStack(spacing: 6) {
                            Text(category.icon)
                                .font(.system(size: 24))
                            Text(category.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 74)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(isSelected ? AppColors.quickSetupAccent.opacity(0.9) : .white.opacity(0.08), lineWidth: isSelected ? 0.9 : 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Text(selectedExpenseCategoriesText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Image(systemName: "info.circle")
                    .foregroundStyle(AppColors.textSecondary)
                Text(quickSetupText(ru: "Категории можно скорректировать позже", en: "Categories can be adjusted later"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var productsStep: some View {
        stepSectionCard {
            productGroupsSection
            productTypeIconSelector

            VStack(spacing: 8) {
                if viewModel.isMarketProductDraft {
                    marketDraftFields
                } else {
                    standardDraftFields
                }

                Button {
                    focusedField = nil
                    let added = viewModel.addDraftProduct()
                    if !added {
                        fireWarningHaptic()
                        errorMessage = viewModel.lastAddDraftError ?? String(localized: "quick_setup.error.check_data")
                    } else {
                        fireSuccessHaptic()
                    }
                } label: {
                    quickSetupPrimaryButtonLabel(
                        title: quickSetupText(ru: "Добавить", en: "Add"),
                        systemImage: "plus.circle.fill"
                    )
                }
                .buttonStyle(.plain)
            }

            if !viewModel.products.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(addedProductsText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    ForEach(viewModel.products) { product in
                        HStack(spacing: 10) {
                            Image(systemName: product.visualIcon ?? product.type.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.symbol ?? product.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                if let groupName = productGroupName(product) {
                                    Text(groupName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(AppColors.quickSetupAccent)
                                }
                                Text(productSummaryText(product))
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.removeProduct(id: product.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(.white.opacity(0.06), lineWidth: 1)
                                )
                        )
                    }
                }
            }

            Text(quickSetupText(ru: "Можно добавить после запуска, но стартовая структура уже будет чистой", en: "You can add more after launch, but the initial structure will already stay clean"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary.opacity(0.9))
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: viewModel.productTypeForCreation)
    }

    private var productGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isGroupSetupCollapsed, !viewModel.groups.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(quickSetupText(ru: "Группы готовы", en: "Groups are ready"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text(collapsedGroupsSummaryText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(quickSetupText(ru: "Изменить", en: "Edit")) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            isGroupSetupCollapsed = false
                        }
                        fireSelectionHaptic()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.quickSetupAccent)
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(quickSetupText(ru: "Сначала группы", en: "Groups first"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(
                        quickSetupText(
                            ru: "Так счета сразу попадают в правильные блоки, а итоги и динамика не превращаются в свалку.",
                            en: "This keeps accounts in the right buckets from day one so totals and trends do not turn into a mess."
                        )
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: productTypeGridColumns, spacing: 8) {
                    ForEach(QuickSetupGroupPreset.all) { preset in
                        let isSelected = viewModel.groups.contains { $0.template == preset.template }
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                viewModel.addGroupPreset(preset)
                            }
                            fireSelectionHaptic()
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Image(systemName: preset.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(.white.opacity(0.06))
                                    )
                                Text(preset.title(for: quickSetupLocale))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.82)
                                Text(
                                    quickSetupText(
                                        ru: "Готовая группа",
                                        en: "Ready group"
                                    )
                                )
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            }
                            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(isSelected ? AppColors.quickSetupAccent.opacity(0.9) : .white.opacity(0.08), lineWidth: isSelected ? 0.9 : 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !viewModel.groups.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(quickSetupText(ru: "Куда сейчас пойдет новый продукт", en: "Where the next product will go"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                        viewModel.selectGroupDraft(id: nil)
                                    }
                                    fireSelectionHaptic()
                                } label: {
                                    groupDraftChip(
                                        title: quickSetupText(ru: "Без группы", en: "Ungrouped"),
                                        icon: "tray.fill",
                                        isSelected: viewModel.selectedGroupDraftID == nil
                                    )
                                }
                                .buttonStyle(.plain)

                                ForEach(viewModel.groups) { group in
                                    HStack(spacing: 6) {
                                        Button {
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                                viewModel.selectGroupDraft(id: group.id)
                                            }
                                            fireSelectionHaptic()
                                        } label: {
                                            groupDraftChip(
                                                title: group.name,
                                                icon: group.icon,
                                                isSelected: viewModel.selectedGroupDraftID == group.id
                                            )
                                        }
                                        .buttonStyle(.plain)

                                        Button {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                                                viewModel.removeGroup(id: group.id)
                                            }
                                            fireWarningHaptic()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(AppColors.textSecondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if let selectedGroup = selectedGroupTitle {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 12, weight: .semibold))
                            Text(
                                quickSetupText(
                                    ru: "Следующий продукт добавится в группу «\(selectedGroup)»",
                                    en: "The next product will be added to \"\(selectedGroup)\""
                                )
                            )
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.quickSetupAccent)
                        .padding(.top, 2)
                    }
                } else {
                    Text(
                        quickSetupText(
                            ru: "Выбери готовую группу, чтобы не раскидывать счета вручную после запуска.",
                            en: "Pick a ready-made group now so you do not have to reorganize accounts after launch."
                        )
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    private var productTypeIconSelector: some View {
        LazyVGrid(columns: productTypeGridColumns, spacing: 8) {
            ForEach(QuickSetupProductType.allCases) { type in
                let selected = viewModel.productTypeForCreation == type
                Button {
                    focusedField = nil
                    let previousType = viewModel.productTypeForCreation
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        viewModel.selectProductType(type)
                    }
                    if QuickSetupProductFlowPolicy.shouldAutoOpenMarketSearch(previousType: previousType, newType: type) {
                        DispatchQueue.main.async {
                            showMarketSearchSheet = true
                        }
                    }
                    fireSelectionHaptic()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Image(systemName: type.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(selected ? AppColors.textPrimary : AppColors.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(.white.opacity(0.06))
                            )
                        Text(type.title(for: quickSetupLocale))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        Text(type.subtitle(for: quickSetupLocale))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(selected ? AppColors.quickSetupAccent.opacity(0.9) : .white.opacity(0.08), lineWidth: selected ? 0.9 : 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 4)
    }

    private var summaryStep: some View {
        let selection = viewModel.makeSelection()
        return stepSectionCard {
            if showCelebrate {
                QuickSetupCelebrateBadge(locale: quickSetupLocale)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            VStack(spacing: 10) {
                ForEach(QuickSetupBackupPreference.allCases) { preference in
                    let isSelected = viewModel.backupPreference == preference
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            viewModel.backupPreference = preference
                        }
                        fireSelectionHaptic()
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20, weight: .semibold))
                                Text(preference.title(for: quickSetupLocale))
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(AppColors.textPrimary)

                            Text(preference.subtitle(for: quickSetupLocale))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)

                            Text(preference.details(for: quickSetupLocale))
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(AppColors.textSecondary.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(isSelected ? AppColors.quickSetupAccent.opacity(0.9) : .white.opacity(0.08), lineWidth: isSelected ? 0.9 : 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(quickSetupText(ru: "Итоговая конфигурация", en: "Final configuration"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                summaryRow(title: quickSetupText(ru: "Язык", en: "Language"), value: selection.language.displayName(for: quickSetupLocale))
                summaryRow(title: quickSetupText(ru: "Основная валюта", en: "Primary currency"), value: selection.primaryCurrencyCode)
                summaryRow(
                    title: quickSetupText(ru: "Избранные валюты", en: "Favorite currencies"),
                    value: selection.favoriteCurrencyCodes.isEmpty ? quickSetupText(ru: "Не выбраны", en: "Not selected") : selection.favoriteCurrencyCodes.joined(separator: ", ")
                )
                summaryRow(title: quickSetupText(ru: "Категории расходов", en: "Expense categories"), value: "\(selection.selectedExpenseCategoryIDs.count)")
                summaryRow(title: quickSetupText(ru: "Группы счетов", en: "Account groups"), value: "\(selection.groups.count)")
                summaryRow(title: quickSetupText(ru: "Продукты", en: "Products"), value: "\(selection.products.count)")
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: showCelebrate)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(AppColors.textPrimary)
                .fontWeight(.semibold)
        }
        .font(.system(size: 14, weight: .medium))
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            if viewModel.currentStep != .localeAndCurrencies {
                Button {
                    focusedField = nil
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        viewModel.goBackStep()
                    }
                    fireSelectionHaptic()
                } label: {
                    Text(quickSetupText(ru: "Назад", en: "Back"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(.white.opacity(0.06), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quickSetup.backButton")
            }

            Button {
                focusedField = nil
                if viewModel.currentStep == .summary {
                    saveSelection()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        viewModel.goNextStep()
                    }
                    fireSelectionHaptic()
                }
            } label: {
                quickSetupPrimaryButtonLabel(
                    title: viewModel.currentStep == .summary ? quickSetupText(ru: "Завершить", en: "Finish") : viewModel.continueTitle,
                    systemImage: viewModel.currentStep == .summary ? "checkmark.circle.fill" : "arrow.right.circle.fill",
                    isLoading: isSaving
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("quickSetup.continueButton")
            .disabled(!viewModel.canContinue || isSaving)
            .opacity((!viewModel.canContinue || isSaving) ? 0.55 : 1)
        }
    }

    private var bottomBarBackground: some View {
        LinearGradient(
            colors: [Color.clear, Color.black.opacity(0.9), Color.black],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private func moneyText(_ amount: Double, currencyCode: String) -> String {
        let raw = AmountInputFormatter.plainString(from: amount)
        let formatted = AmountInputFormatter.display(raw)
        return "\(formatted) \(currencyCode)"
    }

    private var stepProgressText: String {
        quickSetupText(
            ru: "Шаг \(viewModel.currentStep.rawValue + 1) из \(QuickSetupStep.allCases.count)",
            en: "Step \(viewModel.currentStep.rawValue + 1) of \(QuickSetupStep.allCases.count)"
        )
    }

    private var selectedExpenseCategoriesText: String {
        String(
            format: String(localized: "quick_setup.selected_categories_count_format"),
            viewModel.selectedExpenseCategoryIDs.count
        )
    }

    private var addedProductsText: String {
        String(
            format: String(localized: "quick_setup.added_products_count_format"),
            viewModel.products.count
        )
    }

    private func productSummaryText(_ product: QuickSetupProductDraft) -> String {
        let productTypeTitle = product.type.title(for: quickSetupLocale)
        if let marketSnapshot = product.marketSnapshot {
            let quantityText = AmountInputFormatter.display(AmountInputFormatter.plainString(from: marketSnapshot.quantity))
            return "\(productTypeTitle) • \(quantityText) × \(marketSnapshot.purchaseUnitPrice.formatted(.number.precision(.fractionLength(0...4)))) • \(moneyText(product.amount, currencyCode: product.currencyCode))"
        }
        let amountText = moneyText(product.amount, currencyCode: product.currencyCode)
        return String(format: String(localized: "quick_setup.product_summary_format"), productTypeTitle, amountText)
    }

    private func productGroupName(_ product: QuickSetupProductDraft) -> String? {
        guard let groupDraftID = product.groupDraftID else { return nil }
        return viewModel.groups.first(where: { $0.id == groupDraftID })?.name
    }

    private var expenseCategoryPresets: [QuickSetupExpenseCategoryPreset] {
        QuickSetupExpenseCategoryPreset.all(for: viewModel.selectedLanguage.locale ?? Locale.current)
    }

    private var selectedGroupTitle: String? {
        guard let selectedGroupDraftID = viewModel.selectedGroupDraftID else { return nil }
        return viewModel.groups.first(where: { $0.id == selectedGroupDraftID })?.name
    }

    private var collapsedGroupsSummaryText: String {
        let groupNames = viewModel.groups.map(\.name)
        if groupNames.isEmpty {
            return quickSetupText(ru: "Группы не выбраны", en: "No groups selected")
        }

        if groupNames.count <= 2 {
            return groupNames.joined(separator: ", ")
        }

        let leading = groupNames.prefix(2).joined(separator: ", ")
        return quickSetupText(
            ru: "\(leading) и еще \(groupNames.count - 2)",
            en: "\(leading) and \(groupNames.count - 2) more"
        )
    }

    private func groupDraftChip(title: String, icon: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(AppColors.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(.white.opacity(0.04))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? AppColors.quickSetupAccent.opacity(0.9) : .white.opacity(0.08), lineWidth: isSelected ? 0.9 : 1)
                )
        )
    }

    private func saveSelection() {
        guard !isSaving else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            let applier = QuickSetupApplier(modelContext: modelContext, appState: appState)
            try applier.apply(viewModel.makeSelection())
            fireSuccessHaptic()
            onCompleted?()
            if mode == .settings {
                dismiss()
            }
        } catch {
            fireWarningHaptic()
            errorMessage = error.localizedDescription
        }
    }

    private func routeToProductCreation() {
        DispatchQueue.main.async {
            if viewModel.isMarketProductDraft {
                showMarketSearchSheet = true
            } else {
                focusedField = .productName
            }
            fireSelectionHaptic()
        }
    }

    private func fireSelectionHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func fireSuccessHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    private func fireWarningHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    private func triggerSummaryCelebration() {
        showCelebrate = false
        withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) {
            showCelebrate = true
        }

        let impact = UIImpactFeedbackGenerator(style: .rigid)
        impact.prepare()
        impact.impactOccurred()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let notification = UINotificationFeedbackGenerator()
            notification.prepare()
            notification.notificationOccurred(.success)
        }
    }

    private var quickSetupBackground: some View {
        ZStack {
            GradientBackground()
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.05, blue: 0.1), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 320, height: 320)
                .blur(radius: 120)
                .offset(x: -110, y: -280)

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 120)
                .offset(x: 140, y: -180)
        }
        .ignoresSafeArea()
    }

    private var primaryButtonBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        buttonAccentGradient,
                        lineWidth: buttonIsAccentActive ? 0.9 : 1
                    )
            )
    }

    private func quickSetupPrimaryButtonLabel(
        title: String,
        systemImage: String,
        isLoading: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .tint(AppColors.textPrimary)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
            }

            Text(title)
                .font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(AppColors.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .background(primaryButtonBackground)
    }

    private var buttonIsAccentActive: Bool {
        viewModel.canContinue && !isSaving
    }

    private var buttonAccentGradient: LinearGradient {
        LinearGradient(
            colors: buttonIsAccentActive
                ? [AppColors.quickSetupAccent, AppColors.quickSetupAccentMint]
                : [Color.white.opacity(0.12), Color.white.opacity(0.08)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var isLanguageConfigured: Bool {
        !viewModel.selectedLanguage.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isPrimaryCurrencyConfigured: Bool {
        !viewModel.primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isFavoriteCurrenciesConfigured: Bool {
        !viewModel.favoriteCurrencyCodes.isEmpty
    }

    private var standardDraftFields: some View {
        VStack(spacing: 8) {
            TextField(quickSetupText(ru: "Название", en: "Name"), text: $viewModel.productNameInput)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .focused($focusedField, equals: .productName)
                .submitLabel(.next)
                .onSubmit { focusedField = .productAmount }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
                .id(FocusField.productName)
                .accessibilityIdentifier("quickSetup.productNameField")

            TextField(
                viewModel.productAmountFieldTitle,
                text: $productAmountDisplayText
            )
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .productAmount)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
            .id(FocusField.productAmount)
            .accessibilityIdentifier("quickSetup.productAmountField")
        }
    }

    private var marketDraftFields: some View {
        VStack(spacing: 10) {
            Button {
                focusedField = nil
                showMarketSearchSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColors.brandPrimary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.productMarketSearchTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        Text(viewModel.productSymbolInput.isEmpty ? quickSetupText(ru: "Не задан", en: "Not selected") : viewModel.productSymbolInput)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    Spacer()
                    if let exchange = viewModel.productMarketExchange, !exchange.isEmpty {
                        Text(exchange)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
            }
            .buttonStyle(.plain)

            TextField(
                viewModel.productAmountFieldTitle,
                text: $productQuantityDisplayText
            )
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .productQuantity)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
            .id(FocusField.productQuantity)
            .accessibilityIdentifier("quickSetup.productQuantityField")

            TextField(
                viewModel.productPurchasePriceTitle,
                text: $productPurchasePriceDisplayText
            )
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .productPurchasePrice)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
            .id(FocusField.productPurchasePrice)
            .accessibilityIdentifier("quickSetup.productPurchasePriceField")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(quickSetupText(ru: "Текущая цена", en: "Current price"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    if viewModel.isRefreshingProductQuote {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(AppColors.textPrimary)
                    } else {
                        Text(currentUnitPriceText)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }

                    Button {
                        Task {
                            await viewModel.refreshSelectedMarketQuote(forceRefresh: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.productSymbolInput.isEmpty || viewModel.isRefreshingProductQuote)
                }

                if viewModel.productLatestUnitPrice == nil {
                    TextField(
                        quickSetupText(ru: "Ввести текущую цену", en: "Enter current price"),
                        text: $productCurrentPriceDisplayText
                    )
                    .keyboardType(.decimalPad)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.04)))
                }

                if let total = viewModel.productPositionTotal {
                    HStack {
                        Text(quickSetupText(ru: "Позиция", en: "Position"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Text(moneyText(total, currencyCode: viewModel.productResolvedCurrencyCode))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }

                if let growth = viewModel.productPositionGrowthAbsolute {
                    HStack {
                        Text(quickSetupText(ru: "Рост/убыток", en: "Gain/loss"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                        Text(moneyText(growth, currencyCode: viewModel.productResolvedCurrencyCode))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(growth >= 0 ? AppColors.toggleOnGreen : AppColors.error)
                    }
                }

                if let error = viewModel.productMarketError, !error.isEmpty {
                    Text(error)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.error)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.04)))
        }
    }

    private var currentUnitPriceText: String {
        if let price = viewModel.productLatestUnitPrice {
            return moneyText(price, currencyCode: viewModel.productResolvedCurrencyCode)
        }
        let manual = AmountInputFormatter.sanitize(viewModel.productCurrentPriceInput)
        if let manualPrice = Double(manual), manualPrice > 0 {
            return moneyText(manualPrice, currencyCode: viewModel.productResolvedCurrencyCode)
        }
        return "—"
    }

    private func syncAllAmountDisplayTexts() {
        productAmountDisplayText = AmountInputFormatter.display(viewModel.productAmountInput)
        productQuantityDisplayText = AmountInputFormatter.display(viewModel.productQuantityInput)
        productPurchasePriceDisplayText = AmountInputFormatter.display(viewModel.productPurchasePriceInput)
        productCurrentPriceDisplayText = AmountInputFormatter.display(viewModel.productCurrentPriceInput)
    }

    private func handleAmountDisplayChange(
        _ newValue: String,
        raw: String,
        setRaw: (String) -> Void,
        setDisplay: (String) -> Void
    ) {
        let sanitized = AmountInputFormatter.sanitize(newValue)
        let formatted = AmountInputFormatter.display(sanitized)

        if newValue != formatted {
            setDisplay(formatted)
        }
        if raw != sanitized {
            setRaw(sanitized)
        }
    }

    private func stepSectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }

    private func quickSetupTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.white.opacity(0.06))
                    .overlay(
                        Capsule().stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }

    private enum QuickActionChipProminence {
        case accent
        case secondary
    }

    private func quickActionChip(
        title: String,
        systemImage: String,
        prominence: QuickActionChipProminence,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(.white.opacity(0.05))
                    .overlay(
                        Capsule()
                            .stroke(prominence == .accent ? AppColors.quickSetupAccent.opacity(0.9) : .white.opacity(0.08), lineWidth: prominence == .accent ? 0.9 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct QuickSetupCelebrateBadge: View {
    let locale: Locale
    @State private var glow = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .bold))
            Text(QuickSetupLocalization.text(locale: locale, ru: "Конфигурация почти готова", en: "Configuration is almost complete"))
                .font(.system(size: 18, weight: .bold))
                .lineLimit(2)
        }
        .foregroundStyle(AppColors.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppColors.quickSetupAccent.opacity(glow ? 0.94 : 0.82),
                                    AppColors.quickSetupAccentMint.opacity(glow ? 0.88 : 0.72)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: glow ? 1.0 : 0.9
                        )
                )
        )
        .scaleEffect(glow ? 1.02 : 0.99)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                glow = true
            }
        }
    }
}

private struct QuickSetupRowCard: View {
    let title: String
    let value: String
    let icon: String
    let gradient: [Color]
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.06))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(value)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: isCompleted
                                        ? [AppColors.quickSetupAccent, AppColors.quickSetupAccentMint.opacity(0.78)]
                                        : [
                                            (gradient.first ?? AppColors.brandPrimary).opacity(0.9),
                                            .white.opacity(0.08)
                                        ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isCompleted ? 0.9 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct QuickSetupFavoriteCurrenciesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    let locale: Locale

    let primaryCurrencyCode: String
    let selectedCodes: [String]
    let suggestedCodes: [String]
    let maxSelection: Int
    let onToggle: (String) -> Void

    var body: some View {
        CurrencyPickerView(
            allCodes: CurrencySelectionSupport.allCurrencyCodesForPicker,
            searchText: $searchText,
            selectedCodes: selectedCodes,
            suggestedCodes: suggestedCodes,
            favoriteCodes: Set(selectedCodes),
            currentSelection: nil,
            primaryPinnedCode: primaryCurrencyCode,
            primaryPinnedTitle: QuickSetupLocalization.text(locale: locale, ru: "Основная", en: "Primary"),
            onToggleFavorite: { code in
                onToggle(code)
            },
            onSelect: { code in
                onToggle(code)
            }
        )
        .navigationTitle(QuickSetupLocalization.text(locale: locale, ru: "Избранные валюты", en: "Favorite currencies"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(QuickSetupLocalization.text(locale: locale, ru: "Готово", en: "Done")) {
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(String(format: String(localized: "quick_setup.favorite_limit_format"), maxSelection))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
        }
    }
}

private struct QuickSetupPrimaryCurrencySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var primaryCurrencyCode: String
    let locale: Locale
    let suggestedCodes: [String]
    @State private var searchText = ""

    var body: some View {
        CurrencyPickerView(
            allCodes: CurrencySelectionSupport.allCurrencyCodesForPicker,
            searchText: $searchText,
            selectedCodes: [],
            suggestedCodes: suggestedCodes,
            favoriteCodes: [],
            currentSelection: primaryCurrencyCode,
            primaryPinnedCode: primaryCurrencyCode,
            primaryPinnedTitle: QuickSetupLocalization.text(locale: locale, ru: "Основная", en: "Primary"),
            onToggleFavorite: nil,
            onSelect: { code in
                primaryCurrencyCode = code
                dismiss()
            }
        )
        .navigationTitle(QuickSetupLocalization.text(locale: locale, ru: "Основная валюта", en: "Primary currency"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(QuickSetupLocalization.text(locale: locale, ru: "Готово", en: "Done")) {
                    dismiss()
                }
            }
        }
    }
}
