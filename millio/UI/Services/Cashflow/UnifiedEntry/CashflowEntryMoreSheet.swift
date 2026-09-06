//
//  CashflowEntryMoreSheet.swift
//  millio
//
//  Лист «…» экрана быстрого ввода: всё редкое (поиск, плановые, импорт, план на месяц,
//  сортировка и управление категориями) собрано под большим пальцем.
//

import SwiftUI

/// Действие, выбранное в листе «…». Обрабатывается вызывающим экраном после закрытия листа —
/// открыть новый sheet поверх закрывающегося iOS не даёт, поэтому действие откладывается в onDismiss.
enum CashflowEntryMoreAction: Hashable {
    case search
    case management(CashflowManagementDestination)
    case monthPlan
    case reorderCategories
    case screenSettings
    case createCategory
}

struct CashflowEntryMoreSheet: View {
    let kind: CashflowCategoryTransactionSheetKind
    let planTitle: String
    @Binding var sortMode: CashflowCategorySortMode
    let onSelect: (CashflowEntryMoreAction) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Фиксированная высота: контент статичен (3 секции, 9 пунктов), поэтому детент считаем константой,
    /// а не через .presentationSizing — так лист не «прыгает» при открытии.
    static let detentHeight: CGFloat = 470

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            Text(L("cashflow.entry.more.title", defaultValue: "More"))
                .font(.millioTitle3)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.top, AppSpacing.l)

            section(title: L("cashflow.entry.more.section.operations", defaultValue: "Operations")) {
                row(
                    title: L("cashflow.operation.search_category"),
                    icon: "magnifyingglass",
                    action: .search
                )
                ForEach(CashflowManagementEntry.entries(for: kind.categoryKind)) { entry in
                    row(title: entry.title, icon: entry.icon, action: .management(entry.destination))
                }
            }

            section(title: L("cashflow.entry.more.section.month", defaultValue: "Month")) {
                row(title: planTitle, icon: "target", action: .monthPlan)
            }

            section(title: L("cashflow.entry.more.section.categories", defaultValue: "Categories")) {
                sortRow
                row(
                    title: L("cashflow.category.reorder.edit", defaultValue: "Edit order"),
                    icon: "arrow.up.arrow.down",
                    action: .reorderCategories
                )
                row(
                    title: L("cashflow.common.settings", defaultValue: "Settings"),
                    icon: "gearshape",
                    action: .screenSettings
                )
                row(
                    title: L("cashflow.category.create.title", defaultValue: "New category"),
                    icon: "plus",
                    action: .createCategory
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.ignoresSafeArea())
        .presentationDetents([.height(Self.detentHeight)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(title)
                .font(.millioCaption)
                .foregroundStyle(AppColors.textSecondary)
            content()
        }
    }

    private func row(title: String, icon: String, action: CashflowEntryMoreAction) -> some View {
        Button {
            dismiss()
            onSelect(action)
        } label: {
            HStack(spacing: AppSpacing.m) {
                Image(systemName: icon)
                    .font(.millioSubheadline)
                    .foregroundStyle(kind.accentColor)
                    .frame(width: AppSpacing.xxl)
                Text(title)
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .frame(minHeight: AppSpacing.xxxl)
        }
        .buttonStyle(.plain)
    }

    /// Сортировка меняет стейт на месте — лист не закрываем, чтобы можно было сравнить варианты.
    private var sortRow: some View {
        Menu {
            Picker(L("cashflow.category.reorder.sort", defaultValue: "Sort"), selection: $sortMode) {
                ForEach(CashflowCategorySortMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        } label: {
            HStack(spacing: AppSpacing.m) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.millioSubheadline)
                    .foregroundStyle(kind.accentColor)
                    .frame(width: AppSpacing.xxl)
                Text(L("cashflow.category.reorder.sort", defaultValue: "Sort"))
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: 0)
                Text(sortMode.title)
                    .font(.millioCallout)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .contentShape(Rectangle())
            .frame(minHeight: AppSpacing.xxxl)
        }
    }
}
