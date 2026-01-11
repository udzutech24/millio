//
//  CardIndexView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData

struct CardIndexView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CardViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                CardContentViewInternal(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = CardViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Internal Content View

private struct CardContentViewInternal: View {
    @ObservedObject var viewModel: CardViewModel
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Статистика
                    statsSection
                    
                    // Поиск и фильтры
                    searchAndFiltersSection
                    
                    // Список карт
                    cardsListSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Карты")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.handle(.addCard)
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCardEditor },
            set: { if !$0 { viewModel.handle(.hideCardEditor) } }
        )) {
            CardEditorView(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showBankFilterSheet },
            set: { if !$0 { viewModel.handle(.hideBankFilterSheet) } }
        )) {
            BankFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCardTypeFilterSheet },
            set: { if !$0 { viewModel.handle(.hideCardTypeFilterSheet) } }
        )) {
            CardTypeFilterSheet(viewModel: viewModel)
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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Всего карт")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("\(viewModel.state.cards.count)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Общий баланс")
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
                                    colors: AppColors.cardIndexGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatBalance(viewModel.state.totalBalance))
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.cardIndexGradient,
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
                                    colors: AppColors.cardIndexGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            }
            
            // Баланс по валютам
            if !viewModel.state.balanceByCurrency.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(viewModel.state.balanceByCurrency.keys.sorted()), id: \.self) { currency in
                            let balance = viewModel.state.balanceByCurrency[currency] ?? 0
                            CurrencyBalanceCard(currency: currency, balance: balance)
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
                
                TextField("Поиск карт...", text: Binding(
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
                                    colors: AppColors.cardIndexGradient,
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
                            isSelected: viewModel.state.selectedBank != nil
                        )
                    }
                    
                    // Фильтр по типу
                    Button {
                        viewModel.handle(.showCardTypeFilterSheet)
                    } label: {
                        FilterChip(
                            title: viewModel.state.selectedCardType?.displayName ?? "Тип",
                            isSelected: viewModel.state.selectedCardType != nil
                        )
                    }
                    
                    // Фильтр по валюте
                    Button {
                        viewModel.handle(.showCurrencyFilterSheet)
                    } label: {
                        FilterChip(
                            title: viewModel.state.selectedCurrency ?? "Валюта",
                            isSelected: viewModel.state.selectedCurrency != nil
                        )
                    }
                    
                    if viewModel.state.selectedBank != nil ||
                       viewModel.state.selectedCardType != nil ||
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
    
    // MARK: - Cards List
    
    private var cardsListSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Карты")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                if !viewModel.state.filteredCards.isEmpty {
                    Text("\(viewModel.state.filteredCards.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            
            if viewModel.state.filteredCards.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text(viewModel.state.cards.isEmpty ? "Нет карт" : "Ничего не найдено")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    if viewModel.state.cards.isEmpty {
                        Text("Добавьте свою первую карту")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.state.filteredCards) { card in
                        CardRow(card: card) {
                            viewModel.handle(.editCard(card))
                        } onDelete: {
                            viewModel.handle(.deleteCard(card))
                        } onToggleFavorite: {
                            viewModel.handle(.toggleFavorite(card))
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

// MARK: - Currency Balance Card

private struct CurrencyBalanceCard: View {
    let currency: String
    let balance: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currency)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
            
            Text(formatBalance(balance))
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
                                colors: AppColors.cardIndexGradient,
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
                            colors: AppColors.cardIndexGradient,
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
                                    colors: AppColors.cardIndexGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            }
    }
}

// MARK: - Card Row

private struct CardRow: View {
    let card: Card
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void
    
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Основная область карты (кликабельна)
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    // Иконка карты
                    Image(systemName: card.cardType.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.cardIndexGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                        }
                    
                    // Информация о карте
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Text(card.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            
                            if card.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.cardIndexGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                        }
                        
                        Text(card.bank.displayName)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        
                        Text(card.maskedNumber)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    
                    Spacer(minLength: 8)
                    
                    // Финансовая информация
                    VStack(alignment: .trailing, spacing: 3) {
                        if card.cardType == .credit, let limit = card.creditLimit {
                            // Для кредитных карт: долг в одну строку
                            HStack(spacing: 4) {
                                Text("Долг:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppColors.textTertiary)
                                Text("\(formatBalance(card.debt)) \(card.currency)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.error)
                            }
                            
                            HStack(spacing: 4) {
                                Text("Лимит:")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(AppColors.textTertiary)
                                Text("\(formatBalance(limit))")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        } else {
                            // Для дебетовых карт: баланс
                            Text("\(formatBalance(card.balance)) \(card.currency)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        
                        // Тип карты (компактно)
                        Text(card.cardType.displayName)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            
            // Кнопки действий (компактные)
            VStack(spacing: 8) {
                // Кнопка избранного
                Button {
                    onToggleFavorite()
                } label: {
                    Image(systemName: card.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(
                            card.isFavorite ?
                            LinearGradient(
                                colors: AppColors.cardIndexGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: [AppColors.textTertiary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                
                // Кнопка удаления
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.error)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .confirmationDialog("Удалить карту?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                    Button("Удалить", role: .destructive) {
                        onDelete()
                    }
                    Button("Отмена", role: .cancel) {}
                } message: {
                    Text("Карта \"\(card.name)\" будет удалена без возможности восстановления.")
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: AppColors.cardIndexGradient,
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

// MARK: - Card Editor View

struct CardEditorView: View {
    @ObservedObject var viewModel: CardViewModel
    @State private var card: Card
    @State private var isNewCard: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var creditLimitText: String = ""
    
    init(viewModel: CardViewModel) {
        self.viewModel = viewModel
        if let editing = viewModel.state.editingCard {
            let newCard = Card(
                name: editing.name,
                cardNumber: editing.cardNumber,
                bank: editing.bank,
                cardType: editing.cardType,
                currency: editing.currency,
                balance: editing.balance,
                creditLimit: editing.creditLimit,
                expiryDate: editing.expiryDate,
                cardholderName: editing.cardholderName,
                cardColor: editing.cardColor,
                isFavorite: editing.isFavorite
            )
            _card = State(initialValue: newCard)
            _creditLimitText = State(initialValue: editing.creditLimit.map { String(format: "%.2f", $0) } ?? "")
            _isNewCard = State(initialValue: false)
        } else {
            _card = State(initialValue: Card(
                name: "",
                cardNumber: "",
                bank: .other,
                cardType: .debit,
                currency: "RUB",
                balance: 0.0
            ))
            _creditLimitText = State(initialValue: "")
            _isNewCard = State(initialValue: true)
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    Section("Основная информация") {
                        TextField("Название карты", text: $card.name)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        TextField("Номер карты (последние 4 цифры)", text: $card.cardNumber)
                            .keyboardType(.numberPad)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Picker("Банк", selection: $card.bankRaw) {
                            ForEach(Bank.allCases, id: \.rawValue) { bank in
                                Text(bank.displayName).tag(bank.rawValue)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        
                        Picker("Тип карты", selection: $card.cardTypeRaw) {
                            ForEach(CardType.allCases, id: \.rawValue) { type in
                                Text(type.displayName).tag(type.rawValue)
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        .onChange(of: card.cardTypeRaw) { oldValue, newValue in
                            // Если меняем на дебетовую, очищаем лимит
                            if newValue == CardType.debit.rawValue {
                                card.creditLimit = nil
                                creditLimitText = ""
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    
                    Section("Финансы") {
                        TextField("Валюта", text: $card.currency)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        TextField("Баланс", value: $card.balance, format: .number)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(AppColors.textPrimary)
                        
                        if card.cardType == .credit {
                            TextField("Кредитный лимит", text: $creditLimitText)
                                .keyboardType(.decimalPad)
                                .foregroundStyle(AppColors.textPrimary)
                                .onChange(of: creditLimitText) { oldValue, newValue in
                                    if let limit = Double(newValue.replacingOccurrences(of: ",", with: ".")) {
                                        card.creditLimit = limit
                                    } else if newValue.isEmpty {
                                        card.creditLimit = nil
                                    }
                                }
                        }
                    }
                    .listRowBackground(Color.clear)
                    
                    Section("Дополнительно") {
                        TextField("Дата окончания (MM/YY)", text: Binding(
                            get: { card.expiryDate ?? "" },
                            set: { card.expiryDate = $0.isEmpty ? nil : $0 }
                        ))
                        .foregroundStyle(AppColors.textPrimary)
                        
                        TextField("Имя держателя", text: Binding(
                            get: { card.cardholderName ?? "" },
                            set: { card.cardholderName = $0.isEmpty ? nil : $0 }
                        ))
                        .foregroundStyle(AppColors.textPrimary)
                        
                        Toggle("Избранная", isOn: $card.isFavorite)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isNewCard ? "Новая карта" : "Редактирование")
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
                        viewModel.handle(.updateCard(card))
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .disabled(card.name.isEmpty || card.cardNumber.isEmpty)
                }
            }
        }
    }
}

// MARK: - Filter Sheets

private struct BankFilterSheet: View {
    @ObservedObject var viewModel: CardViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                List {
                    Button {
                        viewModel.handle(.filterByBank(nil))
                        dismiss()
                    } label: {
                        HStack {
                            Text("Все банки")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if viewModel.state.selectedBank == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.cardIndexGradient,
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
                            dismiss()
                        } label: {
                            HStack {
                                Text(bank.displayName)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                if viewModel.state.selectedBank == bank {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.cardIndexGradient,
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
            .navigationTitle("Выбор банка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cardIndexGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
        }
    }
}

private struct CardTypeFilterSheet: View {
    @ObservedObject var viewModel: CardViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                List {
                    Button {
                        viewModel.handle(.filterByCardType(nil))
                        dismiss()
                    } label: {
                        HStack {
                            Text("Все типы")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if viewModel.state.selectedCardType == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.cardIndexGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    
                    ForEach(CardType.allCases, id: \.self) { type in
                        Button {
                            viewModel.handle(.filterByCardType(type))
                            dismiss()
                        } label: {
                            HStack {
                                Text(type.displayName)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                if viewModel.state.selectedCardType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.cardIndexGradient,
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
            .navigationTitle("Выбор типа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cardIndexGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
        }
    }
}

private struct CurrencyFilterSheet: View {
    @ObservedObject var viewModel: CardViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                List {
                    Button {
                        viewModel.handle(.filterByCurrency(nil))
                        dismiss()
                    } label: {
                        HStack {
                            Text("Все валюты")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if viewModel.state.selectedCurrency == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.cardIndexGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    
                    ForEach(Array(Set(viewModel.state.cards.map { $0.currency })).sorted(), id: \.self) { currency in
                        Button {
                            viewModel.handle(.filterByCurrency(currency))
                            dismiss()
                        } label: {
                            HStack {
                                Text(currency)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                if viewModel.state.selectedCurrency == currency {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.cardIndexGradient,
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
            .navigationTitle("Выбор валюты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cardIndexGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
        }
    }
}

private struct DisplayCurrencySheet: View {
    @ObservedObject var viewModel: CardViewModel
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
                                                    colors: AppColors.cardIndexGradient,
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
                            colors: AppColors.cardIndexGradient,
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
        // Добавляем валюты из карт пользователя
        let fromCards = Set(viewModel.state.cards.map { $0.currency })
        // Объединяем и сортируем
        availableCurrencies = Array(fromRateSource.union(fromCards)).sorted()
    }
}

#Preview {
    NavigationStack {
        CardIndexView()
    }
    .modelContainer(for: [Card.self])
}
