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
    @State private var didCompleteSetup = false
    @State private var productAmountDisplayText = ""
    @State private var productQuantityDisplayText = ""
    @State private var productPurchasePriceDisplayText = ""
    @State private var productCurrentPriceDisplayText = ""
    @State private var isGroupSetupCollapsed = false
    @State private var isProductTypeCollapsed = false
    @State private var keyboardFrame: CGRect = .zero

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
        viewModel.presentationLocale
    }

    private func quickSetupText(_ key: String, fallback: String? = nil) -> String {
        QuickSetupLocalization.tr(key, locale: quickSetupLocale, fallback: fallback)
    }

    private func quickSetupFormat(_ key: String, fallback: String? = nil, _ args: CVarArg...) -> String {
        QuickSetupLocalization.formatArguments(key, locale: quickSetupLocale, fallback: fallback, arguments: args)
    }

    var body: some View {
        GeometryReader { geometry in
            let keyboardOverlap = QuickSetupLayout.keyboardOverlap(
                screenHeight: UIScreen.main.bounds.height,
                keyboardFrame: keyboardFrame,
                safeAreaBottom: geometry.safeAreaInsets.bottom
            )

            ZStack {
                quickSetupBackground

                if didCompleteSetup {
                    completionContent
                } else {
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
                                .padding(.bottom, QuickSetupLayout.contentBottomPadding(keyboardOverlap: keyboardOverlap))
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
                Button(quickSetupText("quick_setup.common.done")) { focusedField = nil }
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
                // Откладываем мутацию на следующий runloop-тик (тот же приём, что в
                // routeToProductCreation): applySelectedMarketSymbol меняет высоту marketDraftFields
                // над полем количества (появляется exchange-бейдж, цена → ProgressView). Без задержки
                // reflow совпадает с dismiss .sheet и передачей responder обратно presenting-view —
                // первый тап промахивается мимо сдвинувшегося TextField, клавиатура не открывается.
                DispatchQueue.main.async {
                    viewModel.applySelectedMarketSymbol(symbol)
                    Task {
                        await viewModel.refreshSelectedMarketQuote(forceRefresh: true)
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert(quickSetupText("quick_setup.alert.apply_failed.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )) {
            Button(quickSetupText("quick_setup.common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: viewModel.currentStep) { _, newStep in
            focusedField = nil
        }
        .onChange(of: productAmountDisplayText) { _, newValue in
            handleAmountDisplayChange(
                newValue,
                raw: viewModel.productAmountInput,
                maxFractionDigits: AmountInputFormatter.defaultFractionDigits,
                setRaw: { viewModel.productAmountInput = $0 },
                setDisplay: { productAmountDisplayText = $0 }
            )
        }
        .onChange(of: productQuantityDisplayText) { _, newValue in
            handleAmountDisplayChange(
                newValue,
                raw: viewModel.productQuantityInput,
                maxFractionDigits: viewModel.productQuantityFractionDigits,
                setRaw: { viewModel.productQuantityInput = $0 },
                setDisplay: { productQuantityDisplayText = $0 }
            )
        }
        .onChange(of: productPurchasePriceDisplayText) { _, newValue in
            handleAmountDisplayChange(
                newValue,
                raw: viewModel.productPurchasePriceInput,
                maxFractionDigits: viewModel.productUnitPriceFractionDigits,
                setRaw: { viewModel.productPurchasePriceInput = $0 },
                setDisplay: { productPurchasePriceDisplayText = $0 }
            )
        }
        .onChange(of: productCurrentPriceDisplayText) { _, newValue in
            handleAmountDisplayChange(
                newValue,
                raw: viewModel.productCurrentPriceInput,
                maxFractionDigits: viewModel.productUnitPriceFractionDigits,
                setRaw: { viewModel.productCurrentPriceInput = $0 },
                setDisplay: { productCurrentPriceDisplayText = $0 }
            )
        }
        .onChange(of: viewModel.productAmountInput) { _, newValue in
            let formatted = AmountInputFormatter.display(
                AmountInputFormatter.sanitize(newValue, maxFractionDigits: AmountInputFormatter.defaultFractionDigits),
                maxFractionDigits: AmountInputFormatter.defaultFractionDigits
            )
            if formatted != productAmountDisplayText {
                productAmountDisplayText = formatted
            }
        }
        .onChange(of: viewModel.productQuantityInput) { _, newValue in
            let formatted = AmountInputFormatter.display(
                AmountInputFormatter.sanitize(newValue, maxFractionDigits: viewModel.productQuantityFractionDigits),
                maxFractionDigits: viewModel.productQuantityFractionDigits
            )
            if formatted != productQuantityDisplayText {
                productQuantityDisplayText = formatted
            }
        }
        .onChange(of: viewModel.productPurchasePriceInput) { _, newValue in
            let formatted = AmountInputFormatter.display(
                AmountInputFormatter.sanitize(newValue, maxFractionDigits: viewModel.productUnitPriceFractionDigits),
                maxFractionDigits: viewModel.productUnitPriceFractionDigits
            )
            if formatted != productPurchasePriceDisplayText {
                productPurchasePriceDisplayText = formatted
            }
        }
        .onChange(of: viewModel.productCurrentPriceInput) { _, newValue in
            let formatted = AmountInputFormatter.display(
                AmountInputFormatter.sanitize(newValue, maxFractionDigits: viewModel.productUnitPriceFractionDigits),
                maxFractionDigits: viewModel.productUnitPriceFractionDigits
            )
            if formatted != productCurrentPriceDisplayText {
                productCurrentPriceDisplayText = formatted
            }
        }
        .onAppear {
            syncAllAmountDisplayTexts()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard
                let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else {
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                keyboardFrame = frame
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                keyboardFrame = .zero
            }
        }
        .onDisappear {
            keyboardFrame = .zero
        }
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
                Button(quickSetupText("quick_setup.common.skip")) {
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
            Text(stepHeroTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text(stepHeroSubtitle)
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
                title: quickSetupText("quick_setup.common.language"),
                value: viewModel.selectedLanguage.displayName,
                icon: "globe",
                gradient: AppColors.coursesGradient,
                isCompleted: isLanguageConfigured
            ) {
                showLanguageSheet = true
            }

            QuickSetupRowCard(
                title: quickSetupText("quick_setup.common.primary_currency"),
                value: viewModel.primaryCurrencyCode,
                icon: "dollarsign.circle.fill",
                gradient: AppColors.financesGradient,
                isCompleted: isPrimaryCurrencyConfigured
            ) {
                showPrimaryCurrencySheet = true
            }

            QuickSetupRowCard(
                title: quickSetupText("quick_setup.common.favorite_currencies"),
                value: viewModel.favoriteCurrencyCodes.isEmpty ? quickSetupText("quick_setup.common.not_selected") : viewModel.favoriteCurrencyCodes.joined(separator: ", "),
                icon: "star.circle.fill",
                gradient: AppColors.cashbackGradient,
                isCompleted: isFavoriteCurrenciesConfigured
            ) {
                showFavoritesSheet = true
            }

            HStack(spacing: 8) {
                quickSetupTag(
                    QuickSetupLocalization.primaryCurrencyBadge(
                        viewModel.primaryCurrencyCode,
                        locale: quickSetupLocale
                    )
                )
                quickSetupTag(
                    QuickSetupLocalization.favoritesCountBadge(
                        selectedCount: viewModel.favoriteCurrencyCodes.count,
                        maxCount: QuickSetupViewModel.maxFavoriteCurrencies,
                        locale: quickSetupLocale
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var expenseCategoriesStep: some View {
        stepSectionCard {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    quickActionChip(
                        title: quickSetupText("quick_setup.common.all"),
                        systemImage: "square.grid.2x2",
                        prominence: .secondary
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            viewModel.selectAllExpenseCategories()
                        }
                    }

                    quickActionChip(
                        title: quickSetupText("quick_setup.common.recommended"),
                        systemImage: "sparkles",
                        prominence: .accent
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            viewModel.applyRecommendedExpenseCategories()
                        }
                    }

                    quickActionChip(
                        title: quickSetupText("quick_setup.common.clear"),
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
                Text(quickSetupText("quick_setup.hint.categories_adjust_later"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var productsStep: some View {
        stepSectionCard {
            productTypeSection
            if isProductTypeCollapsed {
                productGroupsSection
            }
            if isProductTypeCollapsed && isGroupSetupCollapsed {
                productCreationSection
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: viewModel.productTypeForCreation)
    }

    private var productCreationSection: some View {
        Group {
            if viewModel.shouldPromptForPrimaryProductEntry {
                VStack(spacing: 8) {
                    if viewModel.isMarketProductDraft {
                        marketDraftFields
                    } else {
                        standardDraftFields
                    }
                }
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

            Text(quickSetupText("quick_setup.hint.add_later"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary.opacity(0.9))
        }
    }

    private var productTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isProductTypeCollapsed {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(quickSetupText("quick_setup.common.product_type"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text(viewModel.productTypeForCreation.title(for: quickSetupLocale))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(quickSetupText("quick_setup.common.edit")) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            isProductTypeCollapsed = false
                            viewModel.clearProducts()
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
                    Text(quickSetupText("quick_setup.common.product_type"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }

                productTypeIconSelector
            }
        }
    }

    private var productGroupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isGroupSetupCollapsed, !viewModel.groups.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(quickSetupText("quick_setup.common.grouping"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text(collapsedGroupsSummaryText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(quickSetupText("quick_setup.common.edit")) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            isGroupSetupCollapsed = false
                            viewModel.clearProducts()
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
                    Text(quickSetupText("quick_setup.common.grouping"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(
                        quickSetupText("quick_setup.grouping.subtitle")
                    )
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: productTypeGridColumns, spacing: 8) {
                    ForEach(QuickSetupGroupPreset.all) { preset in
                        let isSelected = viewModel.groups.first?.template == preset.template
                        let isRecommended = preset.template == viewModel.productTypeForCreation.recommendedGroupTemplate
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                                viewModel.chooseGroupPreset(preset)
                                isGroupSetupCollapsed = true
                            }
                            routeToProductCreation()
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

                                if isRecommended {
                                    QuickSetupRecommendedBadge()
                                        .accessibilityLabel(quickSetupText("quick_setup.grouping.recommended_accessibility"))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        isSelected
                                            ? AppColors.quickSetupAccentDeep.opacity(0.82)
                                            : .white.opacity(0.04)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(
                                                isSelected
                                                    ? AppColors.quickSetupAccent.opacity(0.9)
                                                    : .white.opacity(0.08),
                                                lineWidth: isSelected ? 0.9 : 1
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var productTypeIconSelector: some View {
        LazyVGrid(columns: productTypeGridColumns, spacing: 8) {
            ForEach(viewModel.availableProductTypes) { type in
                let selected = viewModel.hasExplicitlySelectedProductType && viewModel.productTypeForCreation == type
                Button {
                    focusedField = nil
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        viewModel.selectProductType(type)
                        isProductTypeCollapsed = true
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
        return stepSectionCard {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var completionContent: some View {
        let selection = viewModel.makeSelection()

        return VStack(spacing: 0) {
            Spacer(minLength: 32)

            VStack(spacing: 22) {
                VStack(spacing: 18) {
                    QuickSetupCompletionHero()

                    VStack(spacing: 8) {
                        Text(quickSetupText("quick_setup.summary.complete_title"))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                }

                stepSectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        summaryRow(title: quickSetupText("quick_setup.common.data_storage"), value: selection.backupPreference.title(for: quickSetupLocale))
                        summaryRow(title: quickSetupText("quick_setup.common.language"), value: selection.language.displayName(for: quickSetupLocale))
                        summaryRow(title: quickSetupText("quick_setup.common.primary_currency"), value: selection.primaryCurrencyCode)
                        summaryRow(title: quickSetupText("quick_setup.common.expense_categories"), value: "\(selection.selectedExpenseCategoryIDs.count)")
                        summaryRow(title: quickSetupText("quick_setup.common.products"), value: "\(selection.products.count)")
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)

            Spacer()
        }
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
            if didCompleteSetup {
                Button {
                    finalizeQuickSetup()
                } label: {
                    quickSetupPrimaryButtonLabel(
                        title: mode == .settings
                            ? quickSetupText("quick_setup.common.done")
                            : quickSetupText("quick_setup.common.continue"),
                        systemImage: "arrow.right.circle.fill",
                        isLoading: false,
                        isAccentActive: true
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quickSetup.finishCompletionButton")
            } else {
                if viewModel.currentStep != .localeAndCurrencies {
                    Button {
                        focusedField = nil
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            viewModel.goBackStep()
                        }
                        fireSelectionHaptic()
                    } label: {
                        Text(quickSetupText("quick_setup.common.back"))
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
                    } else if viewModel.currentStep == .products {
                        handleProductsPrimaryAction()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            viewModel.goNextStep()
                        }
                        fireSelectionHaptic()
                    }
                } label: {
                    quickSetupPrimaryButtonLabel(
                        title: primaryActionTitle,
                        systemImage: primaryActionSystemImage,
                        isLoading: isSaving,
                        isAccentActive: isPrimaryActionEnabled && !isSaving
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quickSetup.continueButton")
                .disabled(!isPrimaryActionEnabled || isSaving)
                .opacity((!isPrimaryActionEnabled || isSaving) ? 0.55 : 1)
            }
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
        QuickSetupLocalization.stepProgress(
            current: viewModel.currentStep.rawValue + 1,
            total: QuickSetupStep.allCases.count,
            locale: quickSetupLocale
        )
    }

    private var hasPendingProductDraftInput: Bool {
        !viewModel.productNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.productSymbolInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.productAmountInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.productQuantityInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.productPurchasePriceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.productCurrentPriceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var stepHeroTitle: String {
        if viewModel.currentStep == .products && !isProductTypeCollapsed {
            return quickSetupText("quick_setup.common.product_type")
        }
        if viewModel.currentStep == .products && !isGroupSetupCollapsed {
            return quickSetupText("quick_setup.common.grouping")
        }
        return viewModel.currentStep.title(for: quickSetupLocale)
    }

    private var stepHeroSubtitle: String {
        if viewModel.currentStep == .products && !isProductTypeCollapsed {
            return quickSetupText("quick_setup.product_type.subtitle")
        }
        if viewModel.currentStep == .products && !isGroupSetupCollapsed {
            return quickSetupText("quick_setup.grouping.select_subtitle")
        }
        return viewModel.currentStep.subtitle(for: quickSetupLocale)
    }

    private var selectedExpenseCategoriesText: String {
        QuickSetupLocalization.selectedCategoriesCount(
            viewModel.selectedExpenseCategoryIDs.count,
            locale: quickSetupLocale
        )
    }

    private var addedProductsText: String {
        QuickSetupLocalization.addedProductsCount(
            viewModel.products.count,
            locale: quickSetupLocale
        )
    }

    private func productSummaryText(_ product: QuickSetupProductDraft) -> String {
        let productTypeTitle = product.type.title(for: quickSetupLocale)
        if let marketSnapshot = product.marketSnapshot {
            let quantityText = AmountInputFormatter.display(AmountInputFormatter.plainString(from: marketSnapshot.quantity))
            return "\(productTypeTitle) • \(quantityText) × \(marketSnapshot.purchaseUnitPrice.formatted(.number.precision(.fractionLength(0...4)))) • \(moneyText(product.amount, currencyCode: product.currencyCode))"
        }
        let amountText = moneyText(product.amount, currencyCode: product.currencyCode)
        return QuickSetupLocalization.format(
            "quick_setup.product_summary_format",
            locale: quickSetupLocale,
            productTypeTitle,
            amountText
        )
    }

    private func productGroupName(_ product: QuickSetupProductDraft) -> String? {
        guard let groupDraftID = product.groupDraftID else { return nil }
        return viewModel.groups.first(where: { $0.id == groupDraftID })?.name
    }

    private var expenseCategoryPresets: [QuickSetupExpenseCategoryPreset] {
        QuickSetupExpenseCategoryPreset.all(for: quickSetupLocale)
    }

    private var collapsedGroupsSummaryText: String {
        viewModel.groups.first?.name ?? quickSetupText("quick_setup.grouping.none_selected")
    }

    private func saveSelection() {
        guard !isSaving else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            let applier = QuickSetupApplier(modelContext: modelContext, appState: appState)
            try applier.apply(viewModel.makeSelection())
            fireSuccessHaptic()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                didCompleteSetup = true
            }
        } catch {
            fireWarningHaptic()
            errorMessage = error.localizedDescription
        }
    }

    private func finalizeQuickSetup() {
        onCompleted?()
        if mode == .settings {
            dismiss()
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

    private func primaryButtonBackground(isAccentActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        buttonAccentGradient(isAccentActive: isAccentActive),
                        lineWidth: isAccentActive ? 0.9 : 1
                    )
            )
    }

    private func quickSetupPrimaryButtonLabel(
        title: String,
        systemImage: String,
        isLoading: Bool = false,
        isAccentActive: Bool = true
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
        .background(primaryButtonBackground(isAccentActive: isAccentActive))
    }

    private var isContinueButtonEnabled: Bool {
        if viewModel.currentStep == .products && (!isProductTypeCollapsed || !isGroupSetupCollapsed) {
            return false
        }
        return viewModel.canContinue
    }

    private var isPrimaryActionEnabled: Bool {
        if viewModel.currentStep == .products && viewModel.products.isEmpty && !hasPendingProductDraftInput {
            return true
        }
        return isContinueButtonEnabled
    }

    private var primaryActionTitle: String {
        switch viewModel.currentStep {
        case .summary:
            return quickSetupText("quick_setup.common.finish")
        case .products:
            return viewModel.products.isEmpty && !hasPendingProductDraftInput
                ? quickSetupText("quick_setup.common.skip")
                : viewModel.products.isEmpty
                ? quickSetupText("quick_setup.common.save")
                : quickSetupText("quick_setup.common.continue")
        default:
            return viewModel.continueTitle
        }
    }

    private var primaryActionSystemImage: String {
        switch viewModel.currentStep {
        case .summary:
            return "checkmark.circle.fill"
        case .products:
            return viewModel.products.isEmpty && !hasPendingProductDraftInput
                ? "arrow.right.circle.fill"
                : viewModel.products.isEmpty ? "checkmark.circle.fill" : "arrow.right.circle.fill"
        default:
            return "arrow.right.circle.fill"
        }
    }

    private func handleProductsPrimaryAction() {
        if viewModel.products.isEmpty && !hasPendingProductDraftInput {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                viewModel.goNextStep()
            }
            fireSelectionHaptic()
            return
        }

        if viewModel.products.isEmpty {
            let saved = viewModel.savePrimaryDraftProduct()
            if !saved {
                fireWarningHaptic()
                errorMessage = viewModel.lastAddDraftError ?? quickSetupText("quick_setup.error.check_data")
            } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    viewModel.goNextStep()
                }
                fireSuccessHaptic()
            }
            return
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            viewModel.goNextStep()
        }
        fireSelectionHaptic()
    }

    private func buttonAccentGradient(isAccentActive: Bool) -> LinearGradient {
        LinearGradient(
            colors: isAccentActive
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
            TextField(
                "",
                text: $viewModel.productNameInput,
                prompt: Text(viewModel.productNamePlaceholder)
                    .foregroundStyle(AppColors.textSecondary.opacity(0.55))
            )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .focused($focusedField, equals: .productName)
                .submitLabel(.next)
                .onSubmit { focusedField = .productAmount }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
                .id(FocusField.productName)
                .accessibilityIdentifier("quickSetup.productNameField")
                .accessibilityLabel(quickSetupText("quick_setup.common.name"))

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
                        Text(viewModel.productSymbolInput.isEmpty ? quickSetupText("quick_setup.common.not_selected") : viewModel.productSymbolInput)
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
                    Text(quickSetupText("quick_setup.common.current_price"))
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
                        quickSetupText("quick_setup.current_price.enter"),
                        text: $productCurrentPriceDisplayText
                    )
                    .keyboardType(.decimalPad)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.04)))
                }

                if let total = viewModel.productPositionTotal {
                    HStack {
                        Text(quickSetupText("quick_setup.common.position"))
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
                        Text(quickSetupText("quick_setup.common.gain_loss"))
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
        let manual = AmountInputFormatter.sanitize(
            viewModel.productCurrentPriceInput,
            maxFractionDigits: viewModel.productUnitPriceFractionDigits
        )
        if let manualPrice = Double(manual), manualPrice > 0 {
            return moneyText(manualPrice, currencyCode: viewModel.productResolvedCurrencyCode)
        }
        return "—"
    }

    private func syncAllAmountDisplayTexts() {
        productAmountDisplayText = AmountInputFormatter.display(
            viewModel.productAmountInput,
            maxFractionDigits: AmountInputFormatter.defaultFractionDigits
        )
        productQuantityDisplayText = AmountInputFormatter.display(
            viewModel.productQuantityInput,
            maxFractionDigits: viewModel.productQuantityFractionDigits
        )
        productPurchasePriceDisplayText = AmountInputFormatter.display(
            viewModel.productPurchasePriceInput,
            maxFractionDigits: viewModel.productUnitPriceFractionDigits
        )
        productCurrentPriceDisplayText = AmountInputFormatter.display(
            viewModel.productCurrentPriceInput,
            maxFractionDigits: viewModel.productUnitPriceFractionDigits
        )
    }

    private func handleAmountDisplayChange(
        _ newValue: String,
        raw: String,
        maxFractionDigits: Int,
        setRaw: (String) -> Void,
        setDisplay: (String) -> Void
    ) {
        let sanitized = AmountInputFormatter.sanitize(newValue, maxFractionDigits: maxFractionDigits)
        let formatted = AmountInputFormatter.display(sanitized, maxFractionDigits: maxFractionDigits)

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

private struct QuickSetupCompletionHero: View {
    @State private var ringRotation = Angle.degrees(-135)
    @State private var ringEnd = 0.08
    @State private var glowScale = 0.74
    @State private var glowOpacity = 0.0
    @State private var coreScale = 0.86
    @State private var pulseScale = 0.86
    @State private var pulseOpacity = 0.0
    @State private var checkTrim = 0.0
    @State private var checkOpacity = 0.0
    @State private var checkScale = 0.84

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppColors.quickSetupAccent.opacity(0.18),
                            AppColors.quickSetupAccent.opacity(0.04),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 64
                    )
                )
                .frame(width: 124, height: 124)
                .scaleEffect(glowScale)
                .opacity(glowOpacity)
                .blur(radius: 8)

            Circle()
                .stroke(AppColors.quickSetupAccent.opacity(0.20), lineWidth: 4)
                .frame(width: 108, height: 108)
                .scaleEffect(pulseScale)
                .opacity(pulseOpacity)
                .blur(radius: 1.5)

            Circle()
                .stroke(.white.opacity(0.06), lineWidth: 1)
                .frame(width: 96, height: 96)

            Circle()
                .trim(from: 0.08, to: ringEnd)
                .stroke(
                    AngularGradient(
                        colors: [
                            AppColors.quickSetupAccent.opacity(0.15),
                            AppColors.quickSetupAccent,
                            AppColors.quickSetupAccentMint,
                            AppColors.quickSetupAccent.opacity(0.15)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                )
                .frame(width: 96, height: 96)
                .rotationEffect(ringRotation)

            Circle()
                .fill(AppColors.quickSetupAccentDeep.opacity(0.58))
                .frame(width: 72, height: 72)
                .scaleEffect(coreScale)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.07), lineWidth: 1)
                )
                .shadow(color: AppColors.quickSetupAccent.opacity(0.12), radius: 20, x: 0, y: 8)

            CheckmarkShape()
                .trim(from: 0, to: checkTrim)
                .stroke(
                    LinearGradient(
                        colors: [AppColors.quickSetupAccent, AppColors.quickSetupAccentMint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 26, height: 22)
                .scaleEffect(checkScale)
                .opacity(checkOpacity)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            guard ringEnd < 0.2 else { return }

            let impact = UIImpactFeedbackGenerator(style: .soft)
            impact.prepare()
            impact.impactOccurred(intensity: 0.55)

            withAnimation(.easeOut(duration: 0.32)) {
                glowOpacity = 1
            }

            withAnimation(.spring(response: 0.68, dampingFraction: 0.82)) {
                glowScale = 1
                coreScale = 1
            }

            withAnimation(.timingCurve(0.16, 0.84, 0.22, 1, duration: 1.15)) {
                ringEnd = 0.88
                ringRotation = .degrees(8)
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(420))
                let notification = UINotificationFeedbackGenerator()
                notification.prepare()
                withAnimation(.spring(response: 0.52, dampingFraction: 0.72)) {
                    checkOpacity = 1
                    checkScale = 1.03
                    checkTrim = 1
                    pulseOpacity = 0.55
                    pulseScale = 1.04
                }
                notification.notificationOccurred(.success)

                try? await Task.sleep(for: .milliseconds(260))
                let settleImpact = UIImpactFeedbackGenerator(style: .soft)
                settleImpact.prepare()
                withAnimation(.spring(response: 0.48, dampingFraction: 0.9)) {
                    checkScale = 1
                    pulseOpacity = 0
                    pulseScale = 1.12
                    glowScale = 1.02
                }
                settleImpact.impactOccurred(intensity: 0.35)

                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.easeOut(duration: 0.34)) {
                    glowScale = 1
                }
            }
        }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.midY + rect.height * 0.02))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.14))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.10, y: rect.minY + rect.height * 0.14))
        return path
    }
}

private struct QuickSetupRecommendedBadge: View {
    var body: some View {
        Text("R")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(AppColors.quickSetupAccent)
            .frame(width: 16, height: 16, alignment: .leading)
            .offset(y: -1)
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
    let onToggle: (String) -> QuickSetupViewModel.FavoriteCurrencyToggleResult

    var body: some View {
        CurrencyPickerView(
            allCodes: CurrencySelectionSupport.allCurrencyCodesForPicker,
            searchText: $searchText,
            selectedCodes: selectedCodes,
            suggestedCodes: suggestedCodes,
            favoriteCodes: Set(selectedCodes),
            currentSelection: nil,
            primaryPinnedCode: primaryCurrencyCode,
            primaryPinnedTitle: QuickSetupLocalization.tr("quick_setup.common.primary", locale: locale),
            locale: locale,
            onToggleFavorite: { code in
                if onToggle(code) == .added {
                    searchText = ""
                }
            },
            onSelect: { code in
                if onToggle(code) == .added {
                    searchText = ""
                }
            }
        )
        .navigationTitle(QuickSetupLocalization.tr("quick_setup.common.favorite_currencies", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(QuickSetupLocalization.tr("quick_setup.common.done", locale: locale)) {
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text(
                QuickSetupLocalization.format(
                    "quick_setup.favorite_limit_format",
                    locale: locale,
                    "You can select up to %lld currencies",
                    maxSelection
                )
            )
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
            primaryPinnedTitle: QuickSetupLocalization.tr("quick_setup.common.primary", locale: locale),
            locale: locale,
            onToggleFavorite: nil,
            onSelect: { code in
                primaryCurrencyCode = code
                dismiss()
            }
        )
        .navigationTitle(QuickSetupLocalization.tr("quick_setup.common.primary_currency", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(QuickSetupLocalization.tr("quick_setup.common.done", locale: locale)) {
                    dismiss()
                }
            }
        }
    }
}
