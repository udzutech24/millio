//
//  CreditsView.swift
//  millio
//
//  Created by Александр Сидоркин on 11.01.2026.
//

import SwiftUI
import SwiftData

struct CreditsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CreditViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                CreditsContentViewInternal(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = CreditViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Internal Content View

private struct CreditsContentViewInternal: View {
    @ObservedObject var viewModel: CreditViewModel
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Статистика
                    statsSection
                    
                    // Список кредитов
                    creditsListSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Кредиты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.handle(.addCredit)
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCreditEditor },
            set: { if !$0 { viewModel.handle(.hideCreditEditor) } }
        )) {
            CreditEditorView(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showDisplayCurrencySheet },
            set: { if !$0 { viewModel.handle(.hideDisplayCurrencySheet) } }
        )) {
            DisplayCurrencySheet(viewModel: viewModel)
        }
        .task {
            // Загружаем курсы при появлении экрана
            await viewModel.refreshRates()
        }
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        VStack(spacing: 16) {
            // Общий долг
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Всего кредитов")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("\(viewModel.state.credits.count)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Общий долг")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                        
                        Button {
                            viewModel.handle(.showDisplayCurrencySheet)
                        } label: {
                            HStack(spacing: 4) {
                                Text(viewModel.state.displayCurrency)
                                    .font(.system(size: 14, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.creditsGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatBalance(viewModel.state.totalDebt))
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.creditsGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        
                        Text(viewModel.state.displayCurrency)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    
                    if viewModel.state.isLoadingRates {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(AppColors.textTertiary)
                    }
                }
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 20)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.creditsGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            }
            
            // Ежемесячные платежи
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ежемесячные платежи")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatBalance(viewModel.state.totalMonthlyPayments))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Text(viewModel.state.displayCurrency)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.creditsGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            }
            
            // Долг по валютам
            if !viewModel.state.debtByCurrency.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(viewModel.state.debtByCurrency.keys.sorted()), id: \.self) { currency in
                            let debt = viewModel.state.debtByCurrency[currency] ?? 0
                            CurrencyDebtCard(currency: currency, debt: debt)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    // MARK: - Credits List
    
    private var creditsListSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Кредиты")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                if !viewModel.state.filteredCredits.isEmpty {
                    Text("\(viewModel.state.filteredCredits.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            
            if viewModel.state.filteredCredits.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text(viewModel.state.credits.isEmpty ? "Нет кредитов" : "Ничего не найдено")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    if viewModel.state.credits.isEmpty {
                        Text("Добавьте свой первый кредит")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.state.filteredCredits) { credit in
                        CreditRow(
                            credit: credit,
                            viewModel: viewModel
                        ) {
                            viewModel.handle(.editCredit(credit))
                        } onDelete: {
                            viewModel.handle(.deleteCredit(credit))
                        } onToggleFavorite: {
                            viewModel.handle(.toggleFavorite(credit))
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0.00"
    }
}

// MARK: - Currency Debt Card

private struct CurrencyDebtCard: View {
    let currency: String
    let debt: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currency)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
            
            Text(formatBalance(debt))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: AppColors.creditsGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.5
                        )
                }
        }
    }
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0.00"
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let gradientColors: [Color]
    
    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                Capsule()
                    .fill(isSelected ? 
                          LinearGradient(
                            colors: gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                          ) :
                          LinearGradient(
                            colors: [Color.clear],
                            startPoint: .leading,
                            endPoint: .trailing
                          )
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            }
    }
}

// MARK: - Credit Row

private struct CreditRow: View {
    let credit: Credit
    let viewModel: CreditViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Основная область кредита (кликабельна)
                Button(action: onEdit) {
                    HStack(spacing: 16) {
                        // Иконка типа кредита
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: AppColors.creditsGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: credit.creditType.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        
                        // Информация о кредите
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(credit.name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                                
                                if credit.isFavorite {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.creditsGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                // Остаток долга
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Остаток:")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(AppColors.textTertiary)
                                    
                                    Text("\(formatBalance(credit.remainingAmount)) \(credit.currency)")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .lineLimit(1)
                                }
                                
                                // Ежемесячный платеж
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Платеж:")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(AppColors.textTertiary)
                                    
                                    Text("\(formatBalance(credit.monthlyPayment)) \(credit.currency)")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .lineLimit(1)
                                }
                                
                                // Осталось месяцев
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Осталось:")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(AppColors.textTertiary)
                                    
                                    Text("\(credit.monthsRemaining) мес.")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)
                                }
                            }
                        }
                        
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                
                    // Кнопки действий
                    VStack(spacing: 8) {
                        Button {
                            onToggleFavorite()
                        } label: {
                            Image(systemName: credit.isFavorite ? "star.fill" : "star")
                                .font(.system(size: 18))
                                .foregroundStyle(
                                    credit.isFavorite ?
                                    LinearGradient(
                                        colors: AppColors.creditsGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ) :
                                    LinearGradient(
                                        colors: [AppColors.textTertiary],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 18))
                                .foregroundStyle(AppColors.error)
                        }
                        .confirmationDialog("Удалить кредит?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                            Button("Удалить", role: .destructive) {
                                onDelete()
                            }
                            Button("Отмена", role: .cancel) {}
                        } message: {
                            Text("Кредит \"\(credit.name)\" будет удален без возможности восстановления.")
                        }
                    }
            }
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.creditsGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            }
            
            // Прогресс выплаты
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.textTertiary.opacity(0.2))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: AppColors.creditsGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * credit.paymentProgress, height: 4)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
    }
}

