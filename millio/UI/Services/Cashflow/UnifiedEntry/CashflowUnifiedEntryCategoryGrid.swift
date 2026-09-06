//
//  CashflowUnifiedEntryCategoryGrid.swift
//  millio
//
//  Сетка категорий экрана быстрого ввода: заголовок секции, плитки, плитка «Новая»,
//  оверлей действий над категорией и её CRUD. Вынесено из CashflowUnifiedEntryView
//  без изменения поведения (Ф5 плана entry-screen-simplify).
//

import SwiftUI

extension CashflowCategoryTransactionSheet {
    var categoriesSectionHeader: some View {
        HStack {
            Text(L("cashflow.entry.more.section.categories", defaultValue: "Categories"))
                .font(.millioSubheadline)
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            if showsCategoryExpandLink {
                Button {
                    withAnimation(AppAnimation.standard) { showAllCategories = true }
                } label: {
                    Text(L("cashflow.entry.all_short", defaultValue: "All"))
                        .font(.millioCallout)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var categoriesSection: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: categoryColumns, spacing: AppSpacing.s) {
                ForEach(visibleCategories) { option in
                    categoryCard(for: option)
                        .id(option.rawValue)
                }
                newCategoryTile
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            updateCategoryGridWidth(proxy.size.width)
                        }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            updateCategoryGridWidth(newWidth)
                        }
                }
            }

