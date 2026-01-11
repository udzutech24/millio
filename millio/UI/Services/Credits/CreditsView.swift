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
                    
                    // Поиск и фильтры
                    searchAndFiltersSection
                    
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
            get: { viewModel.state.showBankFilterSheet },
            set: { if !$0 { viewModel.handle(.hideBankFilterSheet) } }
        )) {
            BankFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCreditTypeFilterSheet },
            set: { if !$0 { viewModel.handle(.hideCreditTypeFilterSheet) } }
        )) {
            CreditTypeFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCurrencyFilterSheet },
            set: { if !$0 { viewModel.handle(.hideCurrencyFilterSheet) } }
        )) {
            CurrencyFilterSheet(viewModel: viewModel)
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
                        
                        Text(viewModel.state.displayCurrency)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
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
    
    // MARK: - Search and Filters
    
    private var searchAndFiltersSection: some View {
        VStack(spacing: 12) {
            // Поиск
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.textTertiary)
                
                TextField("Поиск кредитов...", text: Binding(
                    get: { viewModel.state.searchText },
                    set: { viewModel.handle(.search($0)) }
                ))
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
            
            // Фильтры
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Фильтр по банку
                    Button {
                        viewModel.handle(.showBankFilterSheet)
                    } label: {
                        FilterChip(
                            title: viewModel.state.selectedBank?.displayName ?? "Банк",
                            isSelected: viewModel.state.selectedBank != nil,
                            gradientColors: AppColors.creditsGradient
                        )
                    }
                    
                    // Фильтр по типу кредита
                    Button {
                        viewModel.handle(.showCreditTypeFilterSheet)
                    } label: {
                        FilterChip(
                            title: viewModel.state.selectedCreditType?.displayName ?? "Тип",
                            isSelected: viewModel.state.selectedCreditType != nil,
                            gradientColors: AppColors.creditsGradient
                        )
                    }
                    
                    // Фильтр по валюте
                    Button {
                        viewModel.handle(.showCurrencyFilterSheet)
                    } label: {
                        FilterChip(
                            title: viewModel.state.selectedCurrency ?? "Валюта",
                            isSelected: viewModel.state.selectedCurrency != nil,
                            gradientColors: AppColors.creditsGradient
                        )
                    }
                    
                    if viewModel.state.selectedBank != nil ||
                       viewModel.state.selectedCreditType != nil ||
                       viewModel.state.selectedCurrency != nil {
                        Button {
                            viewModel.handle(.clearFilters)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Сбросить")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.error)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background {
                                Capsule()
                                    .fill(.ultraThinMaterial)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
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
                        CreditRow(credit: credit) {
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
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    
    var body: some View {
        Button {
            onEdit()
        } label: {
            VStack(spacing: 0) {
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
                        
                        HStack(spacing: 12) {
                            // Остаток долга
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Остаток")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(AppColors.textTertiary)
                                
                                Text("\(formatBalance(credit.remainingAmount)) \(credit.currency)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                            
                            // Ежемесячный платеж
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Платеж")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(AppColors.textTertiary)
                                
                                Text("\(formatBalance(credit.monthlyPayment)) \(credit.currency)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                            
                            // Осталось месяцев
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Осталось")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(AppColors.textTertiary)
                                
                                Text("\(credit.monthsRemaining) мес.")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                        }
                    }
                    
                    Spacer()
                    
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
                        
                        Menu {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18))
                                .foregroundStyle(AppColors.textSecondary)
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
        .buttonStyle(.plain)
    }
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                List {
                    ForEach(CurrencyRateService.shared.getAvailableCurrencies(), id: \.self) { currency in
                        Button {
                            viewModel.handle(.setDisplayCurrency(currency))
                            viewModel.handle(.hideDisplayCurrencySheet)
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
            .navigationTitle("Валюта отображения")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Credit Editor View

private struct CreditEditorView: View {
    @ObservedObject var viewModel: CreditViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var amountText: String = ""
    @State private var interestRateText: String = ""
    @State private var monthlyPaymentText: String = ""
    @State private var startDate: Date = Date()
    @State private var termMonthsText: String = ""
    @State private var selectedCurrency: String = "RUB"
    @State private var selectedBank: Bank = .other
    @State private var selectedCreditType: CreditType = .consumer
    
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
                        TextField("Сумма кредита", text: $amountText)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        TextField("Процентная ставка (% годовых)", text: $interestRateText)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        TextField("Ежемесячный платеж", text: $monthlyPaymentText)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        DatePicker("Дата начала", selection: $startDate, displayedComponents: .date)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        TextField("Срок в месяцах", text: $termMonthsText)
                            .keyboardType(.numberPad)
                            .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Параметры кредита")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    Section {
                        Picker("Валюта", selection: $selectedCurrency) {
                            ForEach(CurrencyRateService.shared.getAvailableCurrencies(), id: \.self) { currency in
                                Text(currency).tag(currency)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        
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
                    interestRateText = String(format: "%.2f", editing.interestRate)
                    monthlyPaymentText = String(format: "%.2f", editing.monthlyPayment)
                    startDate = editing.startDate
                    termMonthsText = String(editing.termMonths)
                    selectedCurrency = editing.currency
                    selectedBank = editing.bank
                    selectedCreditType = editing.creditType
                }
            }
        }
    }
    
    private var isValid: Bool {
        !name.isEmpty &&
        Double(amountText) != nil && Double(amountText)! > 0 &&
        Double(interestRateText) != nil && Double(interestRateText)! >= 0 &&
        Double(monthlyPaymentText) != nil && Double(monthlyPaymentText)! > 0 &&
        Int(termMonthsText) != nil && Int(termMonthsText)! > 0
    }
    
    private func saveCredit() {
        guard let amount = Double(amountText),
              let interestRate = Double(interestRateText),
              let monthlyPayment = Double(monthlyPaymentText),
              let termMonths = Int(termMonthsText) else {
            return
        }
        
        viewModel.handle(.updateCredit(
            name: name,
            amount: amount,
            interestRate: interestRate,
            monthlyPayment: monthlyPayment,
            startDate: startDate,
            termMonths: termMonths,
            currency: selectedCurrency,
            bank: selectedBank,
            creditType: selectedCreditType
        ))
        
        dismiss()
    }
}

#Preview {
    NavigationStack {
        CreditsView()
    }
}
