//
//  CashbackView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData

// MARK: - Хелпер для тёмного фона (стиль финансов)

private let cashbackAccent: Color = AppColors.cashbackGradient.first ?? .purple

private let darkCardFill = LinearGradient(
    colors: [
        Color(red: 0.03, green: 0.07, blue: 0.11),
        Color.black
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private let cashbackGlow = LinearGradient(
    colors: [
        cashbackAccent.opacity(0.18),
        Color.clear
    ],
    startPoint: .leading,
    endPoint: .trailing
)

private let darkCircleFill = Color.white.opacity(0.08)
private let cashbackFabFill = LinearGradient(
    colors: [
        Color(red: 0.03, green: 0.07, blue: 0.11),
        Color(red: 0.02, green: 0.04, blue: 0.06),
        Color.black
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

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

            if viewModel.state.visibleCashbacks.isEmpty {
                emptyStateView
                    .padding(.horizontal, 16)
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        monthSelector
                        cashbacksList
                    }
                    .padding(.bottom, 100)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }

            addCashbackFAB
        }
        .navigationTitle("Кешбэк")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCashbackEditor },
            set: { if !$0 { viewModel.handle(.hideCashbackEditor) } }
        )) {
            CashbackEditorView(viewModel: viewModel)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            monthSelector

            VStack(spacing: 20) {
                Image(systemName: "percent")
                    .font(.system(size: 76, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cashbackGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Нет кешбэка в этом месяце")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Добавьте категории кешбэка - начните с быстрой настройки")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 120)
    }

    private var monthSelector: some View {
        HStack(spacing: 14) {
            Button {
                viewModel.handle(.moveMonthBackward)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle().fill(darkCircleFill)
                    }
            }
            .buttonStyle(.plain)

            Text(viewModel.selectedMonthTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(minWidth: 140)

            Button {
                viewModel.handle(.moveMonthForward)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle().fill(darkCircleFill)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canMoveMonthForward())
            .opacity(viewModel.canMoveMonthForward() ? 1 : 0.45)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var addCashbackFAB: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    viewModel.handle(.addCashback)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(
                            Circle()
                                .fill(cashbackFabFill)
                                .overlay(
                                    Circle()
                                        .fill(cashbackGlow)
                                        .opacity(0.6)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(cashbackAccent.opacity(0.55), lineWidth: 1)
                                )
                        )
                }
                .padding(.trailing, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Cashbacks List

    private var cashbacksList: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.state.visibleCashbacks) { cashback in
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
            Button {
                viewModel.handle(.editCashback(cashback))
            } label: {
                HStack(spacing: 16) {
                    // Иконка категории
                    Image(systemName: cashback.displayCategoryIcon)
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
                                .fill(darkCircleFill)
                        }

                    // Информация
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cashback.displayCategoryName)
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
                                        .fill(darkCircleFill)
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
                                        .fill(darkCircleFill)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(darkCardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(cashbackGlow)
                                .opacity(0.6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(cashbackAccent.opacity(0.55), lineWidth: 1)
                        )
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
                                    .fill(darkCircleFill)
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
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(darkCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(cashbackAccent.opacity(0.25), lineWidth: 1)
                )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

// MARK: - Cashback Editor View

private struct CashbackEditorView: View {
    @ObservedObject var viewModel: CashbackViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showCardPicker: Bool = false
    @State private var showCreateCategoryAlert: Bool = false
    @State private var showRenameCategoryAlert: Bool = false
    @State private var showDeleteCategoryAlert: Bool = false
    @State private var newCategoryName: String = ""
    @State private var renameCategoryName: String = ""
    @State private var pendingCategoryRawAction: String?
    @State private var selectedCardID: String? = nil
    @State private var searchText: String = ""
    @State private var isShowingAllCategories: Bool = false
    @State private var selectedCategoryRaws: Set<String> = []
    @State private var cardCashbacks: [String: String] = [:]

    private var filteredCategories: [CashbackCategoryOption] {
        viewModel.categoryOptions(matching: searchText)
    }

    private var visibleCategories: [CashbackCategoryOption] {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isShowingAllCategories {
            return filteredCategories
        }
        return Array(filteredCategories.prefix(6))
    }

    private var canShowMoreCategories: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filteredCategories.count > 6
    }

    private var selectedCategoriesList: [CashbackCategoryOption] {
        selectedCategoryRaws
            .map { viewModel.categoryOption(for: $0) }
            .sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        cardPickerSection
                        categoriesSection
                        selectedCategoriesSection
                        saveButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Новый кешбэк")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background {
                                Circle()
                                    .fill(darkCircleFill)
                            }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
            .sheet(isPresented: $showCardPicker) {
                CashbackSingleCardPickerView(
                    selectedCardID: Binding(
                        get: { selectedCardID ?? "" },
                        set: { selectedCardID = $0.isEmpty ? nil : $0 }
                    ),
                    availableCards: viewModel.state.availableCards
                )
            }
            .onAppear {
                if let editing = viewModel.state.editingCashback {
                    selectedCardID = editing.cardIDs.first { cardID in
                        viewModel.getCard(byID: cardID) != nil
                    }
                }

                if let cardID = selectedCardID {
                    preloadCategories(for: cardID)
                }
            }
            .onChange(of: selectedCardID) { _, newValue in
                guard let cardID = newValue else {
                    selectedCategoryRaws.removeAll()
                    cardCashbacks.removeAll()
                    return
                }
                preloadCategories(for: cardID)
            }
        }
    }

    // MARK: - Sections

    private var cardPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Выберите карту")

            Button {
                showCardPicker = true
            } label: {
                FinancesGlassCard(accentColor: cashbackAccent) {
                    HStack(spacing: 16) {
                        if let cardID = selectedCardID, let card = viewModel.getCard(byID: cardID) {
                            Image(systemName: card.cardType.icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: AppColors.cashbackGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 44, height: 44)
                                .background {
                                    Circle()
                                        .fill(darkCircleFill)
                                }

                            Text(card.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)

                            Spacer()
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.85))
                                .frame(width: 44, height: 44)
                                .background {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: AppColors.cashbackGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                }

                            Text("Выбрать карту")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)

                            Spacer()
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(16)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Выбор категорий")

            FinancesGlassCard(accentColor: cashbackAccent) {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(AppColors.textPrimary)

                        TextField("Поиск категорий", text: $searchText)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(.top, 4)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(visibleCategories, id: \.self) { category in
                            let isSelected = selectedCategoryRaws.contains(category.rawValue)
                            Button {
                                if isSelected {
                                    selectedCategoryRaws.remove(category.rawValue)
                                    cardCashbacks.removeValue(forKey: category.rawValue)
                                } else {
                                    selectedCategoryRaws.insert(category.rawValue)
                                    if cardCashbacks[category.rawValue] == nil {
                                        cardCashbacks[category.rawValue] = "5"
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(category.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(AppColors.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    Capsule()
                                        .fill(isSelected ? Color.white.opacity(0.30) : darkCircleFill)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if category.isCustom {
                                    Button("Переименовать") {
                                        pendingCategoryRawAction = category.rawValue
                                        renameCategoryName = category.displayName
                                        showRenameCategoryAlert = true
                                    }

                                    Button("Удалить", role: .destructive) {
                                        pendingCategoryRawAction = category.rawValue
                                        showDeleteCategoryAlert = true
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        Button {
                            showCreateCategoryAlert = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 32, height: 32)
                                    .background {
                                        Circle()
                                            .stroke(cashbackAccent, lineWidth: 1.5)
                                    }

                                Text("Создать категорию")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.cashbackGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button {
                            isShowingAllCategories.toggle()
                        } label: {
                            HStack(spacing: 8) {
                                Text(isShowingAllCategories ? "Свернуть" : "Показать ещё")
                                    .font(.system(size: 16, weight: .medium))
                                Image(systemName: isShowingAllCategories ? "chevron.up" : "chevron.right")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.cashbackGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .opacity(canShowMoreCategories || isShowingAllCategories ? 1 : 0.5)
                        .disabled(!canShowMoreCategories && !isShowingAllCategories)
                    }
                }
                .padding(16)
            }
            .alert("Создание категории", isPresented: $showCreateCategoryAlert) {
                TextField("Название категории", text: $newCategoryName)
                Button("Отмена", role: .cancel) {
                    newCategoryName = ""
                }
                Button("Создать") {
                    if let option = viewModel.createCustomCategory(newCategoryName) {
                        selectedCategoryRaws.insert(option.rawValue)
                        if cardCashbacks[option.rawValue] == nil {
                            cardCashbacks[option.rawValue] = "5"
                        }
                    }
                    newCategoryName = ""
                }
            } message: {
                Text("Введите название новой категории")
            }
            .alert("Переименовать категорию", isPresented: $showRenameCategoryAlert) {
                TextField("Новое название", text: $renameCategoryName)
                Button("Отмена", role: .cancel) {
                    renameCategoryName = ""
                    pendingCategoryRawAction = nil
                }
                Button("Сохранить") {
                    guard let raw = pendingCategoryRawAction else { return }
                    let oldRaw = raw
                    if viewModel.renameCustomCategory(rawValue: oldRaw, newName: renameCategoryName) {
                        if selectedCategoryRaws.contains(oldRaw) {
                            let newOption = viewModel.categoryOptions().first(where: {
                                $0.displayName.caseInsensitiveCompare(renameCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                            })
                            selectedCategoryRaws.remove(oldRaw)
                            if let newOption {
                                selectedCategoryRaws.insert(newOption.rawValue)
                                cardCashbacks[newOption.rawValue] = cardCashbacks[oldRaw] ?? "5"
                            }
                            cardCashbacks.removeValue(forKey: oldRaw)
                        }
                    }
                    renameCategoryName = ""
                    pendingCategoryRawAction = nil
                }
            } message: {
                Text("Введите новое название категории. Связанные кешбэки будут обновлены автоматически.")
            }
            .alert("Удалить категорию?", isPresented: $showDeleteCategoryAlert) {
                Button("Отмена", role: .cancel) {
                    pendingCategoryRawAction = nil
                }
                Button("Удалить", role: .destructive) {
                    guard let raw = pendingCategoryRawAction else { return }
                    if viewModel.deleteCustomCategory(rawValue: raw) {
                        selectedCategoryRaws.remove(raw)
                        cardCashbacks.removeValue(forKey: raw)
                    }
                    pendingCategoryRawAction = nil
                }
            } message: {
                Text("Все связанные кешбэки этой категории будут безопасно перенесены в категорию \"Другое\".")
            }
        }
    }

    private var selectedCategoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                FinancesSectionHeader(title: "Выбранные категории")
                Spacer()
                HStack(spacing: 8) {
                    quickFillButton(5)
                    quickFillButton(10)
                    quickFillButton(15)
                }
            }

            FinancesGlassCard(accentColor: cashbackAccent) {
                if selectedCategoriesList.isEmpty {
                    Text("Выберите хотя бы одну категорию")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(selectedCategoriesList.enumerated()), id: \.element) { index, category in
                            HStack(spacing: 12) {
                                Image(systemName: "flag")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .frame(width: 24, height: 24)

                                Text(category.displayName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                HStack(spacing: 14) {
                                    Button {
                                        adjustPercentage(for: category.rawValue, delta: -1)
                                    } label: {
                                        Text("-")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(AppColors.textPrimary)
                                    }

                                    Rectangle()
                                        .fill(Color.white.opacity(0.35))
                                        .frame(width: 1, height: 18)

                                    Button {
                                        adjustPercentage(for: category.rawValue, delta: 1)
                                    } label: {
                                        Text("+")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(AppColors.textPrimary)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background {
                                    Capsule()
                                        .fill(darkCircleFill)
                                }

                                Text("\(formattedPercentage(for: category.rawValue)) %")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: AppColors.cashbackGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contextMenu {
                                if category.isCustom {
                                    Button("Переименовать") {
                                        pendingCategoryRawAction = category.rawValue
                                        renameCategoryName = category.displayName
                                        showRenameCategoryAlert = true
                                    }

                                    Button("Удалить", role: .destructive) {
                                        pendingCategoryRawAction = category.rawValue
                                        showDeleteCategoryAlert = true
                                    }
                                }
                            }

                            if index < selectedCategoriesList.count - 1 {
                                FinancesRowDivider()
                            }
                        }
                    }
                }
            }
        }
    }

    private func quickFillButton(_ value: Int) -> some View {
        Button {
            applyPercentageToAllSelected(Double(value))
        } label: {
            Text("\(value)%")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(darkCircleFill)
                }
        }
        .buttonStyle(.plain)
        .disabled(selectedCategoryRaws.isEmpty)
        .opacity(selectedCategoryRaws.isEmpty ? 0.45 : 1)
    }

    private var saveButton: some View {
        Button {
            saveCashback()
        } label: {
            Text("Сохранить")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(darkCardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(cashbackGlow)
                                .opacity(0.6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(cashbackAccent.opacity(0.55), lineWidth: 1)
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(!isValid)
        .opacity(isValid ? 1 : 0.5)
    }

    // MARK: - Validation
    var isValid: Bool {
        guard selectedCardID != nil else { return false }
        return selectedCategoryRaws.contains { raw in
            guard let percentage = percentageValue(for: raw) else { return false }
            return percentage > 0 && percentage <= 100
        }
    }

    // MARK: - Save

    func saveCashback() {
        guard let cardID = selectedCardID else { return }

        let validCashbacks = selectedCategoryRaws.compactMap { raw -> (categoryRaw: String, categoryName: String, percentage: Double)? in
            guard let percentage = percentageValue(for: raw),
                  percentage > 0 && percentage <= 100 else {
                return nil
            }
            let option = viewModel.categoryOption(for: raw)
            return (categoryRaw: raw, categoryName: option.displayName, percentage: percentage)
        }

        guard !validCashbacks.isEmpty else { return }

        viewModel.handle(.updateCashbacksForCard(
            cardID: cardID,
            cashbacks: validCashbacks
        ))

        dismiss()
    }

    // MARK: - Helpers

    private func preloadCategories(for cardID: String) {
        let selectedMonthKey = Cashback.monthKey(for: viewModel.state.selectedMonth)
        let existingForCard = viewModel.state.cashbacks.filter { cashback in
            cashback.cardIDs.contains(cardID) && cashback.monthKey == selectedMonthKey
        }

        selectedCategoryRaws = Set(existingForCard.map(\.categoryRaw))
        cardCashbacks = Dictionary(
            uniqueKeysWithValues: existingForCard.map { ($0.categoryRaw, percentageText(for: $0.percentage)) }
        )
    }

    private func percentageValue(for categoryRaw: String) -> Double? {
        guard let text = cardCashbacks[categoryRaw] else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func percentageText(for value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }

    private func formattedPercentage(for categoryRaw: String) -> String {
        guard let value = percentageValue(for: categoryRaw) else { return "0" }
        return percentageText(for: value)
    }

    private func adjustPercentage(for categoryRaw: String, delta: Double) {
        let current = percentageValue(for: categoryRaw) ?? 0
        let next = min(100, max(0, current + delta))
        cardCashbacks[categoryRaw] = percentageText(for: next)
    }

    private func applyPercentageToAllSelected(_ value: Double) {
        guard !selectedCategoryRaws.isEmpty else { return }
        let clamped = min(100, max(0, value))
        let text = percentageText(for: clamped)
        for raw in selectedCategoryRaws {
            cardCashbacks[raw] = text
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
                                                    .fill(darkCircleFill)
                                            }

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
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(darkCardFill)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .fill(cashbackGlow)
                                                    .opacity(isSelected ? 0.6 : 0)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .stroke(
                                                        cashbackAccent.opacity(isSelected ? 0.55 : 0.2),
                                                        lineWidth: 1
                                                    )
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
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
