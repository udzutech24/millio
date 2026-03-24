//
//  CashbackView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData
import PhotosUI

private struct CashbackCategoryIconView: View {
    let icon: String
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let tint: AnyShapeStyle

    var body: some View {
        if CashbackCustomCategory.isSFSymbolIcon(icon) {
            Image(systemName: icon)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(tint)
        } else {
            Text(icon)
                .font(.system(size: fontSize, weight: .regular))
                .foregroundStyle(tint)
        }
    }
}

private struct CashbackCategoryEditButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CashbackScreenStyle.accent)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Редактировать категорию"))
    }
}

private struct CashbackCardSelectionBadge: View {
    let title: String
    let tint: Color
    let fill: Color

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
    }
}

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
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var showCategorySettingsSheet: Bool = false
    @State private var showQuickNavigationPopover: Bool = false
    @State private var isSearchExpanded: Bool = false
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    private let currentRoute: AppRoute = .cashback

    private var localizationLocale: Locale {
        appState.selectedLanguage.locale ?? Locale.current
    }

    private var filteredCashbacks: [Cashback] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.state.visibleCashbacks }

        return viewModel.state.visibleCashbacks.filter { cashback in
            let categoryOption = viewModel.categoryOption(
                for: cashback.categoryRaw,
                fallbackName: cashback.name
            )
            let cardNames = viewModel.getCardsForCashback(cashback).map(\.name)

            if categoryOption.displayName.localizedCaseInsensitiveContains(query) {
                return true
            }

            if CashbackCategoryCatalog.matchesSearch(rawValue: cashback.categoryRaw, query: query) {
                return true
            }

            if cashback.name.localizedCaseInsensitiveContains(query) {
                return true
            }

            return cardNames.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        ZStack {
            GradientBackground()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissSearchKeyboard()
                }

            if viewModel.state.visibleCashbacks.isEmpty {
                emptyStateView
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    if isSearchExpanded {
                        searchPanel
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if filteredCashbacks.isEmpty {
                        searchEmptyStateView
                            .padding(.horizontal, 16)
                            .onTapGesture {
                                dismissSearchKeyboard()
                            }
                    } else {
                        cashbacksList
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    dismissSearchKeyboard()
                                }
                            )
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveBackSwipe()
        .toolbar { topToolbar }
        .animation(.easeInOut(duration: 0.18), value: isSearchExpanded)
        .safeAreaInset(edge: .bottom) {
            addCashbackFAB
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCashbackEditor },
            set: { if !$0 { viewModel.handle(.hideCashbackEditor) } }
        )) {
            CashbackEditorView(viewModel: viewModel)
        }
        .sheet(isPresented: $showCategorySettingsSheet) {
            CashbackCategorySettingsSheet(viewModel: viewModel)
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
                                    .fill(CashbackScreenStyle.fabFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(CashbackScreenStyle.accent.opacity(0.45), lineWidth: 1)
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
        HStack {
            Spacer()
            Button {
                viewModel.handle(.addCashback)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                .background(addCashbackFABBackground)
                .shadow(color: CashbackScreenStyle.accent.opacity(0.22), radius: 16, y: 10)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color.clear)
    }

    private var addCashbackFABBackground: some View {
        Circle()
            .fill(CashbackScreenStyle.fabFill)
            .overlay(
                Circle()
                    .stroke(CashbackScreenStyle.accent.opacity(0.6), lineWidth: 1.2)
            )
    }

    // MARK: - Cashbacks List

    private var cashbacksList: some View {
        List {
            Section {
                ForEach(Array(filteredCashbacks.enumerated()), id: \.element.id) { _, cashback in
                    CashbackRowView(
                        cashback: cashback,
                        viewModel: viewModel
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } header: {
                Text("Категории кешбэка")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.36))
                    .textCase(nil)
                    .padding(.leading, 6)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 86)
        }
        .padding(.top, -14)
    }

    private var searchPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            TextField("Поиск категории", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .foregroundStyle(AppColors.textPrimary)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    dismissSearchKeyboard()
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Очистить поиск"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                )
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .onAppear {
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
    }

    private var searchEmptyStateView: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 40)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)

            Text("Ничего не найдено")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text("Попробуйте другое название категории или карты")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 72)
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        let itemSize: CGFloat = 28
        let iconSize: CGFloat = 18

        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 6) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.96))
                        .frame(width: itemSize, height: itemSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Назад"))

                Button {
                    showQuickNavigationPopover.toggle()
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: iconSize - 2, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.90))
                        .frame(width: itemSize, height: itemSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Быстрая навигация по мини-приложениям"))
                .popover(isPresented: $showQuickNavigationPopover, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                    MiniAppQuickNavigationPopover(
                        destinations: MiniAppNavigation.destinations(excluding: currentRoute)
                    ) { destination in
                        showQuickNavigationPopover = false
                        MiniAppNavigation.navigate(to: destination.route, from: currentRoute, router: router)
                    }
                    .presentationCompactAdaptation(.popover)
                }
            }
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 10) {
                monthStepButton(
                    systemName: "chevron.left",
                    accessibilityLabel: "Предыдущий месяц",
                    isEnabled: viewModel.canMoveMonthBackward()
                ) {
                    viewModel.handle(.moveMonthBackward)
                }

                (
                    Text(toolbarMonthText)
                        .font(.system(size: 20, weight: .semibold))
                    + Text(" ")
                        .font(.system(size: 20, weight: .semibold))
                    + Text(toolbarYearText)
                        .font(.system(size: 16, weight: .medium))
                )
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)

                monthStepButton(
                    systemName: "chevron.right",
                    accessibilityLabel: "Следующий месяц",
                    isEnabled: viewModel.canMoveMonthForward()
                ) {
                    viewModel.handle(.moveMonthForward)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 10) {
                Button {
                    isSearchExpanded.toggle()
                    if !isSearchExpanded {
                        searchText = ""
                        dismissSearchKeyboard()
                    }
                } label: {
                    Image(systemName: isSearchExpanded ? "xmark" : "magnifyingglass")
                        .font(.system(size: iconSize - 1, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .frame(width: itemSize, height: itemSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(isSearchExpanded ? "Закрыть поиск" : "Поиск"))

                Button {
                    showCategorySettingsSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.94))
                        .frame(width: itemSize, height: itemSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Настройки категорий"))
            }
        }
    }

    @ViewBuilder
    private func monthStepButton(
        systemName: String,
        accessibilityLabel: LocalizedStringKey,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? AppColors.textPrimary : AppColors.textTertiary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var toolbarMonthText: String {
        CashbackMonthTitleFormatter.monthText(for: viewModel.state.selectedMonth, locale: localizationLocale)
    }

    private var toolbarYearText: String {
        CashbackMonthTitleFormatter.yearText(for: viewModel.state.selectedMonth, locale: localizationLocale)
    }

    private func dismissSearchKeyboard() {
        isSearchFieldFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

private struct CashbackCategorySettingsSheet: View {
    @ObservedObject var viewModel: CashbackViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    private var categoryOptions: [CashbackCategoryOption] {
        let options = viewModel.categoryOptions(matching: searchText, includeHidden: true)
            .filter { !$0.isCustom }
        return options.sorted { lhs, rhs in
            let lhsVisible = !viewModel.state.hiddenCategoryRaws.contains(lhs.rawValue)
            let rhsVisible = !viewModel.state.hiddenCategoryRaws.contains(rhs.rawValue)
            if lhsVisible != rhsVisible { return lhsVisible && !rhsVisible }
            let lhsFavorite = viewModel.isFavoriteCategory(rawValue: lhs.rawValue, fallbackName: lhs.displayName)
            let rhsFavorite = viewModel.isFavoriteCategory(rawValue: rhs.rawValue, fallbackName: rhs.displayName)
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
                            .fill(CashbackScreenStyle.subduedCircleFill)
                    }
                    .padding(.horizontal, 16)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(categoryOptions.enumerated()), id: \.element.rawValue) { index, category in
                                let isFavorite = viewModel.isFavoriteCategory(
                                    rawValue: category.rawValue,
                                    fallbackName: category.displayName
                                )
                                let isVisible = !viewModel.state.hiddenCategoryRaws.contains(category.rawValue)
                                let canHide = category.rawValue != CashbackCategory.other.rawValue
                                HStack(spacing: 12) {
                                    HStack(spacing: 12) {
                                        CashbackCategoryIconView(
                                            icon: category.icon,
                                            fontSize: 17,
                                            fontWeight: .semibold,
                                            tint: AnyShapeStyle(AppColors.textPrimary)
                                        )
                                        .frame(width: 28, height: 28)

                                        Text(category.displayName)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }

                                    Toggle(
                                        "",
                                        isOn: Binding(
                                            get: { isVisible },
                                            set: { newValue in
                                                _ = viewModel.setCategoryHidden(
                                                    rawValue: category.rawValue,
                                                    isHidden: !newValue
                                                )
                                            }
                                        )
                                    )
                                    .labelsHidden()
                                    .tint(CashbackScreenStyle.accent)
                                    .disabled(!canHide)

                                    Button {
                                        viewModel.handle(.toggleFavoriteCategory(rawValue: category.rawValue))
                                    } label: {
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
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(isFavorite ? Text("Убрать из избранного") : Text("Добавить в избранное"))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

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
                                .fill(CashbackScreenStyle.cardFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(CashbackScreenStyle.accent.opacity(0.35), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .padding(.top, 12)
            }
            .navigationTitle("Настройки категорий")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityLabel(Text("Закрыть"))
                }
                ToolbarItem(placement: .principal) {
                    Text("Настройки категорий")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    }
                }
        }
    }
}

private struct CashbackCardPromptOrb: View {
    @State private var isAnimating: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: AppColors.cashbackGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: CashbackScreenStyle.accent.opacity(0.28), radius: isAnimating ? 18 : 10, y: 6)

            Circle()
                .stroke(Color.white.opacity(isAnimating ? 0.28 : 0.12), lineWidth: 1.2)
                .scaleEffect(isAnimating ? 1.12 : 0.94)
                .blur(radius: isAnimating ? 0.4 : 0)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(isAnimating ? 0.34 : 0.20),
                            Color.white.opacity(0.02)
                        ],
                        center: .topLeading,
                        startRadius: 3,
                        endRadius: 24
                    )
                )
                .scaleEffect(isAnimating ? 1.04 : 0.92)

            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.black.opacity(0.82))
                .scaleEffect(isAnimating ? 1.06 : 0.94)
                .opacity(isAnimating ? 1 : 0.9)
        }
        .frame(width: 52, height: 52)
        .onAppear {
            guard !isAnimating else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
// MARK: - Cashback Row View

private struct CashbackRowView: View {
    let cashback: Cashback
    @ObservedObject var viewModel: CashbackViewModel
    private let rowHeight: CGFloat = 66
    private let rowVerticalSpacing: CGFloat = 5

    var body: some View {
        let categoryOption = viewModel.categoryOption(
            for: cashback.categoryRaw,
            fallbackName: cashback.name
        )
        let isFavorite = viewModel.isFavoriteCategory(
            rawValue: cashback.categoryRaw,
            fallbackName: cashback.name
        )
        let isPinned = viewModel.isPinnedCashback(cashback)

        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                categoryIconBox(icon: categoryOption.icon)

                VStack(alignment: .leading, spacing: 4) {
                    Text(categoryOption.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    Text(cardSubtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    if isFavorite {
                        statusBadge(title: "TOP", fill: Color.orange.opacity(0.18), tint: .orange)
                    }

                    if isPinned {
                        statusBadge(
                            title: "PIN",
                            fill: CashbackScreenStyle.neonCyan.opacity(0.18),
                            tint: CashbackScreenStyle.neonCyan
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(contentCardBackground)

            percentageCapsule
                .frame(height: rowHeight)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, rowVerticalSpacing)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                viewModel.handle(.togglePinnedCashback(cashback))
            } label: {
                Label {
                    if isPinned {
                        Text("Открепить")
                    } else {
                        Text("Закрепить")
                    }
                } icon: {
                    Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                }
            }
            .tint(.orange)
            .disabled(isFavorite)

            Button {
                viewModel.handle(.editCashback(cashback))
            } label: {
                Label("Редактировать", systemImage: "pencil")
            }
            .tint(CashbackScreenStyle.accent)

            Button(role: .destructive) {
                viewModel.handle(.deleteCashback(cashback))
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            .tint(AppColors.error)
        }
    }

    private func statusBadge(title: String, fill: Color, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(fill)
            )
    }

    private func categoryIconBox(icon: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))

            CashbackCategoryIconView(
                icon: icon,
                fontSize: 14,
                fontWeight: .semibold,
                tint: AnyShapeStyle(AppColors.textPrimary)
            )
        }
        .frame(width: 28, height: 28)
    }

    private var percentageCapsule: some View {
        Text(cashback.formattedPercentage)
            .font(.system(size: 21, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .foregroundStyle(CashbackScreenStyle.showcasePercentTint)
            .frame(width: rowHeight, height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(CashbackScreenStyle.showcaseCardFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(CashbackScreenStyle.showcaseCardStroke, lineWidth: CashbackScreenStyle.showcaseStrokeWidth)
                    }
            )
    }

    private var contentCardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(CashbackScreenStyle.showcaseCardFill)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CashbackScreenStyle.showcaseCardStroke, lineWidth: CashbackScreenStyle.showcaseStrokeWidth)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CashbackScreenStyle.showcaseInsetStroke, lineWidth: 0.5)
                    .padding(1)
            }
    }

    private var cardSubtitle: String {
        let names = viewModel
            .getCardsForCashback(cashback)
            .map(\.name)
        guard !names.isEmpty else { return String(localized: "Без привязанной карты") }
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

enum CashbackEditorCardSelectionResolver {
    static func resolve(
        existingCategoryRaws: [String],
        existingCardCashbacks: [String: String],
        currentCategoryRaws: Set<String>,
        currentCardCashbacks: [String: String],
        preserveCurrentIfExistingIsEmpty: Bool
    ) -> (selectedCategoryRaws: Set<String>, cardCashbacks: [String: String]) {
        if preserveCurrentIfExistingIsEmpty && existingCategoryRaws.isEmpty {
            return (currentCategoryRaws, currentCardCashbacks)
        }
        return (Set(existingCategoryRaws), existingCardCashbacks)
    }
}

private struct CashbackEditorView: View {
    @ObservedObject var viewModel: CashbackViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

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
    @State private var isImportAlertPremiumLocked: Bool = false
    @State private var showPaywallAlert: Bool = false
    @State private var paywallMessage: String = ""
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
                    isImportAlertPremiumLocked = false
                    importAlertMessage = nil
                }
            }
        )
    }

    private var limitedFreeCards: [Card] {
        let sorted = viewModel.state.availableCards.sorted { $0.createdAt < $1.createdAt }
        return Array(sorted.prefix(EntitlementPolicy.freeCashbackCardLimit))
    }

    private var availableCardsForPicker: [Card] {
        if appState.isPro {
            return viewModel.state.availableCards
        }
        return limitedFreeCards
    }

    private var cashbackCardsAreLimited: Bool {
        !appState.isPro && viewModel.state.availableCards.count > EntitlementPolicy.freeCashbackCardLimit
    }

    private var isScreenshotImportLocked: Bool {
        !EntitlementPolicy.canImportCashbackFromScreenshot(isPro: appState.isPro)
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
                .scrollDismissesKeyboard(.immediately)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissKeyboard()
                }
            )
            .navigationTitle(
                viewModel.state.editingCashback == nil
                    ? String(localized: "Новый кешбэк")
                    : String(localized: "Редактировать кешбэк")
            )
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
                    availableCards: availableCardsForPicker,
                    hasFreeLimit: cashbackCardsAreLimited,
                    onTapUpgrade: { router.push(.subscription) },
                    onCardsChanged: {
                        viewModel.handle(.loadCards)
                    }
                )
            }
            .sheet(isPresented: $showCategoryEditorSheet) {
                CashbackCategoryEditorSheet(
                    mode: categoryEditorMode,
                    name: categoryEditorName,
                    selectedIcon: categoryEditorIcon
                ) { name, icon in
                    handleCategoryEditorSave(name: name, icon: icon)
                } onDelete: {
                    handleCategoryEditorDelete()
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
                let shouldPreserveCurrentDraft = !selectedCategoryRaws.isEmpty
                preloadCategories(
                    for: cardID,
                    preserveCurrentIfStoredCashbackMissing: shouldPreserveCurrentDraft
                )
            }
            .onChange(of: screenshotPhotoItem) { _, newValue in
                guard let item = newValue else { return }
                guard !isScreenshotImportLocked else {
                    isImportAlertPremiumLocked = true
                    importAlertMessage = String(localized: "cashback.import.screenshot.pro_only")
                    screenshotPhotoItem = nil
                    return
                }
                Task {
                    await importFromScreenshot(item: item)
                }
            }
            .alert(String(localized: "Импорт со скриншота"), isPresented: isShowingImportAlert) {
                if isImportAlertPremiumLocked {
                    Button(String(localized: "subscription.button.subscribe")) {
                        router.push(.subscription)
                    }
                }
                Button("OK", role: .cancel) {
                    isImportAlertPremiumLocked = false
                    importAlertMessage = nil
                }
            } message: {
                Text(importAlertMessage ?? "")
            }
            .premiumUpsellAlert(
                isPresented: $showPaywallAlert,
                titleKey: "Ограничение Free-плана",
                message: paywallMessage,
                onSubscribe: { router.push(.subscription) }
            )
        }
    }

    // MARK: - Sections

    private var cardPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "Выберите карту"))

            Button {
                showCardPicker = true
            } label: {
                FinancesGlassCard(accentColor: CashbackScreenStyle.accent, cornerRadius: 20) {
                    HStack(spacing: 14) {
                        if let cardID = selectedCardID, let card = viewModel.getCard(byID: cardID) {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(CashbackScreenStyle.iconTintFill)

                                    Image(systemName: card.cardType.icon)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: AppColors.cashbackGradient,
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                }
                                .frame(width: 52, height: 52)

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(CashbackCardPresentation.title(for: card))
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .lineLimit(1)

                                        CashbackCardSelectionBadge(
                                            title: "Выбрана",
                                            tint: CashbackScreenStyle.accentSoft,
                                            fill: CashbackScreenStyle.accent.opacity(0.14)
                                        )
                                    }

                                    Text(CashbackCardPresentation.subtitle(for: card))
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppColors.textSecondary)
                                        .lineLimit(2)

                                    Text(CashbackCardPresentation.detail(for: card))
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(AppColors.textTertiary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                        } else {
                            HStack(spacing: 14) {
                                CashbackCardPromptOrb()

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Выбрать карту")
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)

                                    Text("Без карты кешбэк не сохранится")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppColors.textSecondary)
                                }

                                Spacer(minLength: 0)
                            }
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(18)
                }
            }
            .buttonStyle(.plain)

            if cashbackCardsAreLimited {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(
                        String(
                            format: String(localized: "cashback.free_plan.card_limit_format"),
                            EntitlementPolicy.freeCashbackCardLimit
                        )
                    )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                    Button(String(localized: "subscription.button.subscribe")) {
                        router.push(.subscription)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: String(localized: "Выбор категорий"))
            HStack {
                if isScreenshotImportLocked {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                        Text("cashback.import.screenshot.pro_only")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                        Spacer()
                        Button(String(localized: "subscription.button.subscribe")) {
                            router.push(.subscription)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 4)
                } else {
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
                            if isImportingFromScreenshot {
                                Text("cashback.import.screenshot.loading")
                                    .font(.system(size: 14, weight: .medium))
                            } else {
                                Text("Импорт со скриншота")
                                    .font(.system(size: 14, weight: .medium))
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            Capsule()
                                .fill(CashbackScreenStyle.subduedCircleFill)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isImportingFromScreenshot)
                }
                Spacer()
            }

            FinancesGlassCard(accentColor: CashbackScreenStyle.accent) {
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
                            HStack(spacing: 6) {
                                Button {
                                    toggleCategorySelection(for: category.rawValue, isSelected: isSelected)
                                } label: {
                                    HStack(spacing: 8) {
                                        CashbackCategoryIconView(
                                            icon: category.icon,
                                            fontSize: 14,
                                            fontWeight: .semibold,
                                            tint: AnyShapeStyle(AppColors.textPrimary)
                                        )
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
                                            .fill(isSelected ? Color.white.opacity(0.30) : CashbackScreenStyle.subduedCircleFill)
                                    }
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if category.isCustom {
                                        Button("Удалить", role: .destructive) {
                                            pendingCategoryRawAction = category.rawValue
                                            showDeleteCategoryAlert = true
                                        }
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
                                            .stroke(CashbackScreenStyle.accent, lineWidth: 1)
                                    }

                                Text("Создать категорию")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(AppColors.textPrimary)
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
                                if isShowingAllCategories {
                                    Text("Свернуть")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(AppColors.textPrimary)
                                } else {
                                    Text("Показать ещё")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(AppColors.textPrimary)
                                }
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
                    if viewModel.deleteCategory(rawValue: raw) {
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
                FinancesSectionHeader(title: String(localized: "Выбранные категории"))
                Spacer()
                HStack(spacing: 8) {
                    quickFillButton(5)
                    quickFillButton(7)
                    quickFillButton(10)
                }
            }

            FinancesGlassCard(accentColor: CashbackScreenStyle.accent) {
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
                                CashbackCategoryIconView(
                                    icon: category.icon,
                                    fontSize: 18,
                                    fontWeight: .regular,
                                    tint: AnyShapeStyle(AppColors.textPrimary)
                                )
                                .frame(width: 24, height: 24)

                                Text(category.displayName)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    toggleCategorySelection(for: category.rawValue, isSelected: true)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Убрать категорию"))

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
                                        .fill(CashbackScreenStyle.subduedCircleFill)
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
                        .fill(CashbackScreenStyle.subduedCircleFill)
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
                        .fill(CashbackScreenStyle.cardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(CashbackScreenStyle.glow)
                                .opacity(0.6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(CashbackScreenStyle.accent.opacity(0.55), lineWidth: 1)
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
        return selectedCategoryRaws.allSatisfy { raw in
            guard let percentage = percentageValue(for: raw) else { return false }
            return percentage > 0 && percentage <= 100
        }
    }

    // MARK: - Save

    func saveCashback() {
        guard let cardID = selectedCardID else { return }

        let projectedCategoryCount = viewModel.projectedCategoryCountForMonth(
            cardID: cardID,
            newCategoryRaws: selectedCategoryRaws
        )
        guard EntitlementPolicy.canAddCashbackCategories(
            isPro: appState.isPro,
            projectedCategoryCount: projectedCategoryCount
        ) else {
            paywallMessage = String(
                format: String(localized: "monetization.cashback.categories.limit.hard_format"),
                EntitlementPolicy.freeCashbackCategoryLimitPerMonth
            )
            showPaywallAlert = true
            return
        }

        let validCashbacks = selectedCategoryRaws.compactMap { raw -> (categoryRaw: String, categoryName: String, percentage: Double)? in
            guard let percentage = percentageValue(for: raw),
                  percentage > 0 && percentage <= 100 else {
                return nil
            }
            let option = viewModel.categoryOption(for: raw)
            return (categoryRaw: raw, categoryName: option.displayName, percentage: percentage)
        }

        viewModel.handle(.updateCashbacksForCard(
            cardID: cardID,
            cashbacks: validCashbacks
        ))

        dismiss()
    }

    // MARK: - Helpers

    @MainActor
    private func importFromScreenshot(item: PhotosPickerItem) async {
        guard !isScreenshotImportLocked else {
            isImportAlertPremiumLocked = true
            importAlertMessage = String(localized: "cashback.import.screenshot.pro_only")
            screenshotPhotoItem = nil
            return
        }
        isImportAlertPremiumLocked = false

        isImportingFromScreenshot = true
        defer {
            isImportingFromScreenshot = false
            screenshotPhotoItem = nil
        }

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            importAlertMessage = String(localized: "cashback.import.screenshot.read_failed")
            return
        }

        do {
            let parsed = try await screenshotParser.parse(from: data)
            applyImportedItems(parsed)
            importAlertMessage = String(
                format: String(localized: "cashback.import.screenshot.recognized_format"),
                parsed.count
            )
        } catch let error as CashbackScreenshotImportError {
            importAlertMessage = error.errorDescription
        } catch {
            importAlertMessage = String(localized: "cashback.import.screenshot.parse_failed")
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

    private func handleCategoryEditorDelete() {
        guard case .edit(let raw) = categoryEditorMode else { return }
        if viewModel.deleteCategory(rawValue: raw) {
            selectedCategoryRaws.remove(raw)
            cardCashbacks.removeValue(forKey: raw)
        }
        showCategoryEditorSheet = false
    }

    private func preloadCategories(for cardID: String, preserveCurrentIfStoredCashbackMissing: Bool = false) {
        let selectedMonthKey = Cashback.monthKey(for: viewModel.state.selectedMonth)
        let existingForCard = viewModel.state.cashbacks.filter { cashback in
            cashback.cardIDs.contains(cardID) && cashback.monthKey == selectedMonthKey
        }

        let existingCategoryRaws = existingForCard.map(\.categoryRaw)
        let existingCardCashbacks = Dictionary(
            uniqueKeysWithValues: existingForCard.map { ($0.categoryRaw, percentageText(for: $0.percentage)) }
        )
        let resolved = CashbackEditorCardSelectionResolver.resolve(
            existingCategoryRaws: existingCategoryRaws,
            existingCardCashbacks: existingCardCashbacks,
            currentCategoryRaws: selectedCategoryRaws,
            currentCardCashbacks: cardCashbacks,
            preserveCurrentIfExistingIsEmpty: preserveCurrentIfStoredCashbackMissing
        )
        selectedCategoryRaws = resolved.selectedCategoryRaws
        cardCashbacks = resolved.cardCashbacks
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

    private func toggleCategorySelection(for categoryRaw: String, isSelected: Bool) {
        if isSelected {
            selectedCategoryRaws.remove(categoryRaw)
            cardCashbacks.removeValue(forKey: categoryRaw)
        } else {
            selectedCategoryRaws.insert(categoryRaw)
            if cardCashbacks[categoryRaw] == nil {
                cardCashbacks[categoryRaw] = "5"
            }
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchText = ""
            isShowingAllCategories = false
        }
        dismissKeyboard()
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

private struct CashbackCategoryEditorSheet: View {
    private enum IconPickerTab: CaseIterable, Identifiable {
        case emoji
        case symbols

        var id: Self { self }

        var localizedTitle: String {
            switch self {
            case .emoji:
                return String(localized: "Эмодзи")
            case .symbols:
                return String(localized: "Иконки")
            }
        }
    }

    let mode: CashbackCategoryEditorMode
    let initialName: String
    let initialSelectedIcon: String
    @State private var name: String
    @State private var selectedIcon: String
    let onSave: (_ name: String, _ icon: String) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFieldFocused: Bool
    @State private var selectedTab: IconPickerTab = .emoji
    @State private var iconSearchText: String = ""
    @State private var showDeleteConfirmation: Bool = false

    init(
        mode: CashbackCategoryEditorMode,
        name: String,
        selectedIcon: String,
        onSave: @escaping (_ name: String, _ icon: String) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.initialName = name
        self.initialSelectedIcon = selectedIcon
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: name)
        _selectedIcon = State(initialValue: selectedIcon)
    }

    private var title: String {
        switch mode {
        case .create:
            return String(localized: "Новая категория")
        case .edit:
            return String(localized: "Категория")
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filteredSymbolIcons: [String] {
        let query = iconSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return CashbackCustomCategory.allowedSFSymbolIcons }
        return CashbackCustomCategory.allowedSFSymbolIcons.filter { $0.lowercased().contains(query) }
    }

    private var visibleIcons: [String] {
        switch selectedTab {
        case .symbols:
            return filteredSymbolIcons
        case .emoji:
            return CashbackCustomCategory.allowedEmojiIcons
        }
    }

    private var suggestedIcons: [String] {
        CashbackCategoryCatalog.suggestedIcons(for: name)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        FinancesSectionHeader(title: String(localized: "Название"))
                        FinancesGlassCard(accentColor: CashbackScreenStyle.accent) {
                            TextField("Например: Кофейни", text: $name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                                .focused($isNameFieldFocused)
                                .padding(16)
                        }

                        FinancesSectionHeader(title: String(localized: "Иконка"))
                        FinancesGlassCard(accentColor: CashbackScreenStyle.accent) {
                            VStack(spacing: 12) {
                                if !suggestedIcons.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(
                                            String(
                                                localized: "cashflow.editor.icon_suggestions",
                                                defaultValue: "Suggested icons",
                                                comment: "Suggested icons title for category creation"
                                            )
                                        )
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppColors.textSecondary)

                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 10) {
                                                ForEach(suggestedIcons, id: \.self) { icon in
                                                    let isSelected = selectedIcon == icon
                                                    Button {
                                                        selectedIcon = icon
                                                    } label: {
                                                        CashbackCategoryIconView(
                                                            icon: icon,
                                                            fontSize: 22,
                                                            fontWeight: .semibold,
                                                            tint: AnyShapeStyle(AppColors.textPrimary)
                                                        )
                                                        .frame(width: 52, height: 52)
                                                        .background {
                                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                                .fill(isSelected ? Color.white.opacity(0.22) : CashbackScreenStyle.subduedCircleFill)
                                                                .overlay(
                                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                                        .stroke(CashbackScreenStyle.accent.opacity(isSelected ? 0.75 : 0.15), lineWidth: 1)
                                                                )
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            .padding(.horizontal, 2)
                                        }
                                    }
                                }

                                Picker("Тип иконки", selection: $selectedTab) {
                                    Text(IconPickerTab.emoji.localizedTitle)
                                        .tag(IconPickerTab.emoji)
                                    Text(IconPickerTab.symbols.localizedTitle)
                                        .tag(IconPickerTab.symbols)
                                }
                                .pickerStyle(.segmented)

                                if selectedTab == .symbols {
                                    HStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(AppColors.textTertiary)
                                        TextField("Поиск иконки (например, машина, корзина, сердце)", text: $iconSearchText)
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundStyle(AppColors.textPrimary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(CashbackScreenStyle.subduedCircleFill)
                                    }
                                }

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10) {
                                    ForEach(visibleIcons, id: \.self) { icon in
                                    let isSelected = selectedIcon == icon
                                    Button {
                                        selectedIcon = icon
                                    } label: {
                                        CashbackCategoryIconView(
                                            icon: icon,
                                            fontSize: 22,
                                            fontWeight: .semibold,
                                            tint: AnyShapeStyle(AppColors.textPrimary)
                                        )
                                        .frame(width: 54, height: 54)
                                            .background {
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(isSelected ? Color.white.opacity(0.22) : CashbackScreenStyle.subduedCircleFill)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                            .stroke(CashbackScreenStyle.accent.opacity(isSelected ? 0.75 : 0.15), lineWidth: 1)
                                                    )
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            }
                            .padding(12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    dismissKeyboard()
                }
            )
            .navigationTitle(title)
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
                    .accessibilityLabel(Text("Отмена"))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if case .edit = mode {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Удалить"))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        onSave(name, selectedIcon)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cashbackGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .disabled(!isValid)
                    .accessibilityLabel(Text("Сохранить"))
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    isNameFieldFocused = true
                }
                name = initialName
                selectedIcon = initialSelectedIcon
                switch mode {
                case .create:
                    selectedTab = .emoji
                case .edit:
                    selectedTab = CashbackCustomCategory.isSFSymbolIcon(selectedIcon) ? .symbols : .emoji
                }
                iconSearchText = ""
            }
            .alert("Удалить категорию?", isPresented: $showDeleteConfirmation) {
                Button("Отмена", role: .cancel) {}
                Button("Удалить", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
            } message: {
                Text("Связанные кешбэки этой категории будут перенесены в «Другое».")
            }
        }
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

// MARK: - Cashback Single Card Picker View

private struct CashbackSingleCardPickerView: View {
    @Binding var selectedCardID: String
    let availableCards: [Card]
    let hasFreeLimit: Bool
    let onTapUpgrade: () -> Void
    let onCardsChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var isAddCardRecommendationHidden = CashbackCardPickerRecommendationPrefs.shared.isHidden()
    @State private var financeViewModel: FinanceViewModel?
    @State private var showAddCardSheet: Bool = false
    private let currentRoute: AppRoute = .cashback

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
                        VStack(alignment: .leading, spacing: 14) {
                            pickerHeader

                            if hasFreeLimit {
                                freeLimitHint
                            }

                            ForEach(availableCards) { card in
                                let cardID = card.cardUniqueID
                                let isSelected = selectedCardID == cardID

                                Button {
                                    selectedCardID = cardID
                                    dismiss()
                                } label: {
                                    cardRow(card: card, isSelected: isSelected)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)

                        Color.clear.frame(height: isAddCardRecommendationHidden ? 16 : 108)
                    }
                }

                if !isAddCardRecommendationHidden {
                    VStack {
                        Spacer()
                        cardCreationRecommendationBanner
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                }
            }
            .navigationTitle("Выбор карты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.brandPrimary)
                    .accessibilityLabel(Text("Готово"))
                }
            }
            .sheet(isPresented: $showAddCardSheet, onDismiss: onCardsChanged) {
                if let financeViewModel {
                    FinanceAddAccountView(
                        viewModel: financeViewModel,
                        preselectedAccountType: .card
                    )
                }
            }
        }
    }

    private var pickerHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Выберите карту, для которой вы настраиваете категории и проценты в этом месяце")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let selectedCard = availableCards.first(where: { $0.cardUniqueID == selectedCardID }) {
                HStack(spacing: 8) {
                    Text("Выбрана")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CashbackScreenStyle.accentSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CashbackScreenStyle.accent.opacity(0.14))
                        )

                    Text(CashbackCardPresentation.title(for: selectedCard))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? CashbackScreenStyle.accent.opacity(0.16) : Color.white.opacity(0.03))
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? CashbackScreenStyle.accent.opacity(0.52) : Color.white.opacity(0.10),
                            lineWidth: 1
                        )
                )

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: AppColors.cashbackGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        : AnyShapeStyle(AppColors.textTertiary.opacity(0.7))
                )
        }
        .frame(width: 30, height: 30)
    }

    private func favoriteMarker(for card: Card) -> some View {
        Group {
            if card.isFavorite {
                Label("Избранная", systemImage: "star.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private func rowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? CashbackScreenStyle.accent.opacity(0.10) : Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? CashbackScreenStyle.accent.opacity(0.34) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
    }

    private var freeLimitHint: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CashbackScreenStyle.accentSoft)

            Text(
                String(
                    format: String(localized: "cashback.free_plan.card_limit_format"),
                    EntitlementPolicy.freeCashbackCardLimit
                )
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppColors.textSecondary)

            Spacer(minLength: 8)

            Button(String(localized: "cashback.free_plan.show_all_cards_pro")) {
                onTapUpgrade()
            }
            .font(.system(size: 13, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(
                LinearGradient(
                    colors: AppColors.cashbackGradient,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CashbackScreenStyle.accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func cardRow(card: Card, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            selectionIndicator(isSelected: isSelected)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(CashbackCardPresentation.title(for: card))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    favoriteMarker(for: card)
                }

                Text(CashbackCardPresentation.pickerSubtitle(for: card))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(rowBackground(isSelected: isSelected))
    }

    private var cardCreationRecommendationBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lightbulb.max.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                Text("Где добавить новую карту")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button("Скрыть") {
                    isAddCardRecommendationHidden = true
                    CashbackCardPickerRecommendationPrefs.shared.setHidden(true)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .accessibilityLabel(Text("Скрыть рекомендацию"))
            }

            Text("Новой карты нет в списке? Добавьте ее в «Финансах»")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if financeViewModel == nil {
                    financeViewModel = FinanceViewModel(modelContext: modelContext)
                }
                showAddCardSheet = true
            } label: {
                Text("Добавить карту")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Открыть создание новой карты"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CashbackScreenStyle.accent.opacity(0.04))
                )
        }
    }
}

#Preview {
    NavigationStack {
        CashbackView()
    }
}