// MARK: - Filter Sheets

private struct BankFilterSheet: View {
    @ObservedObject var viewModel: CreditViewModel
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                List {
                    Button {
                        viewModel.handle(.filterByBank(nil))
                        viewModel.handle(.hideBankFilterSheet)
                    } label: {
                        HStack {
                            Text("Все банки")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if viewModel.state.selectedBank == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.creditsGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    
                    ForEach(Bank.allCases, id: \.self) { bank in
                        Button {
                            viewModel.handle(.filterByBank(bank))
                            viewModel.handle(.hideBankFilterSheet)
                        } label: {
                            HStack {
                                Text(bank.displayName)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                if viewModel.state.selectedBank == bank {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.creditsGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Банк")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CreditTypeFilterSheet: View {
    @ObservedObject var viewModel: CreditViewModel
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                List {
                    Button {
                        viewModel.handle(.filterByCreditType(nil))
                        viewModel.handle(.hideCreditTypeFilterSheet)
                    } label: {
                        HStack {
                            Text("Все типы")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if viewModel.state.selectedCreditType == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.creditsGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    
                    ForEach(CreditType.allCases, id: \.self) { type in
                        Button {
                            viewModel.handle(.filterByCreditType(type))
                            viewModel.handle(.hideCreditTypeFilterSheet)
                        } label: {
                            HStack {
                                Text(type.displayName)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                if viewModel.state.selectedCreditType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.creditsGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Тип кредита")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CurrencyFilterSheet: View {
    @ObservedObject var viewModel: CreditViewModel
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                List {
                    Button {
                        viewModel.handle(.filterByCurrency(nil))
                        viewModel.handle(.hideCurrencyFilterSheet)
                    } label: {
                        HStack {
                            Text("Все валюты")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if viewModel.state.selectedCurrency == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.creditsGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    
                    ForEach(Array(Set(viewModel.state.credits.map { $0.currency })).sorted(), id: \.self) { currency in
                        Button {
                            viewModel.handle(.filterByCurrency(currency))
                            viewModel.handle(.hideCurrencyFilterSheet)
                        } label: {
                            HStack {
                                Text(currency)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                if viewModel.state.selectedCurrency == currency {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.creditsGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Валюта")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct DisplayCurrencySheet: View {
    @ObservedObject var viewModel: CreditViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var availableCurrencies: [String] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                if isLoading {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                } else {
                    List {
                        ForEach(availableCurrencies, id: \.self) { currency in
                            Button {
                                viewModel.handle(.setDisplayCurrency(currency))
                                dismiss()
                            } label: {
                                HStack {
                                    Text(currency)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    if viewModel.state.displayCurrency == currency {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: AppColors.creditsGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    }
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Валюта отображения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.creditsGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
            .task {
                await loadAvailableCurrencies()
            }
        }
    }
    
    private func loadAvailableCurrencies() async {
        isLoading = true
        defer { isLoading = false }
        
        // Загружаем курсы, чтобы получить актуальный список валют
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        
        // Получаем валюты из текущего источника курсов
        let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
        // Добавляем валюты из кредитов пользователя
        let fromCredits = Set(viewModel.state.credits.map { $0.currency })
        // Объединяем и сортируем
        availableCurrencies = Array(fromRateSource.union(fromCredits)).sorted()
    }
}

// MARK: - Credit Editor View

private struct CreditEditorView: View {
    @ObservedObject var viewModel: CreditViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var amountText: String = ""
    @State private var monthlyPaymentText: String = ""
    @State private var endDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var remainingAmountText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var selectedBank: Bank = .other
    @State private var selectedCreditType: CreditType = .consumer
    @State private var isFavorite: Bool = false
    @State private var availableCurrencies: [String] = ["RUB", "USD", "EUR"]
    @State private var isLoadingCurrencies: Bool = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    Section {
                        TextField("Название кредита", text: $name)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Основная информация")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        TextField("Сумма кредита", text: Binding(
                            get: { formatNumberForDisplay(amountText) },
                            set: { newValue in
                                // Нормализуем: убираем пробелы и заменяем запятую на точку
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                amountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        
                        TextField("Ежемесячный платеж", text: Binding(
                            get: { formatNumberForDisplay(monthlyPaymentText) },
                            set: { newValue in
                                // Нормализуем: убираем пробелы и заменяем запятую на точку
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                monthlyPaymentText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                        
                        DatePicker("Дата окончания", selection: $endDate, displayedComponents: .date)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        TextField("Остаток долга", text: Binding(
                            get: { formatNumberForDisplay(remainingAmountText) },
                            set: { newValue in
                                // Нормализуем: убираем пробелы и заменяем запятую на точку
                                let normalized = newValue.replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")
                                remainingAmountText = normalized
                            }
                        ))
                        .keyboardType(.decimalPad)
                        .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Параметры кредита")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        if isLoadingCurrencies {
                            HStack {
                                Text("Валюта")
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(AppColors.textTertiary)
                            }
                        } else {
                            Picker("Валюта", selection: $selectedCurrency) {
                                ForEach(availableCurrencies, id: \.self) { currency in
                                    Text(currency).tag(currency)
                                }
                            }
                            .foregroundStyle(AppColors.textPrimary)
                        }
                        
                        Picker("Банк", selection: $selectedBank) {
                            ForEach(Bank.allCases, id: \.self) { bank in
                                Text(bank.displayName).tag(bank)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        
                        Picker("Тип кредита", selection: $selectedCreditType) {
                            ForEach(CreditType.allCases, id: \.self) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        
                        Toggle("В избранном", isOn: $isFavorite)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Дополнительно")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(viewModel.state.editingCredit == nil ? "Новый кредит" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        saveCredit()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.creditsGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let editing = viewModel.state.editingCredit {
                    name = editing.name
                    amountText = String(format: "%.2f", editing.amount)
                    monthlyPaymentText = String(format: "%.2f", editing.monthlyPayment)
                    endDate = editing.endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
                    remainingAmountText = String(format: "%.2f", editing.remainingAmount)
                    selectedCurrency = editing.currency
                    selectedBank = editing.bank
                    selectedCreditType = editing.creditType
                    isFavorite = editing.isFavorite
                } else {
                    // Для нового кредита устанавливаем дату окончания на год вперед
                    endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
                }
                
                // Загружаем доступные валюты
                loadAvailableCurrencies()
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty &&
        parseNumber(amountText) != nil && parseNumber(amountText)! > 0 &&
        parseNumber(monthlyPaymentText) != nil && parseNumber(monthlyPaymentText)! > 0 &&
        parseNumber(remainingAmountText) != nil && parseNumber(remainingAmountText)! >= 0
    }
    
    // MARK: - Currency Loading
    
    private func loadAvailableCurrencies() {
        Task {
            isLoadingCurrencies = true
            defer { isLoadingCurrencies = false }
            
            // Загружаем курсы, чтобы получить актуальный список валют
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            
            // Получаем валюты из текущего источника курсов
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            // Добавляем валюту текущего кредита, если она есть
            var currencies = Array(fromRateSource)
            if !currencies.contains(selectedCurrency) {
                currencies.append(selectedCurrency)
            }
            // Сортируем
            availableCurrencies = currencies.sorted()
        }
    }
    
    // MARK: - Number Formatting Helpers
    
    /// Нормализует число: убирает пробелы и заменяет запятую на точку
    private func normalizeNumber(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
    }
    
    /// Нормализует десятичное число: заменяет запятую на точку
    private func normalizeDecimal(_ text: String) -> String {
        text.replacingOccurrences(of: ",", with: ".")
    }
    
    /// Парсит число из строки (обрабатывает запятую и пробелы)
    private func parseNumber(_ text: String) -> Double? {
        let normalized = normalizeNumber(text)
        return Double(normalized)
    }
    
    /// Парсит десятичное число из строки (обрабатывает запятую)
    private func parseDecimal(_ text: String) -> Double? {
        let normalized = normalizeDecimal(text)
        return Double(normalized)
    }
    
    /// Форматирует число для отображения с пробелами между тысячами
    private func formatNumberForDisplay(_ text: String) -> String {
        // Если текст пустой, возвращаем как есть
        guard !text.isEmpty else { return text }
        
        // Парсим число
        guard let number = parseNumber(text) else {
            // Если не число, возвращаем как есть (может быть в процессе ввода)
            return text
        }
        
        // Форматируем с пробелами между тысячами
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        // Определяем, есть ли десятичная часть
        let normalized = normalizeNumber(text)
        let hasDecimal = normalized.contains(".")
        if !hasDecimal {
            formatter.maximumFractionDigits = 0
        }
        
        return formatter.string(from: NSNumber(value: number)) ?? text
    }
    
    private func saveCredit() {
        guard let amount = parseNumber(amountText),
              let monthlyPayment = parseNumber(monthlyPaymentText),
              let remainingAmount = parseNumber(remainingAmountText) else {
            return
        }
        
        viewModel.handle(.updateCredit(
            name: name,
            amount: amount,
            monthlyPayment: monthlyPayment,
            endDate: endDate,
            remainingAmount: remainingAmount,
            currency: selectedCurrency,
            bank: selectedBank,
            creditType: selectedCreditType,
            isFavorite: isFavorite
        ))
        
        dismiss()
    }
}

#Preview {
    NavigationStack {
        CreditsView()
    }
}
