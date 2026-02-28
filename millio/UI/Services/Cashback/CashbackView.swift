//
//  CashbackView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData
import PhotosUI

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
    @State private var showMonthPickerSheet: Bool = false
    @State private var showFavoriteCategoriesSheet: Bool = false
    @State private var activeSwipeCashbackID: PersistentIdentifier?

    var body: some View {
        ZStack {
            GradientBackground()

            if viewModel.state.visibleCashbacks.isEmpty {
                emptyStateView
                    .padding(.horizontal, 16)
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        cashbacksList
                    }
                    .padding(.bottom, 100)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }

            addCashbackFAB
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showMonthPickerSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.selectedMonthTitle)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Выбрать месяц кешбэка")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showFavoriteCategoriesSheet = true
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Избранные категории")
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCashbackEditor },
            set: { if !$0 { viewModel.handle(.hideCashbackEditor) } }
        )) {
            CashbackEditorView(viewModel: viewModel)
        }
        .sheet(isPresented: $showMonthPickerSheet) {
            CashbackMonthPickerSheet(
                selectedMonth: viewModel.state.selectedMonth,
                maxMonth: viewModel.maxSelectableMonth
            ) { newMonth in
                viewModel.handle(.setSelectedMonth(newMonth))
            }
        }
        .sheet(isPresented: $showFavoriteCategoriesSheet) {
            CashbackFavoriteCategoriesSheet(viewModel: viewModel)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 20) {
                Image(ServiceItem.cashbackIconAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)

                Text("Нет кешбэка в этом месяце")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Добавьте категории кешбэка - начните с быстрой настройки")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)

                Button {
                    viewModel.handle(.addCashback)
                } label: {
                    Text("Добавить кешбэк")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(cashbackFabFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(cashbackAccent.opacity(0.45), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 72)
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
        let listShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return VStack(spacing: 0) {
            ForEach(Array(viewModel.state.visibleCashbacks.enumerated()), id: \.element.id) { index, cashback in
                CashbackRowView(
                    cashback: cashback,
                    cashbackID: cashback.id,
                    activeSwipeCashbackID: $activeSwipeCashbackID,
                    viewModel: viewModel
                )
                if index < viewModel.state.visibleCashbacks.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.leading, 74)
                }
            }
        }
        .clipShape(listShape)
        .background {
            listShape
                .fill(darkCardFill)
                .overlay(
                    listShape
                        .stroke(cashbackAccent.opacity(0.35), lineWidth: 1)
                )
        }
    }
}