            if hasCompletedInitialLoad && monthlyTotal == 0 {
                cashflowEmptyMonthState
                    .padding(.top, AppSpacing.xxl)
            }
        }
    }

    /// Последняя плитка сетки: создание категории прямо из сетки, пунктирная рамка
    /// отличает её от обычных категорий.
    private var newCategoryTile: some View {
        Button {
            showCreateCategorySheet = true
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                ZStack {
                    Circle().stroke(
                        AppColors.textSecondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                    Image(systemName: "plus")
                        .font(.millioSubheadline)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(width: 40, height: 40)

                Text(L("cashflow.entry.category.new_short", defaultValue: "New"))
                    .font(.millioCalloutSemibold)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: CashflowCategoryGridLayout.unifiedCardMinHeight, alignment: .topLeading)
            .padding(AppSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        AppColors.textSecondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("cashflow.category.create.title", defaultValue: "New category"))
    }

    /// Однократная подсказка (§7.5): закрывает недискаверабельность pin-жеста и
    /// cap-сетки. Реализована как обычный dismissible-баннер (паттерн уже есть в
    /// `CashflowCurrencySelectorView`), а не как anchored coach-mark с указателями —
    /// отдельная позиционная система тултипов для двух строк текста была бы
    /// абстракцией ради абстракции (KISS) для задачи такого размера.
    @ViewBuilder
    var categoryCapCoachMarkBanner: some View {
        if showCategoryCapCoachMark {
            HStack(alignment: .top, spacing: AppSpacing.s) {
                Image(systemName: "hand.tap.fill")
                    .font(.millioCalloutSemibold)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(L("cashflow.category.coachmark.pin_hint", defaultValue: "Long-press to pin a category"))
                    Text(L("cashflow.category.coachmark.show_all_hint", defaultValue: "All categories →"))
                }
                .font(.millioCaptionRegular)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    withAnimation(AppAnimation.standard) {
                        showCategoryCapCoachMark = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.millioCaption2)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("cashflow.common.close"))
            }
            .padding(.vertical, AppSpacing.s)
            .padding(.horizontal, AppSpacing.m)
            .background(innerPanelBackground)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var cashflowEmptyMonthState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(L("cashflow.category.empty_month"))
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }

    /// Компактная плитка сетки 3×N: иконка в круге 40 pt · имя · сумма.
    /// Полоска лимита остаётся — без неё сигнал о превышении бюджета виден только
    /// в листе плана; бейджи и подпись лимита ушли туда же ради компактности.

    private func categoryCard(for option: CashflowCategoryOption) -> some View {
        let summary = categoryBudgetSummary(for: option)
        let amount = categoryTotals[option.rawValue, default: 0]
        let isActive = amount > 0.0000001
        let isHighlighted = highlightedCategoryRaw == option.rawValue
        let feedbackPlan = categoryUpdateFeedbackPlan?.categoryRawValue == option.rawValue ? categoryUpdateFeedbackPlan : nil
        let feedbackColor = kind.amountColor(for: feedbackPlan?.delta ?? 0)
        let isPinned = viewModel.isCategoryPinned(rawValue: option.rawValue, kind: kind.categoryKind)

        return ZStack(alignment: .topTrailing) {
            Button {
                if suppressNextCategoryTap {
                    suppressNextCategoryTap = false
                    return
                }
                selectedCategory = option
            } label: {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    ZStack {
                        Circle().fill(kind.accentColor.opacity(isActive ? 0.20 : 0.09))
                        CashflowCategoryIconView(
                            icon: option.icon,
                            fontSize: 16,
                            fontWeight: .semibold,
                            tint: AnyShapeStyle(AppColors.textPrimary)
                        )
                    }
                    .frame(width: 40, height: 40)

                    Text(option.displayName)
                        .font(.millioCallout)
                        .foregroundStyle(AppColors.textPrimary.opacity(isActive ? 1 : 0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(formattedCategoryTotal(for: option))
                        .font(.millioBodySemibold)
                        .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textSecondary.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                        .scaleEffect(isHighlighted ? 1.07 : 1)
                        .animation(.spring(response: 0.32, dampingFraction: 0.68), value: isHighlighted)

                    if let summary {
                        GeometryReader { proxy in
                            let progress = min(max(summary.progress, 0), 1)
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                                Capsule(style: .continuous)
                                    .fill(budgetStatusColor(summary.status))
                                    .frame(width: max(4, proxy.size.width * progress))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: CashflowCategoryGridLayout.unifiedCardMinHeight, alignment: .topLeading)
                .padding(AppSpacing.s)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(isActive ? 0.075 : 0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(feedbackColor.opacity(isHighlighted ? 0.95 : 0), lineWidth: 1.4)
                        )
                        .shadow(color: feedbackColor.opacity(isHighlighted ? 0.28 : 0), radius: isHighlighted ? 16 : 0)
                )
                .scaleEffect(isHighlighted ? 1.015 : 1)
                .animation(.spring(response: 0.34, dampingFraction: 0.8), value: isHighlighted)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in
                        suppressNextCategoryTap = true
                        openCategoryActions(for: option)
                    }
            )

            if isPinned {
                pinnedBadge
                    .padding(AppSpacing.xs)
            }
        }
    }

    private var pinnedBadge: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color(hex: "FF6B6B"))
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .accessibilityLabel(L("cashflow.category.pinned"))
    }

    private func togglePinned(for option: CashflowCategoryOption) {
        let nextValue = !viewModel.isCategoryPinned(rawValue: option.rawValue, kind: kind.categoryKind)
        viewModel.setCategoryPinned(rawValue: option.rawValue, kind: kind.categoryKind, isPinned: nextValue)
    }

    private func openCategoryEditor(for option: CashflowCategoryOption) {
        categoryEditorMode = .edit(rawValue: option.rawValue)
        categoryEditorName = option.displayName
        categoryEditorIcon = option.icon
        showCategoryEditorSheet = true
    }

    private func openCategoryActions(for option: CashflowCategoryOption) {
        pendingActionCategory = option
        showCategoryActionsDialog = true
    }

    private func closeCategoryActions() {
        showCategoryActionsDialog = false
        pendingActionCategory = nil
    }

    private func destructiveActionTitle(for option: CashflowCategoryOption) -> String {
        option.isCustom
            ? L("cashflow.category.actions.delete")
            : String(
                localized: "cashflow.category.actions.archive",
                defaultValue: "Archive",
                comment: "Archive system category action title"
            )
    }

    private func destructiveActionIcon(for option: CashflowCategoryOption) -> String {
        option.isCustom ? "trash" : "archivebox"
    }

    private func presentDeleteCategoryFlow(for option: CashflowCategoryOption) {
        pendingCategoryDeletionPreview = viewModel.categoryDeletionPreview(
            rawValue: option.rawValue,
            kind: kind.categoryKind
        )
    }

    private func handleCategoryDeletion(preview: CashflowCategoryDeletionPreview, targetRaw: String) {
        guard let undoAction = viewModel.performCategoryRemoval(
            rawValue: preview.rawValue,
            kind: preview.kind,
            targetRawValue: targetRaw
        ) else {
            return
        }

        if selectedCategory?.rawValue == preview.rawValue {
            selectedCategory = viewModel.categoryOption(for: targetRaw, kind: preview.kind)
        }
        pendingCategoryDeletionPreview = nil
        presentUndoCategoryDeletion(undoAction)
    }

    private func presentUndoCategoryDeletion(_ action: CashflowCategoryMutationUndoAction) {
        categoryUndoDismissTask?.cancel()
        pendingCategoryUndoAction = action
        categoryUndoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            pendingCategoryUndoAction = nil
        }
    }

    private func dismissUndoCategoryDeletion() {
        categoryUndoDismissTask?.cancel()
        categoryUndoDismissTask = nil
        pendingCategoryUndoAction = nil
    }

    private func handleUndoCategoryDeletion() {
        guard let action = pendingCategoryUndoAction else { return }
        guard viewModel.undoCategoryMutation(action) else { return }
        if selectedCategory?.rawValue == action.targetOption.rawValue {
            selectedCategory = viewModel.categoryOption(
                for: action.sourceOption.rawValue,
                kind: action.kind
            )
        }
        dismissUndoCategoryDeletion()
    }

    func handleCategoryEditorSave(name: String, icon: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        switch categoryEditorMode {
        case .create:
            if viewModel.createCustomCategory(kind: kind.categoryKind, name: trimmedName, icon: icon) != nil {
                searchText = ""
            }
        case .edit(let rawValue):
            guard viewModel.renameCategory(
                rawValue: rawValue,
                kind: kind.categoryKind,
                newName: trimmedName,
                newIcon: icon
            ) else { return }

            if selectedCategory?.rawValue == rawValue {
                if let resolved = viewModel.categoryOptions(for: kind.categoryKind, includeHiddenSystem: true).first(where: {
                    $0.displayName.caseInsensitiveCompare(trimmedName) == .orderedSame
                }) {
                    selectedCategory = resolved
                } else {
                    selectedCategory = nil
                }
            }
        }

        showCategoryEditorSheet = false
    }
    private var categoryColumns: [GridItem] {
        CashflowCategoryGridLayout.columns(
            for: kind,
            containerWidth: categoryGridWidth
        )
    }

    private var categories: [CashflowCategoryOption] {
        let base = viewModel.orderedCategoryOptions(
            for: kind.categoryKind,
            matching: searchText
        )
        guard searchText.isEmpty, !frozenCategoryOrder.isEmpty else { return base }
        let rank = Dictionary(uniqueKeysWithValues: frozenCategoryOrder.enumerated().map { ($0.element, $0.offset) })
        return base.sorted { rank[$0.rawValue, default: .max] < rank[$1.rawValue, default: .max] }
    }

    // MARK: - Cap избранных категорий (§2.2 плана редизайна add-flow, Фаза 2)
    // Сама формула cap вынесена в `CashflowCategoryCapPolicy` (чистая функция, юнит-тестируется
    // без View-харнеса) — здесь только адаптация к состоянию этого экрана (поиск/showAll/pin).

    private var isCategorySearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// R8: активный поиск снимает cap полностью — иначе категория вне топа не найдётся.
    private var shouldCapCategories: Bool {
        !showAllCategories && !isCategorySearchActive
    }

    /// Сколько pinned-категорий в начале уже отсортированного списка (pinned всегда
    /// идут первыми — инвариант `sortCategoryOptions`/`sortCategoryOptionsWithCustomOrder`).
    private var pinnedCategoryCount: Int {
        categories.prefix { viewModel.isCategoryPinned(rawValue: $0.rawValue, kind: kind.categoryKind) }.count
    }

    private var categoryCapCount: Int {
        CashflowCategoryCapPolicy.visibleCount(pinnedCount: pinnedCategoryCount, totalCount: categories.count)
    }

    private var visibleCategories: [CashflowCategoryOption] {
        guard shouldCapCategories else { return categories }
        return Array(categories.prefix(categoryCapCount))
    }

    private var showsCategoryExpandLink: Bool {
        shouldCapCategories && categories.count > categoryCapCount
    }

    private var hasCustomCategoryOrder: Bool {
        viewModel.categoryCustomOrder(for: kind.categoryKind) != nil
    }

    func presentCategoryUpdateFeedback(using scrollProxy: ScrollViewProxy) {
        guard let feedbackPlan = categoryUpdateFeedbackPlan else { return }

        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            scrollProxy.scrollTo(feedbackPlan.categoryRawValue, anchor: .center)
            highlightedCategoryRaw = feedbackPlan.categoryRawValue
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            await MainActor.run {
                guard highlightedCategoryRaw == feedbackPlan.categoryRawValue else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    highlightedCategoryRaw = nil
                }
            }
        }
    }

    private func formattedCategoryTotal(for option: CashflowCategoryOption) -> String {
        let value = categoryTotals[option.rawValue] ?? 0
        return formattedAmount(value)
    }

    private func categoryBudgetSummary(for option: CashflowCategoryOption) -> BudgetCategoryProgressSnapshot? {
        return budgetSnapshot?.categorySnapshots.first(where: { $0.categoryRawValue == option.rawValue })
    }

    func handleCreateCategory(_ name: String, icon: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if viewModel.createCustomCategory(kind: kind.categoryKind, name: trimmedName, icon: icon) != nil {
            searchText = ""
        }

        newCategoryName = ""
        newCategoryIcon = CashflowCustomCategory.defaultIcon
        showCreateCategorySheet = false
    }

    private func updateCategoryGridWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        let rounded = width.rounded(.toNearestOrAwayFromZero)
        guard abs(rounded - categoryGridWidth) >= 1 else { return }
        categoryGridWidth = rounded
    }

    private func budgetStatusColor(_ status: BudgetStatus) -> Color {
        budgetStatusTintToken(status).color
    }

    /// Оверлей действий над категорией (long-press): pin, операции, редактирование, удаление.
    @ViewBuilder
    var categoryActionsOverlay: some View {
        if let option = pendingActionCategory {
            CashflowCategoryActionOverlay(
                isPresented: showCategoryActionsDialog,
                categoryName: option.displayName,
                categoryIcon: option.icon,
                accentColor: kind.accentColor,
                primaryActionTitle: viewModel.isCategoryPinned(rawValue: option.rawValue, kind: kind.categoryKind)
                    ? L("cashflow.category.actions.unpin")
                    : L("cashflow.category.actions.pin"),
                primaryActionIcon: viewModel.isCategoryPinned(rawValue: option.rawValue, kind: kind.categoryKind)
                    ? "pin.slash"
                    : "pin",
                onPrimaryAction: {
                    togglePinned(for: option)
                    closeCategoryActions()
                },
                secondaryActionTitle: L("cashflow.category.actions.operations"),
                secondaryActionIcon: "list.bullet.rectangle",
                onSecondaryAction: {
                    openOperations(for: option)
                },
                onEdit: {
                    closeCategoryActions()
                    openCategoryEditor(for: option)
                },
                deleteActionTitle: destructiveActionTitle(for: option),
                deleteActionIcon: destructiveActionIcon(for: option),
                onDelete: viewModel.canDeleteCategory(rawValue: option.rawValue, kind: kind.categoryKind) ? {
                    closeCategoryActions()
                    presentDeleteCategoryFlow(for: option)
                } : nil,
                onDismiss: closeCategoryActions
            )
        }
    }

    func categoryDeletionSheet(for preview: CashflowCategoryDeletionPreview) -> some View {
        CashflowCategoryDeletionSheet(viewModel: viewModel, preview: preview) { targetRaw in
            handleCategoryDeletion(preview: preview, targetRaw: targetRaw)
        }
    }

    @ViewBuilder
    var categoryUndoOverlay: some View {
        if let pendingCategoryUndoAction {
            CashflowCategoryUndoBanner(action: pendingCategoryUndoAction) {
                handleUndoCategoryDeletion()
            } onDismiss: {
                dismissUndoCategoryDeletion()
            }
        }
    }
}
