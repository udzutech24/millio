//
//  FinanceGroupEditorView.swift
//  millio
//

import SwiftUI

// MARK: - Finance Group Editor View

struct FinanceGroupEditorView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var selectedColor: Color = Color.blue
    @State private var selectedCurrency: String? = nil
    @State private var availableCurrencies: [String] = []
    @State private var isLoadingCurrencies = true
    @State private var isFavorite: Bool = false
    @State private var selectedPriority: GroupPriority = .normal
    
    @State private var showCurrencyPicker: Bool = false
    @State private var currencySearchText: String = ""
    
    private let predefinedColors: [Color] = [
        .blue, .cyan, .green, .mint, .purple, .pink,
        .indigo, .orange, .red, .yellow, .teal, .brown
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                ScrollView {
                    VStack(spacing: 24) {
                        nameSection
                        colorSection
                        currencySection
                        prioritySection
                        
                        if let editingGroup = viewModel.state.editingGroup,
                           let accounts = editingGroup.accounts,
                           !accounts.isEmpty {
                            accountsSection(accounts)
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                    .padding(.horizontal, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()
            }
            .navigationTitle(viewModel.state.editingGroup == nil ? "Новая группа" : "Группа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отмена")
                }
                
                if viewModel.state.editingGroup != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            deleteGroup()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Удалить")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        saveGroup()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                    .accessibilityLabel("Сохранить")
                }
            }
            .onAppear {
                if let editing = viewModel.state.editingGroup {
                    name = editing.name
                    selectedCurrency = editing.displayCurrency
                    isFavorite = editing.isFavorite
                    selectedPriority = editing.priority
                    // Находим соответствующий цвет из predefinedColors по hex-значению
                    let editingColorHex = editing.colorHex.uppercased()
                    if let matchingColor = predefinedColors.first(where: { color in
                        color.toHex().uppercased() == editingColorHex
                    }) {
                        selectedColor = matchingColor
                    } else {
                        // Если точного совпадения нет, используем цвет из группы
                        selectedColor = editing.color
                    }
                }
            }
            .task {
                await loadAvailableCurrencies()
            }
            .sheet(isPresented: $showCurrencyPicker) {
                NavigationStack {
                    let favoriteCodes = SettingsManager.shared.favoriteCurrencyCodes
                    CurrencyPickerView(
                        allCodes: availableCurrencies,
                        searchText: $currencySearchText,
                        selectedCodes: favoriteCodes,
                        favoriteCodes: Set(favoriteCodes),
                        currentSelection: selectedCurrency,
                        onToggleFavorite: nil,
                        onSelect: { currency in
                            selectedCurrency = currency
                            showCurrencyPicker = false
                        }
                    )
                    .navigationTitle("Выбор валюты")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отмена") { showCurrencyPicker = false }
                        }
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Название группы")
            FinancesGlassCard {
                TextField("Название", text: $name)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
            }
        }
    }
    
    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Цвет группы")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(predefinedColors, id: \.self) { color in
                        Button {
                            selectedColor = color
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    if selectedColor == color {
                                        Circle()
                                            .stroke(AppColors.textPrimary, lineWidth: 3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var currencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Валюта отображения")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("Валюта")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Spacer()
                        
                        if isLoadingCurrencies {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(AppColors.textTertiary)
                        } else {
                            HStack(spacing: 12) {
                                if selectedCurrency != nil {
                                    Button {
                                        selectedCurrency = nil
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(AppColors.textTertiary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                Button {
                                        showCurrencyPicker = true
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(selectedCurrency ?? viewModel.state.displayCurrency)
                                                .font(.system(size: 16, weight: .semibold))
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 12, weight: .semibold))
                                        }
                                        .foregroundStyle(AppColors.textTertiary)
                                    }
                            }
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Приоритет")
            FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("В избранном", isOn: $isFavorite)
                        .tint(AppColors.toggleOnGreen)
                        .foregroundStyle(AppColors.textPrimary)
                    
                    FinancesRowDivider(leadingPadding: 0)
                    
                    HStack(spacing: 12) {
                        FinancesRadioOption(title: "низкий", isSelected: selectedPriority == .low) { selectedPriority = .low }
                        FinancesRadioOption(title: "обычный", isSelected: selectedPriority == .normal) { selectedPriority = .normal }
                        FinancesRadioOption(title: "высокий", isSelected: selectedPriority == .high) { selectedPriority = .high }
                    }
                    
                    Text("Высокий приоритет — выше в списках.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                }
            }
        }
    }
    
    private func accountsSection(_ accounts: [FinanceAccount]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Счета группы")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    ForEach(accounts) { account in
                        if let accountInfo = viewModel.getAccountInfo(account: account) {
                            HStack(spacing: 12) {
                                // Иконка счета
                                Image(systemName: accountInfo.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.financesGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: 24, height: 24)
                                
                                // Название и сумма счета
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(accountInfo.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                    
                                    HStack(spacing: 4) {
                                        Text(formatAmount(accountInfo.amount, isHidden: viewModel.state.isAmountHidden))
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(accountInfo.isCreditCardDebt ? AppColors.error : AppColors.textSecondary)
                                        
                                        Text(accountInfo.currency)
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                }
                                
                                Spacer()
                                
                                // Кнопка удаления
                                Button {
                                    viewModel.handle(.removeAccountFromGroup(account))
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(AppColors.error)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            
                            if account.id != accounts.last?.id {
                                FinancesRowDivider(leadingPadding: 52)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty
    }
    
    private func saveGroup() {
        let colorHex = selectedColor.toHex()
        viewModel.handle(.updateGroup(name: name, colorHex: colorHex, displayCurrency: selectedCurrency, isFavorite: isFavorite, priority: selectedPriority))
        dismiss()
    }

    private func deleteGroup() {
        guard let editingGroup = viewModel.state.editingGroup else { return }
        viewModel.handle(.deleteGroup(editingGroup))
        dismiss()
    }
    
    private func loadAvailableCurrencies() async {
        isLoadingCurrencies = true
        defer { isLoadingCurrencies = false }
        
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        
        let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
        availableCurrencies = Array(fromRateSource).sorted()
    }
    
    private func formatAmount(_ amount: Double, isHidden: Bool = false) -> String {
        if isHidden {
            // Подсчитываем количество цифр в числе
            let digits = Int(amount.rounded())
            let digitCount = String(digits).count
            // Возвращаем точки вместо цифр
            return String(repeating: "•", count: max(3, digitCount))
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }
}
