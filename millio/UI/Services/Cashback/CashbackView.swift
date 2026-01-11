//
//  CashbackView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData

struct CashbackView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CashbackViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                CashbackContentViewInternal(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = CashbackViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Content View

private struct CashbackContentViewInternal: View {
    @ObservedObject var viewModel: CashbackViewModel
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Список кешбэков
                    if viewModel.state.cashbacks.isEmpty {
                        emptyStateView
                    } else {
                        cashbacksList
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Кешбэк")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.handle(.addCashback)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.cashbackGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCashbackEditor },
            set: { if !$0 { viewModel.handle(.hideCashbackEditor) } }
        )) {
            CashbackEditorView(viewModel: viewModel)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "percent")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: AppColors.cashbackGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Нет кешбэков")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            
            Text("Добавьте свой первый кешбэк")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
    }
    
    // MARK: - Cashbacks List
    
    private var cashbacksList: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.state.cashbacks) { cashback in
                CashbackRowView(cashback: cashback, viewModel: viewModel)
            }
        }
    }
}

// MARK: - Cashback Row View

private struct CashbackRowView: View {
    let cashback: Cashback
    @ObservedObject var viewModel: CashbackViewModel
    @State private var showCards: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Основная информация о кешбэке
            Button {
                viewModel.handle(.editCashback(cashback))
            } label: {
                HStack(spacing: 16) {
                    // Иконка категории
                    Image(systemName: cashback.category.icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.cashbackGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                        }
                    
                    // Информация
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cashback.category.displayName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        
                        Text(cashback.formattedPercentage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.cashbackGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer(minLength: 0)
                    
                    HStack(spacing: 8) {
                        // Кнопка удаления
                        Button {
                            viewModel.handle(.deleteCashback(cashback))
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.error)
                                .frame(width: 32, height: 32)
                                .background {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                }
                        }
                        .buttonStyle(.plain)
                        
                        // Кнопка показа карт
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showCards.toggle()
                            }
                        } label: {
                            Image(systemName: showCards ? "chevron.up" : "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                                .frame(width: 32, height: 32)
                                .background {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    LinearGradient(
                                        colors: AppColors.cashbackGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.5
                                )
                        }
                }
            }
            .buttonStyle(.plain)
            
            // Карты для этого кешбэка
            if showCards {
                cardsSection
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let cards = viewModel.getCardsForCashback(cashback)
            
            if cards.isEmpty {
                Text("Нет доступных карт")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            } else {
                Text("Используйте эти карты для получения кешбэка:")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                
                ForEach(cards) { card in
                    HStack(spacing: 12) {
                        Image(systemName: card.cardType.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.cashbackGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 40, height: 40)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                            }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            
                            Text(card.bank.displayName)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        
                        Spacer()
                        
                        if card.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: AppColors.cashbackGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - Cashback Editor View

/// Режим создания кэшбеков
enum CashbackCreationMode {
    case createCashback // Создать кэшбек → выбрать карты
    case addToCard // Выбрать карту → добавить кэшбеки
}

private struct CashbackEditorView: View {
    @ObservedObject var viewModel: CashbackViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var creationMode: CashbackCreationMode = .createCashback
    @State private var selectedCategory: CashbackCategory = .other
    @State private var percentageText: String = ""
    @State private var selectedCardIDs: Set<String> = []
    @State private var showCardPicker: Bool = false
    
    // Режим "Добавить к карте"
    @State private var selectedCardID: String? = nil
    @State private var cardCashbacks: [CashbackCategory: String] = [:] // Категория -> процент (текст)
    
    var isEditing: Bool {
        viewModel.state.editingCashback != nil
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Переключатель режимов (только при создании нового)
                        if !isEditing {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Режим создания")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                
                                Picker("Режим", selection: $creationMode) {
                                    Text("Создать кэшбек").tag(CashbackCreationMode.createCashback)
                                    Text("Добавить к карте").tag(CashbackCreationMode.addToCard)
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        
                        // Контент в зависимости от режима
                        if creationMode == .createCashback || isEditing {
                            // Режим "Создать кэшбек" (текущий функционал)
                            createCashbackModeContent
                        } else {
                            // Режим "Добавить к карте"
                            addToCardModeContent
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(isEditing ? "Редактирование" : "Новый кешбэк")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textSecondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        saveCashback()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cashbackGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .sheet(isPresented: $showCardPicker) {
                if creationMode == .createCashback || isEditing {
                    CashbackCardPickerView(
                        selectedCardIDs: $selectedCardIDs,
                        availableCards: viewModel.state.availableCards
                    )
                } else {
                    CashbackSingleCardPickerView(
                        selectedCardID: Binding(
                            get: { selectedCardID ?? "" },
                            set: { selectedCardID = $0.isEmpty ? nil : $0 }
                        ),
                        availableCards: viewModel.state.availableCards
                    )
                }
            }
            .onAppear {
                if let editing = viewModel.state.editingCashback {
                    selectedCategory = editing.category
                    percentageText = String(format: "%.1f", editing.percentage)
                    let validCardIDs = editing.cardIDs.filter { cardID in
                        viewModel.getCard(byID: cardID) != nil
                    }
                    selectedCardIDs = Set(validCardIDs)
                }
            }
        }
    }
    
    // MARK: - Create Cashback Mode Content
    
    var createCashbackModeContent: some View {
        VStack(spacing: 24) {
            // Категория
            VStack(alignment: .leading, spacing: 12) {
                Text("Категория")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                ForEach(CashbackCategory.allCases, id: \.self) { category in
                                    Button {
                                        selectedCategory = category
                                    } label: {
                                        VStack(spacing: 8) {
                                            Image(systemName: category.icon)
                                                .font(.system(size: 24, weight: .semibold))
                                                .foregroundStyle(
                                                    selectedCategory == category ?
                                                    LinearGradient(
                                                        colors: AppColors.cashbackGradient,
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    ) :
                                                    LinearGradient(
                                                        colors: [AppColors.textTertiary, AppColors.textTertiary],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                            
                                            Text(category.displayName)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(
                                                    selectedCategory == category ?
                                                    AppColors.textPrimary :
                                                    AppColors.textSecondary
                                                )
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background {
                                            RoundedRectangle(cornerRadius: 16)
                                                .fill(.ultraThinMaterial)
                                                .overlay {
                                                    if selectedCategory == category {
                                                        RoundedRectangle(cornerRadius: 16)
                                                            .stroke(
                                                                LinearGradient(
                                                                    colors: AppColors.cashbackGradient,
                                                                    startPoint: .leading,
                                                                    endPoint: .trailing
                                                                ),
                                                                lineWidth: 1.5
                                                            )
                                                    }
                                                }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // Процент
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Процент кешбэка")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            
                            HStack(spacing: 12) {
                                TextField("0", text: $percentageText)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .keyboardType(.decimalPad)
                                    .padding(16)
                                    .background {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(.ultraThinMaterial)
                                    }
                                
                                Text("%")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        
                        // Привязанные карты
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Привязанные карты")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                
                                Spacer()
                                
                                if !selectedCardIDs.isEmpty {
                                    Text("\(selectedCardIDs.count)")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.cashbackGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background {
                                            Capsule()
                                                .fill(.ultraThinMaterial)
                                        }
                                }
                            }
                            
                            Button {
                                showCardPicker = true
                            } label: {
                                HStack(spacing: 16) {
                                    // Фильтруем только существующие карты
                                    let validCardIDs = selectedCardIDs.filter { viewModel.getCard(byID: $0) != nil }
                                    
                                    if !validCardIDs.isEmpty {
                                        // Показываем первые 3 карты
                                        HStack(spacing: -8) {
                                            ForEach(Array(validCardIDs.prefix(3)), id: \.self) { cardID in
                                                if let card = viewModel.getCard(byID: cardID) {
                                                    Image(systemName: card.cardType.icon)
                                                        .font(.system(size: 20, weight: .semibold))
                                                        .foregroundStyle(
                                                            LinearGradient(
                                                                colors: AppColors.cashbackGradient,
                                                                startPoint: .leading,
                                                                endPoint: .trailing
                                                            )
                                                        )
                                                        .frame(width: 40, height: 40)
                                                        .background {
                                                            Circle()
                                                                .fill(.ultraThinMaterial)
                                                                .overlay {
                                                                    Circle()
                                                                        .stroke(
                                                                            LinearGradient(
                                                                                colors: AppColors.cashbackGradient,
                                                                                startPoint: .leading,
                                                                                endPoint: .trailing
                                                                            ),
                                                                            lineWidth: 2
                                                                        )
                                                                }
                                                        }
                                                }
                                            }
                                            
                                            if validCardIDs.count > 3 {
                                                Text("+\(validCardIDs.count - 3)")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(AppColors.textPrimary)
                                                    .frame(width: 40, height: 40)
                                                    .background {
                                                        Circle()
                                                            .fill(.ultraThinMaterial)
                                                            .overlay {
                                                                Circle()
                                                                    .stroke(
                                                                        LinearGradient(
                                                                            colors: AppColors.cashbackGradient,
                                                                            startPoint: .leading,
                                                                            endPoint: .trailing
                                                                        ),
                                                                        lineWidth: 2
                                                                    )
                                                            }
                                                    }
                                            }
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            // Считаем только существующие карты
                                            let validCardCount = selectedCardIDs.filter { viewModel.getCard(byID: $0) != nil }.count
                                            Text(validCardCount == 1 ? "1 карта" : "\(validCardCount) карт")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(AppColors.textPrimary)
                                            
                                            Text("Нажмите для изменения")
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundStyle(AppColors.textSecondary)
                                        }
                                        
                                        Spacer()
                                    } else {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 24, weight: .semibold))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: AppColors.cashbackGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                        
                                        Text("Выбрать карты")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(AppColors.textPrimary)
                                        
                                        Spacer()
                                    }
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                                .padding(16)
                                .background {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(
                                                    LinearGradient(
                                                        colors: AppColors.cashbackGradient,
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    ),
                                                    lineWidth: 1.5
                                                )
                                        }
                                }
                            }
                            .buttonStyle(.plain)
                        }
        }
    }
    
    // MARK: - Add To Card Mode Content
    
    var addToCardModeContent: some View {
        VStack(spacing: 24) {
            // Выбор карты
            VStack(alignment: .leading, spacing: 12) {
                Text("Выберите карту")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Button {
                    showCardPicker = true
                } label: {
                    HStack(spacing: 16) {
                        if let cardID = selectedCardID, let card = viewModel.getCard(byID: cardID) {
                            Image(systemName: card.cardType.icon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: AppColors.cashbackGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 48, height: 48)
                                .background {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                
                                Text(card.bank.displayName)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                            
                            Spacer()
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: AppColors.cashbackGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            
                            Text("Выбрать карту")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            
                            Spacer()
                        }
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(16)
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(
                                            colors: AppColors.cashbackGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                    }
                }
                .buttonStyle(.plain)
            }
            
            // Кэшбеки для карты (если карта выбрана)
            if selectedCardID != nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Кэшбеки для карты")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    VStack(spacing: 12) {
                        ForEach(CashbackCategory.allCases, id: \.self) { category in
                            HStack(spacing: 12) {
                                // Иконка категории
                                Image(systemName: category.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.cashbackGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: 40, height: 40)
                                    .background {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                    }
                                
                                // Название категории
                                Text(category.displayName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                // Поле ввода процента
                                HStack(spacing: 4) {
                                    TextField("0", text: Binding(
                                        get: { cardCashbacks[category] ?? "" },
                                        set: { cardCashbacks[category] = $0 }
                                    ))
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.trailing)
                                    
                                    Text("%")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.ultraThinMaterial)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Validation
    
    var isValid: Bool {
        if creationMode == .createCashback || isEditing {
            guard let percentage = Double(percentageText.replacingOccurrences(of: ",", with: ".")),
                  percentage >= 0 && percentage <= 100 else {
                return false
            }
            return !selectedCardIDs.isEmpty
        } else {
            // Режим "Добавить к карте"
            guard selectedCardID != nil else { return false }
            // Проверяем, что хотя бы один кэшбек с процентом > 0
            return cardCashbacks.values.contains { text in
                if let percentage = Double(text.replacingOccurrences(of: ",", with: ".")) {
                    return percentage > 0 && percentage <= 100
                }
                return false
            }
        }
    }
    
    // MARK: - Save
    
    func saveCashback() {
        if creationMode == .createCashback || isEditing {
            guard let percentage = Double(percentageText.replacingOccurrences(of: ",", with: ".")),
                  percentage >= 0 && percentage <= 100 else {
                return
            }
            
            viewModel.handle(.updateCashback(
                category: selectedCategory,
                percentage: percentage,
                cardIDs: Array(selectedCardIDs)
            ))
        } else {
            // Режим "Добавить к карте"
            guard let cardID = selectedCardID else { return }
            
            // Собираем валидные кэшбеки
            let validCashbacks = cardCashbacks.compactMap { (category, text) -> (CashbackCategory, Double)? in
                guard let percentage = Double(text.replacingOccurrences(of: ",", with: ".")),
                      percentage > 0 && percentage <= 100 else {
                    return nil
                }
                return (category, percentage)
            }
            
            guard !validCashbacks.isEmpty else { return }
            
            viewModel.handle(.updateCashbacksForCard(
                cardID: cardID,
                cashbacks: validCashbacks
            ))
        }
        
        dismiss()
    }
}

// MARK: - Cashback Card Picker View

private struct CashbackCardPickerView: View {
    @Binding var selectedCardIDs: Set<String>
    let availableCards: [Card]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                if availableCards.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "creditcard.trianglebadge.exclamationmark")
                            .font(.system(size: 64))
                            .foregroundStyle(AppColors.textTertiary)
                        
                        Text("Нет доступных карт")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Text("Добавьте карту в сервисе \"Карты\"")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Список карт с множественным выбором
                            ForEach(availableCards) { card in
                                let cardID = card.cardUniqueID // Используем стабильный uniqueID
                                let isSelected = selectedCardIDs.contains(cardID)
                                
                                Button {
                                    if isSelected {
                                        selectedCardIDs.remove(cardID)
                                    } else {
                                        selectedCardIDs.insert(cardID)
                                    }
                                } label: {
                                    HStack(spacing: 16) {
                                        // Чекбокс
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 24, weight: .semibold))
                                            .foregroundStyle(
                                                isSelected ?
                                                LinearGradient(
                                                    colors: AppColors.cashbackGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                ) :
                                                LinearGradient(
                                                    colors: [AppColors.textTertiary, AppColors.textTertiary],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                        
                                        // Иконка карты
                                        Image(systemName: card.cardType.icon)
                                            .font(.system(size: 28, weight: .semibold))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: AppColors.cashbackGradient,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 48, height: 48)
                                            .background {
                                                Circle()
                                                    .fill(.ultraThinMaterial)
                                            }
                                        
                                        // Информация о карте
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(card.name)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundStyle(AppColors.textPrimary)
                                                
                                                if card.isFavorite {
                                                    Image(systemName: "star.fill")
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(
                                                            LinearGradient(
                                                                colors: AppColors.cashbackGradient,
                                                                startPoint: .leading,
                                                                endPoint: .trailing
                                                            )
                                                        )
                                                }
                                            }
                                            
                                            Text(card.bank.displayName)
                                                .font(.system(size: 14, weight: .regular))
                                                .foregroundStyle(AppColors.textSecondary)
                                            
                                            Text(card.maskedNumber)
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundStyle(AppColors.textTertiary)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(16)
                                    .background {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(.ultraThinMaterial)
                                            .overlay {
                                                if isSelected {
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .stroke(
                                                            LinearGradient(
                                                                colors: AppColors.cashbackGradient,
                                                                startPoint: .leading,
                                                                endPoint: .trailing
                                                            ),
                                                            lineWidth: 1.5
                                                        )
                                                }
                                            }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Выбор карт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cashbackGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
        }
    }
}

// MARK: - Cashback Single Card Picker View

private struct CashbackSingleCardPickerView: View {
    @Binding var selectedCardID: String
    let availableCards: [Card]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                if availableCards.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "creditcard.trianglebadge.exclamationmark")
                            .font(.system(size: 64))
                            .foregroundStyle(AppColors.textTertiary)
                        
                        Text("Нет доступных карт")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Text("Добавьте карту в сервисе \"Карты\"")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(availableCards) { card in
                                let cardID = card.cardUniqueID
                                let isSelected = selectedCardID == cardID
                                
                                Button {
                                    selectedCardID = cardID
                                    dismiss()
                                } label: {
                                    HStack(spacing: 16) {
                                        // Чекбокс
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 24, weight: .semibold))
                                            .foregroundStyle(
                                                isSelected ?
                                                LinearGradient(
                                                    colors: AppColors.cashbackGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                ) :
                                                LinearGradient(
                                                    colors: [AppColors.textTertiary, AppColors.textTertiary],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                        
                                        // Иконка карты
                                        Image(systemName: card.cardType.icon)
                                            .font(.system(size: 28, weight: .semibold))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: AppColors.cashbackGradient,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 48, height: 48)
                                            .background {
                                                Circle()
                                                    .fill(.ultraThinMaterial)
                                            }
                                        
                                        // Информация о карте
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(card.name)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundStyle(AppColors.textPrimary)
                                                
                                                if card.isFavorite {
                                                    Image(systemName: "star.fill")
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(
                                                            LinearGradient(
                                                                colors: AppColors.cashbackGradient,
                                                                startPoint: .leading,
                                                                endPoint: .trailing
                                                            )
                                                        )
                                                }
                                            }
                                            
                                            Text(card.bank.displayName)
                                                .font(.system(size: 14, weight: .regular))
                                                .foregroundStyle(AppColors.textSecondary)
                                            
                                            Text(card.maskedNumber)
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundStyle(AppColors.textTertiary)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(16)
                                    .background {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(.ultraThinMaterial)
                                            .overlay {
                                                if isSelected {
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .stroke(
                                                            LinearGradient(
                                                                colors: AppColors.cashbackGradient,
                                                                startPoint: .leading,
                                                                endPoint: .trailing
                                                            ),
                                                            lineWidth: 1.5
                                                        )
                                                }
                                            }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Выбор карты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cashbackGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CashbackView()
    }
}