private struct CashbackMonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let maxMonth: Date
    let onApply: (Date) -> Void
    @State private var draftMonth: Date

    init(selectedMonth: Date, maxMonth: Date, onApply: @escaping (Date) -> Void) {
        self.maxMonth = maxMonth
        self.onApply = onApply
        _draftMonth = State(initialValue: selectedMonth)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                Form {
                    Section {
                        DatePicker(
                            "Месяц",
                            selection: $draftMonth,
                            in: ...maxMonth,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                        .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Выберите месяц")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Период кешбэка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Применить") {
                        onApply(draftMonth)
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

private struct CashbackFavoriteCategoriesSheet: View {
    @ObservedObject var viewModel: CashbackViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var categoryOptions: [CashbackCategoryOption] {
        let options = viewModel.categoryOptions(matching: searchText)
        return options.sorted { lhs, rhs in
            let lhsFavorite = viewModel.isFavoriteCategory(rawValue: lhs.rawValue)
            let rhsFavorite = viewModel.isFavoriteCategory(rawValue: rhs.rawValue)
            if lhsFavorite != rhsFavorite { return lhsFavorite && !rhsFavorite }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppColors.textSecondary)
                        TextField("Поиск категории", text: $searchText)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(darkCircleFill)
                    }
                    .padding(.horizontal, 16)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(categoryOptions.enumerated()), id: \.element.rawValue) { index, category in
                                let isFavorite = viewModel.isFavoriteCategory(rawValue: category.rawValue)
                                Button {
                                    viewModel.handle(.toggleFavoriteCategory(rawValue: category.rawValue))
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: category.icon)
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .frame(width: 28, height: 28)

                                        Text(category.displayName)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Image(systemName: isFavorite ? "star.fill" : "star")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(
                                                isFavorite
                                                    ? AnyShapeStyle(
                                                        LinearGradient(
                                                            colors: [Color.orange, Color.yellow],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                                    : AnyShapeStyle(AppColors.textTertiary)
                                            )
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(.plain)

                                if index < categoryOptions.count - 1 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.08))
                                        .frame(height: 1)
                                        .padding(.leading, 56)
                                }
                            }
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(darkCardFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(cashbackAccent.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .padding(.top, 12)
            }
            .navigationTitle("Избранные категории")
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

// MARK: - Cashback Row View

private struct CashbackRowView: View {
    let cashback: Cashback
    let cashbackID: PersistentIdentifier
    @Binding var activeSwipeCashbackID: PersistentIdentifier?
    @ObservedObject var viewModel: CashbackViewModel
    @State private var rowOffset: CGFloat = 0
    @State private var dragOriginOffset: CGFloat?

    private let actionButtonSize: CGFloat = 44
    private let deleteRevealWidth: CGFloat = 64
    private var leadingActionsWidth: CGFloat { (actionButtonSize * 2) + 10 }
    private var isFavoriteCategory: Bool {
        viewModel.isFavoriteCategory(rawValue: cashback.categoryRaw)
    }

    var body: some View {
        let categoryOption = viewModel.categoryOption(
            for: cashback.categoryRaw,
            fallbackName: cashback.name
        )
        let isFavorite = isFavoriteCategory
        let isPinned = viewModel.isPinnedCategory(rawValue: cashback.categoryRaw)

        ZStack(alignment: .trailing) {
            HStack {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            rowOffset = 0
                        }
                        activeSwipeCashbackID = nil
                        viewModel.handle(.togglePinnedCategory(rawValue: cashback.categoryRaw))
                    } label: {
                        Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: actionButtonSize, height: actionButtonSize)
                            .background(
                                Circle()
                                    .fill(Color.orange.opacity(0.95))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isPinned ? "Открепить категорию" : "Закрепить категорию")
                    .disabled(isFavorite)
                    .opacity(isFavorite ? 0.45 : 1)

                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            rowOffset = 0
                        }
                        activeSwipeCashbackID = nil
                        viewModel.handle(.editCashback(cashback))
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: actionButtonSize, height: actionButtonSize)
                            .background(
                                Circle()
                                    .fill(cashbackAccent.opacity(0.95))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Редактировать кешбэк")
                }
                .padding(.leading, 12)
                .opacity(rowOffset > 8 ? 1 : 0)

                Spacer()
            }

            HStack(spacing: 14) {
                Image(systemName: categoryOption.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cashbackGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(darkCircleFill)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(cashback.displayCategoryName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                        if isFavorite {
                            Text("TOP")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.orange)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.2))
                                )
                        } else if isPinned {
                            Text("PIN")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(AppColors.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.14))
                                )
                        }
                    }

                    Text(cardSubtitle)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(cashback.formattedPercentage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .offset(x: rowOffset)
            .gesture(deleteSwipeGesture)
            .onTapGesture {
                if rowOffset != 0 {
                    withAnimation(.easeOut(duration: 0.16)) {
                        rowOffset = 0
                    }
                    activeSwipeCashbackID = nil
                }
            }
            .animation(.easeOut(duration: 0.16), value: rowOffset)
            .clipped()
            .onChange(of: activeSwipeCashbackID) { _, newValue in
                if newValue != cashbackID && rowOffset != 0 {
                    withAnimation(.easeOut(duration: 0.16)) {
                        rowOffset = 0
                    }
                }
            }

            HStack {
                Spacer()
                Button(role: .destructive) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        rowOffset = 0
                    }
                    activeSwipeCashbackID = nil
                    viewModel.handle(.deleteCashback(cashback))
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: actionButtonSize, height: actionButtonSize)
                    .background(
                        Circle()
                            .fill(AppColors.error.opacity(0.95))
                    )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .opacity(-rowOffset > 8 ? 1 : 0)
            }
        }
    }

    private var deleteSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if activeSwipeCashbackID != cashbackID {
                    activeSwipeCashbackID = cashbackID
                }
                if dragOriginOffset == nil {
                    dragOriginOffset = rowOffset
                }
                let origin = dragOriginOffset ?? rowOffset
                let proposed = origin + value.translation.width
                let maxRight = leadingActionsWidth
                rowOffset = min(maxRight, max(-deleteRevealWidth, proposed))
            }
            .onEnded { value in
                defer { dragOriginOffset = nil }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                let shouldRevealLeft = value.predictedEndTranslation.width < -45 || rowOffset < -36
                let shouldRevealRight = value.predictedEndTranslation.width > 55 || rowOffset > 42
                withAnimation(.easeOut(duration: 0.16)) {
                    if shouldRevealLeft {
                        rowOffset = -deleteRevealWidth
                        activeSwipeCashbackID = cashbackID
                    } else if shouldRevealRight {
                        rowOffset = leadingActionsWidth
                        activeSwipeCashbackID = cashbackID
                    } else {
                        rowOffset = 0
                        if activeSwipeCashbackID == cashbackID {
                            activeSwipeCashbackID = nil
                        }
                    }
                }
            }
    }

    private var cardSubtitle: String {
        let names = viewModel
            .getCardsForCashback(cashback)
            .map(\.name)
        guard !names.isEmpty else { return "Без привязанной карты" }
        let preview = Array(names.prefix(2))
        if names.count <= 2 {
            return preview.joined(separator: ", ")
        }
        return "\(preview.joined(separator: ", ")) +\(names.count - 2)"
    }
}

