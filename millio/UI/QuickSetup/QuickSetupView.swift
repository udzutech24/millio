import SwiftUI
import SwiftData
import UIKit

struct QuickSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        ZStack {
            quickSetupBackground

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        progressBar
                        stepHero
                        stepContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 132)
                }

                bottomActions
                    .padding(.top, 14)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)
                    .background(
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.9), Color.black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .navigationBarBackButtonHidden(mode == .onboarding)
        .toolbarBackground(.hidden, for: .navigationBar)
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
                    suggestedCodes: viewModel.recommendedCurrencyCodes
                )
            }
        }
        .sheet(isPresented: $showFavoritesSheet) {
            NavigationStack {
                QuickSetupFavoriteCurrenciesSheet(
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
        .alert("Не удалось применить настройку", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: viewModel.currentStep) { _, newStep in
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Quick setup")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .textCase(.uppercase)
                Text("Быстрая настройка")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer()

            if mode == .onboarding {
                Button("Пропустить") {
                    onSkipped?()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.brandPrimary)
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
            Text(viewModel.currentStep.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text(viewModel.currentStep.subtitle)
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
                title: "Язык",
                value: viewModel.selectedLanguage.displayName,
                icon: "globe",
                gradient: AppColors.coursesGradient
            ) {
                showLanguageSheet = true
            }

            QuickSetupRowCard(
                title: "Основная валюта",
                value: viewModel.primaryCurrencyCode,
                icon: "dollarsign.circle.fill",
                gradient: AppColors.financesGradient
            ) {
                showPrimaryCurrencySheet = true
            }

            QuickSetupRowCard(
                title: "Избранные валюты",
                value: viewModel.favoriteCurrencyCodes.isEmpty ? "Не выбраны" : viewModel.favoriteCurrencyCodes.joined(separator: ", "),
                icon: "star.circle.fill",
                gradient: AppColors.cashbackGradient
            ) {
                showFavoritesSheet = true
            }

            HStack(spacing: 8) {
                quickSetupTag("Основная: \(viewModel.primaryCurrencyCode)")
                quickSetupTag("Избранных: \(viewModel.favoriteCurrencyCodes.count)/\(QuickSetupViewModel.maxFavoriteCurrencies)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var expenseCategoriesStep: some View {
        stepSectionCard {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    quickActionChip(
                        title: "Рекомендуемые",
                        systemImage: "sparkles",
                        prominence: .accent
                    ) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            viewModel.applyRecommendedExpenseCategories()
                        }
                    }

                    quickActionChip(
                        title: "Очистить",
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
                Text("Категории можно изменить позже.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var productsStep: some View {
        stepSectionCard {
            productTypeIconSelector

            if viewModel.products.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Необязательно")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.brandPrimary)
                    Text("Добавьте только те продукты, которые хотите сразу увидеть в Финансах. Остальное можно создать позже.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }

            VStack(spacing: 8) {
                if viewModel.isMarketProductDraft {
                    marketDraftFields
                } else {
                    standardDraftFields
                }

                Button {
                    let added = viewModel.addDraftProduct()
                    if !added {
                        fireWarningHaptic()
                        errorMessage = viewModel.lastAddDraftError ?? String(localized: "quick_setup.error.check_data")
                    } else {
                        fireSuccessHaptic()
                    }
                } label: {
                    Text("Добавить")
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

            Text("Можно добавить позже")
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
                            Text(type.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                            Text(type.subtitle)
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
                QuickSetupCelebrateBadge()
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
                                Text(preference.title)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(AppColors.textPrimary)

                            Text(preference.subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)

                            Text(preference.details)
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
                Text("Ваш выбор")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)

                summaryRow(title: "Язык", value: selection.language.displayName)
                summaryRow(title: "Основная валюта", value: selection.primaryCurrencyCode)
                summaryRow(
                    title: "Избранные валюты",
                    value: selection.favoriteCurrencyCodes.isEmpty ? "Не выбраны" : selection.favoriteCurrencyCodes.joined(separator: ", ")
                )
                summaryRow(title: "Категории трат", value: "\(selection.selectedExpenseCategoryIDs.count)")
                summaryRow(title: "Продукты", value: "\(selection.products.count)")
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
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        viewModel.goBackStep()
                    }
                    fireSelectionHaptic()
                } label: {
                    Text("Назад")
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
            }

            Button {
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
                    Text(viewModel.currentStep == .summary ? "Завершить" : viewModel.continueTitle)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(primaryButtonBackground)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canContinue || isSaving)
            .opacity((!viewModel.canContinue || isSaving) ? 0.55 : 1)
        }
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
            viewModel.currentStep.title
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
        if let marketSnapshot = product.marketSnapshot {
            let quantityText = AmountInputFormatter.display(AmountInputFormatter.plainString(from: marketSnapshot.quantity))
            return "\(product.type.title) • \(quantityText) × \(marketSnapshot.purchaseUnitPrice.formatted(.number.precision(.fractionLength(0...4)))) • \(moneyText(product.amount, currencyCode: product.currencyCode))"
        }
        let amountText = moneyText(product.amount, currencyCode: product.currencyCode)
        return String(format: String(localized: "quick_setup.product_summary_format"), product.type.title, amountText)
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
            TextField("Название", text: $viewModel.productNameInput)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))

            TextField(
                viewModel.productAmountFieldTitle,
                text: Binding(
                    get: { AmountInputFormatter.display(viewModel.productAmountInput) },
                    set: { viewModel.productAmountInput = AmountInputFormatter.sanitize($0) }
                )
            )
            .keyboardType(.decimalPad)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
        }
    }

    private var marketDraftFields: some View {
        VStack(spacing: 10) {
            Button {
                showMarketSearchSheet = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColors.brandPrimary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.productMarketSearchTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        Text(viewModel.productSymbolInput.isEmpty ? "Не выбран" : viewModel.productSymbolInput)
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
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))

            TextField(
                viewModel.productPurchasePriceTitle,
                text: Binding(
                    get: { AmountInputFormatter.display(viewModel.productPurchasePriceInput) },
                    set: { viewModel.productPurchasePriceInput = AmountInputFormatter.sanitize($0) }
                )
            )
            .keyboardType(.decimalPad)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Текущая цена")
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
                        Text("Позиция")
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
                        Text("Рост/убыток")
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
    @State private var glow = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold))
            Text("Отлично! Настройка почти готова")
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
            primaryPinnedTitle: "Основная",
            onToggleFavorite: { code in
                onToggle(code)
            },
            onSelect: { code in
                onToggle(code)
            }
        )
        .navigationTitle("Избранные валюты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Готово") {
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
            primaryPinnedTitle: "Основная",
            onToggleFavorite: nil,
            onSelect: { code in
                primaryCurrencyCode = code
                dismiss()
            }
        )
        .navigationTitle("Основная валюта")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Готово") {
                    dismiss()
                }
            }
        }
    }
}
