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
    @Namespace private var productTypeNamespace
    @State private var showCelebrate = false

    private let mode: QuickSetupFlowMode
    private let onCompleted: (() -> Void)?
    private let onSkipped: (() -> Void)?

    private enum FocusField: Hashable {
        case productName
        case productAmount
        case productQuantity
        case productPurchasePrice
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

            VStack(alignment: .leading, spacing: 4) {
                Text("profile.quick_setup")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }

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
                                colors: [AppColors.brandPrimary, Color.cyan],
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
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text(viewModel.currentStep.subtitle(for: quickSetupLocale))
                .font(.system(size: 15, weight: .regular))
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
                gradient: AppColors.coursesGradient
            ) {
                showLanguageSheet = true
            }

            QuickSetupRowCard(
                title: quickSetupText(ru: "Основная валюта", en: "Primary currency"),
                value: viewModel.primaryCurrencyCode,
                icon: "dollarsign.circle.fill",
                gradient: AppColors.financesGradient
            ) {
                showPrimaryCurrencySheet = true
            }

            QuickSetupRowCard(
                title: quickSetupText(ru: "Избранные валюты", en: "Favorite currencies"),
                value: viewModel.favoriteCurrencyCodes.isEmpty ? quickSetupText(ru: "Не выбраны", en: "Not selected") : viewModel.favoriteCurrencyCodes.joined(separator: ", "),
                icon: "star.circle.fill",
                gradient: AppColors.cashbackGradient
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                ForEach(expenseCategoryPresets) { category in
                    let isSelected = viewModel.selectedExpenseCategoryIDs.contains(category.id)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            viewModel.toggleExpenseCategory(raw: category.id)
                        }
                        fireSelectionHaptic()
                    } label: {
                        VStack(spacing: 8) {
                            Text(category.icon)
                                .font(.system(size: 26))
                            Text(category.displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 92)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isSelected ? AppColors.brandPrimary.opacity(0.16) : .white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(isSelected ? AppColors.brandPrimary.opacity(0.9) : .white.opacity(0.08), lineWidth: 1)
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
                Text(quickSetupText(ru: "Категории можно изменить позже", en: "Categories can be changed later"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var productsStep: some View {
        stepSectionCard {
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
                    Text(quickSetupText(ru: "Добавить", en: "Add"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(primaryButtonBackground)
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

            Text(quickSetupText(ru: "Можно добавить позже", en: "Can be added later"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary.opacity(0.9))
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: viewModel.productTypeForCreation)
    }

    private var productTypeIconSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(QuickSetupProductType.allCases) { type in
                    let selected = viewModel.productTypeForCreation == type
                    Button {
                        focusedField = nil
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            viewModel.selectProductType(type)
                        }
                        fireSelectionHaptic()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: type.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(selected ? AppColors.textPrimary : AppColors.textSecondary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(selected ? AppColors.brandPrimary.opacity(0.26) : .white.opacity(0.06))
                                )
                            Text(type.title(for: quickSetupLocale))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                            Text(type.subtitle(for: quickSetupLocale))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(width: 104, height: 98, alignment: .leading)
                        .padding(12)
                        .background(
                            ZStack {
                                if selected {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(AppColors.brandPrimary.opacity(0.16))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(AppColors.brandPrimary.opacity(0.95), lineWidth: 1)
                                        )
                                        .matchedGeometryEffect(id: "quick_setup_product_type", in: productTypeNamespace)
                                } else {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(.white.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(.white.opacity(0.08), lineWidth: 1)
                                        )
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
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
                                .fill(isSelected ? AppColors.brandPrimary.opacity(0.16) : .white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(isSelected ? AppColors.brandPrimary.opacity(0.95) : .white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(quickSetupText(ru: "Ваш выбор", en: "Your selection"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)

                summaryRow(title: quickSetupText(ru: "Язык", en: "Language"), value: selection.language.displayName(for: quickSetupLocale))
                summaryRow(title: quickSetupText(ru: "Основная валюта", en: "Primary currency"), value: selection.primaryCurrencyCode)
                summaryRow(
                    title: quickSetupText(ru: "Избранные валюты", en: "Favorite currencies"),
                    value: selection.favoriteCurrencyCodes.isEmpty ? quickSetupText(ru: "Не выбраны", en: "Not selected") : selection.favoriteCurrencyCodes.joined(separator: ", ")
                )
                summaryRow(title: quickSetupText(ru: "Категории трат", en: "Expense categories"), value: "\(selection.selectedExpenseCategoryIDs.count)")
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
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(AppColors.textPrimary)
                    }
                    Text(viewModel.currentStep == .summary ? quickSetupText(ru: "Завершить", en: "Finish") : viewModel.continueTitle)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(primaryButtonBackground)
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
        String(
            format: String(localized: "quick_setup.step_progress_format"),
            viewModel.currentStep.rawValue + 1,
            QuickSetupStep.allCases.count,
            viewModel.currentStep.title(for: quickSetupLocale)
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

    private var expenseCategoryPresets: [QuickSetupExpenseCategoryPreset] {
        QuickSetupExpenseCategoryPreset.all(for: viewModel.selectedLanguage.locale ?? Locale.current)
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
                .fill(AppColors.brandPrimary.opacity(0.22))
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
            .fill(
                LinearGradient(
                    colors: [AppColors.brandPrimary.opacity(0.34), Color.cyan.opacity(0.2), Color.black.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [AppColors.brandPrimary, Color.cyan.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )
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
                text: Binding(
                    get: { AmountInputFormatter.display(viewModel.productAmountInput) },
                    set: { viewModel.productAmountInput = AmountInputFormatter.sanitize($0) }
                )
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
                        Text(viewModel.productSymbolInput.isEmpty ? quickSetupText(ru: "Не выбран", en: "Not selected") : viewModel.productSymbolInput)
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
                text: Binding(
                    get: { AmountInputFormatter.display(viewModel.productQuantityInput) },
                    set: { viewModel.productQuantityInput = AmountInputFormatter.sanitize($0) }
                )
            )
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: .productQuantity)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
            .id(FocusField.productQuantity)
            .accessibilityIdentifier("quickSetup.productQuantityField")

            TextField(
                viewModel.productPurchasePriceTitle,
                text: Binding(
                    get: { AmountInputFormatter.display(viewModel.productPurchasePriceInput) },
                    set: { viewModel.productPurchasePriceInput = AmountInputFormatter.sanitize($0) }
                )
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
        guard let price = viewModel.productLatestUnitPrice else {
            return "—"
        }
        return moneyText(price, currencyCode: viewModel.productResolvedCurrencyCode)
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
                    .fill(prominence == .accent ? AppColors.brandPrimary.opacity(0.16) : .white.opacity(0.05))
                    .overlay(
                        Capsule()
                            .stroke(prominence == .accent ? AppColors.brandPrimary.opacity(0.9) : .white.opacity(0.08), lineWidth: 1)
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
                .font(.system(size: 18, weight: .bold))
            Text(QuickSetupLocalization.text(locale: locale, ru: "Отлично! Настройка почти готова", en: "Great! Setup is almost complete"))
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(AppColors.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.textPrimary.opacity(glow ? 0.18 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.textPrimary.opacity(glow ? 0.45 : 0.2), lineWidth: 1)
                )
        )
        .scaleEffect(glow ? 1.02 : 0.98)
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
                            .fill((gradient.first ?? AppColors.brandPrimary).opacity(0.2))
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
                                    colors: [
                                        (gradient.first ?? AppColors.brandPrimary).opacity(0.9),
                                        .white.opacity(0.08)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
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