// MARK: - Cashback Editor View

private enum CashbackCategoryEditorMode {
    case create
    case edit(rawValue: String)
}

private struct CashbackEditorView: View {
    @ObservedObject var viewModel: CashbackViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showCardPicker: Bool = false
    @State private var showCategoryEditorSheet: Bool = false
    @State private var showDeleteCategoryAlert: Bool = false
    @State private var categoryEditorMode: CashbackCategoryEditorMode = .create
    @State private var categoryEditorName: String = ""
    @State private var categoryEditorIcon: String = CashbackCustomCategory.defaultIcon
    @State private var pendingCategoryRawAction: String?
    @State private var selectedCardID: String? = nil
    @State private var searchText: String = ""
    @State private var isShowingAllCategories: Bool = false
    @State private var selectedCategoryRaws: Set<String> = []
    @State private var cardCashbacks: [String: String] = [:]
    @State private var screenshotPhotoItem: PhotosPickerItem?
    @State private var isImportingFromScreenshot: Bool = false
    @State private var importAlertMessage: String?
    private let screenshotParser = CashbackScreenshotParser()

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

    private var isShowingImportAlert: Binding<Bool> {
        Binding(
            get: { importAlertMessage != nil },
            set: { isPresented in
                if !isPresented {
                    importAlertMessage = nil
                }
            }
        )
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
            .navigationTitle(viewModel.state.editingCashback == nil ? "Новый кешбэк" : "Редактировать кешбэк")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
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
            .sheet(isPresented: $showCategoryEditorSheet) {
                CashbackCategoryEditorSheet(
                    mode: categoryEditorMode,
                    name: categoryEditorName,
                    selectedIcon: categoryEditorIcon
                ) { name, icon in
                    handleCategoryEditorSave(name: name, icon: icon)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
            .onChange(of: screenshotPhotoItem) { _, newValue in
                guard let item = newValue else { return }
                Task {
                    await importFromScreenshot(item: item)
                }
            }
            .alert("Импорт из скриншота", isPresented: isShowingImportAlert) {
                Button("OK", role: .cancel) {
                    importAlertMessage = nil
                }
            } message: {
                Text(importAlertMessage ?? "")
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
            HStack {
                PhotosPicker(
                    selection: $screenshotPhotoItem,
                    matching: .images
                ) {
                    HStack(spacing: 8) {
                        if isImportingFromScreenshot {
                            ProgressView()
                                .tint(AppColors.textPrimary)
                        } else {
                            Image(systemName: "photo.badge.magnifyingglass")
                                .font(.system(size: 16, weight: .regular))
                        }
                        Text(isImportingFromScreenshot ? "Распознаю скриншот..." : "Импорт со скриншота")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(darkCircleFill)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isImportingFromScreenshot)
                Spacer()
            }

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
                                    Button("Редактировать") {
                                        openEditCategorySheet(for: category)
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
                            openCreateCategorySheet()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .regular))
                                    .frame(width: 24, height: 24)
                                    .background {
                                        Circle()
                                            .stroke(cashbackAccent, lineWidth: 1)
                                    }

                                Text("Создать категорию")
                                    .font(.system(size: 15, weight: .regular))
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
                                    .font(.system(size: 15, weight: .regular))
                                Image(systemName: isShowingAllCategories ? "chevron.up" : "chevron.right")
                                    .font(.system(size: 15, weight: .regular))
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
                                Image(systemName: category.icon)
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
                                    Button("Редактировать") {
                                        openEditCategorySheet(for: category)
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

    @MainActor
    private func importFromScreenshot(item: PhotosPickerItem) async {
        isImportingFromScreenshot = true
        defer {
            isImportingFromScreenshot = false
            screenshotPhotoItem = nil
        }

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            importAlertMessage = "Не удалось прочитать изображение. Попробуйте выбрать другой скриншот."
            return
        }

        do {
            let parsed = try await screenshotParser.parse(from: data)
            applyImportedItems(parsed)
            importAlertMessage = "Распознано категорий: \(parsed.count). Проверь и нажми «Сохранить»."
        } catch let error as CashbackScreenshotImportError {
            importAlertMessage = error.errorDescription
        } catch {
            importAlertMessage = "Не удалось распознать скриншот. Попробуйте более чёткое изображение."
        }
    }

    @MainActor
    private func applyImportedItems(_ items: [CashbackScreenshotImportItem]) {
        var importedCategoryRaws: Set<String> = []
        var importedPercentages: [String: String] = [:]

        for item in items {
            let option = viewModel.categoryOptionForImportedName(item.categoryName)
            importedCategoryRaws.insert(option.rawValue)

            let newPercentage = item.percentage
            if let existingText = importedPercentages[option.rawValue],
               let existingValue = Double(existingText.replacingOccurrences(of: ",", with: ".")) {
                importedPercentages[option.rawValue] = percentageText(for: max(existingValue, newPercentage))
            } else {
                importedPercentages[option.rawValue] = percentageText(for: newPercentage)
            }
        }

        guard !importedCategoryRaws.isEmpty else { return }
        selectedCategoryRaws = importedCategoryRaws
        cardCashbacks = importedPercentages
    }

    private func openCreateCategorySheet() {
        categoryEditorMode = .create
        categoryEditorName = ""
        categoryEditorIcon = CashbackCustomCategory.defaultIcon
        showCategoryEditorSheet = true
    }

    private func openEditCategorySheet(for category: CashbackCategoryOption) {
        guard category.isCustom else { return }
        categoryEditorMode = .edit(rawValue: category.rawValue)
        categoryEditorName = category.displayName
        categoryEditorIcon = category.icon
        showCategoryEditorSheet = true
    }

    private func handleCategoryEditorSave(name: String, icon: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        switch categoryEditorMode {
        case .create:
            if let option = viewModel.createCustomCategory(trimmedName, icon: icon) {
                selectedCategoryRaws.insert(option.rawValue)
                if cardCashbacks[option.rawValue] == nil {
                    cardCashbacks[option.rawValue] = "5"
                }
            }

        case .edit(let oldRaw):
            let wasSelected = selectedCategoryRaws.contains(oldRaw)
            let previousPercentage = cardCashbacks[oldRaw]
            guard viewModel.renameCustomCategory(rawValue: oldRaw, newName: trimmedName, newIcon: icon) else {
                return
            }

            guard wasSelected else { break }

            selectedCategoryRaws.remove(oldRaw)
            cardCashbacks.removeValue(forKey: oldRaw)

            let updatedOption = viewModel.categoryOptions().first { $0.rawValue == oldRaw }
                ?? viewModel.categoryOptions().first {
                    $0.displayName.caseInsensitiveCompare(trimmedName) == .orderedSame
                }

            if let updatedOption {
                selectedCategoryRaws.insert(updatedOption.rawValue)
                if cardCashbacks[updatedOption.rawValue] == nil {
                    cardCashbacks[updatedOption.rawValue] = previousPercentage ?? "5"
                }
            }
        }

        showCategoryEditorSheet = false
    }

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

private struct CashbackCategoryEditorSheet: View {
    let mode: CashbackCategoryEditorMode
    @State var name: String
    @State var selectedIcon: String
    let onSave: (_ name: String, _ icon: String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var title: String {
        switch mode {
        case .create:
            return "Новая категория"
        case .edit:
            return "Редактировать категорию"
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        FinancesSectionHeader(title: "Название")
                        FinancesGlassCard(accentColor: cashbackAccent) {
                            TextField("Например: Кофейни", text: $name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                                .padding(16)
                        }

                        FinancesSectionHeader(title: "Иконка")
                        FinancesGlassCard(accentColor: cashbackAccent) {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10) {
                                ForEach(CashbackCustomCategory.allowedIcons, id: \.self) { icon in
                                    let isSelected = selectedIcon == icon
                                    Button {
                                        selectedIcon = icon
                                    } label: {
                                        Image(systemName: icon)
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .frame(width: 54, height: 54)
                                            .background {
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(isSelected ? Color.white.opacity(0.22) : darkCircleFill)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                            .stroke(cashbackAccent.opacity(isSelected ? 0.75 : 0.15), lineWidth: 1)
                                                    )
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(title)
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
                        onSave(name, selectedIcon)
                        dismiss()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cashbackGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
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

                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(card.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(AppColors.textPrimary)

                                            HStack(spacing: 8) {
                                                Text(card.bank.displayName)
                                                    .font(.system(size: 14, weight: .regular))
                                                    .foregroundStyle(AppColors.textSecondary)

                                                if card.isFavorite {
                                                    Label("Избранная", systemImage: "star.fill")
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundStyle(AppColors.textPrimary)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 3)
                                                        .background(
                                                            Capsule()
                                                                .fill(Color.white.opacity(0.12))
                                                        )
                                                }
                                            }

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
