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
            GradientBackground()

            VStack(spacing: 0) {
                header
                progressBar

                ScrollView {
                    VStack(spacing: 20) {
                        stepContent
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 120)
                }

                bottomActions
                    .padding(.horizontal, 20)
                    .padding(.bottom, 22)
                    .background(Color.black.opacity(0.001))
            }
        }
        .navigationBarBackButtonHidden(mode == .onboarding)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showLanguageSheet) {
            NavigationStack {
                LanguageSelectionView(selectedLanguage: $viewModel.selectedLanguage)
            }
        }
        .sheet(isPresented: $showPrimaryCurrencySheet) {
            NavigationStack {
                QuickSetupPrimaryCurrencySheet(primaryCurrencyCode: $viewModel.primaryCurrencyCode)
            }
        }
        .sheet(isPresented: $showFavoritesSheet) {
            NavigationStack {
                QuickSetupFavoriteCurrenciesSheet(
                    primaryCurrencyCode: viewModel.primaryCurrencyCode,
                    selectedCodes: viewModel.favoriteCurrencyCodes,
                    maxSelection: QuickSetupViewModel.maxFavoriteCurrencies,
                    onToggle: viewModel.toggleFavoriteCurrency
                )
            }
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
            if mode == .settings {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(AppColors.textPrimary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Быстрая настройка")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer()

            if mode == .onboarding {
                Button("Пропустить") {
                    onSkipped?()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stepProgressText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.textPrimary.opacity(0.12))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: AppColors.financesGradient,
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
        .padding(.horizontal, 20)
        .padding(.top, 12)
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
        VStack(spacing: 14) {
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

            Text("До 4 валют для быстрого выбора в операциях")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var expenseCategoriesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Выберите категории трат")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text("От них зависит, что вы увидите при добавлении расхода")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
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
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? AppColors.textPrimary.opacity(0.18) : AppColors.textPrimary.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isSelected ? AppColors.textPrimary.opacity(0.55) : AppColors.textPrimary.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(selectedExpenseCategoriesText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                Text("Категории можно изменить и добавить позже в процессе работы.")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var productsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Добавьте продукты")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            productTypeIconSelector

            VStack(spacing: 8) {
                TextField("Название", text: $viewModel.productNameInput)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.textPrimary.opacity(0.08)))

                if viewModel.productTypeForCreation == .ticker || viewModel.productTypeForCreation == .crypto {
                    TextField(
                        viewModel.productTypeForCreation == .crypto ? "Тикер (BTC)" : "Тикер (AAPL)",
                        text: $viewModel.productSymbolInput
                    )
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.textPrimary.opacity(0.08)))
                }

                TextField(
                    "Сумма в \(viewModel.primaryCurrencyCode)",
                    text: Binding(
                        get: { AmountInputFormatter.display(viewModel.productAmountInput) },
                        set: { viewModel.productAmountInput = AmountInputFormatter.sanitize($0) }
                    )
                )
                .keyboardType(.decimalPad)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.textPrimary.opacity(0.08)))

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
                        .padding(.vertical, 12)
                        .background(GlassBackground(gradient: AppColors.financesGradient, strokeWidth: 1))
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
                                Text(product.name)
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
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.textPrimary.opacity(0.06)))
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
                        VStack(spacing: 7) {
                            Image(systemName: type.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(width: 30, height: 30)
                            Text(type.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(width: 78, height: 78)
                        .background(
                            ZStack {
                                if selected {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppColors.textPrimary.opacity(0.2))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(AppColors.textPrimary.opacity(0.6), lineWidth: 1)
                                        )
                                        .matchedGeometryEffect(id: "quick_setup_product_type", in: productTypeNamespace)
                                } else {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(AppColors.textPrimary.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(AppColors.textPrimary.opacity(0.1), lineWidth: 1)
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
        return VStack(alignment: .leading, spacing: 14) {
            if showCelebrate {
                QuickSetupCelebrateBadge()
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }

            Text("Безопасность данных")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            Text("Выберите, как хранить ваши данные. Это можно изменить позже в Профиль -> Backup.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)

            VStack(spacing: 10) {
                ForEach(QuickSetupBackupPreference.allCases) { preference in
                    let isSelected = viewModel.backupPreference == preference
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                            viewModel.backupPreference = preference
                        }
                        fireSelectionHaptic()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18, weight: .semibold))
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
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? AppColors.textPrimary.opacity(0.16) : AppColors.textPrimary.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isSelected ? AppColors.textPrimary.opacity(0.55) : AppColors.textPrimary.opacity(0.14), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Коротко: без выгрузки данные остаются только на устройстве. С выгрузкой они попадают в ваш приватный CloudKit.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 8)

            summaryRow(title: "Язык", value: selection.language.displayName)
            summaryRow(title: "Основная валюта", value: selection.primaryCurrencyCode)
            summaryRow(
                title: "Избранные валюты",
                value: selection.favoriteCurrencyCodes.isEmpty ? "Не выбраны" : selection.favoriteCurrencyCodes.joined(separator: ", ")
            )
            summaryRow(title: "Категории трат", value: "\(selection.selectedExpenseCategoryIDs.count)")
            summaryRow(title: "Продукты", value: "\(selection.products.count)")
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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.textPrimary.opacity(0.06)))
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
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(AppColors.textPrimary.opacity(0.08))
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
                .background(
                    GlassBackground(
                        gradient: viewModel.currentStep == .summary ? AppColors.incomeGradient : AppColors.financesGradient,
                        strokeWidth: 1
                    )
                )
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
                .fill(AppColors.textPrimary.opacity(glow ? 0.2 : 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.textPrimary.opacity(glow ? 0.55 : 0.25), lineWidth: 1)
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
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(AppColors.textPrimary.opacity(0.12)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(value)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(14)
            .background(GlassBackground(gradient: gradient, strokeWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct QuickSetupFavoriteCurrenciesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    let primaryCurrencyCode: String
    let selectedCodes: [String]
    let maxSelection: Int
    let onToggle: (String) -> Void

    var body: some View {
        CurrencyPickerView(
            allCodes: CurrencySelectionSupport.allCurrencyCodesForPicker,
            searchText: $searchText,
            selectedCodes: selectedCodes,
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
    @State private var searchText = ""

    var body: some View {
        CurrencyPickerView(
            allCodes: CurrencySelectionSupport.allCurrencyCodesForPicker,
            searchText: $searchText,
            selectedCodes: [],
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
