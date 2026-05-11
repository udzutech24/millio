//
//  CashflowCategorySettingsSheet.swift
//  millio
//

import SwiftUI

struct CashflowCategorySettingsSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let kind: CashflowCategoryTransactionSheetKind

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var showActionsDialog: Bool = false
    @State private var showEditorSheet: Bool = false
    @State private var editorMode: CashflowCategoryEditorMode = .create
    @State private var editorName: String = ""
    @State private var editorIcon: String = CashflowCustomCategory.defaultIcon
    @State private var pendingDeletePreview: CashflowCategoryDeletionPreview?
    @State private var pendingUndoAction: CashflowCategoryMutationUndoAction?
    @State private var undoDismissTask: Task<Void, Never>?
    @State private var pendingActionCategory: CashflowCategoryOption?

    private var systemOptions: [CashflowCategoryOption] {
        viewModel.categoryOptions(
            for: kind.categoryKind,
            matching: searchText,
            includeHiddenSystem: true
        ).filter { !$0.isCustom }
    }

    private var customOptions: [CashflowCategoryOption] {
        viewModel.categoryOptions(
            for: kind.categoryKind,
            matching: searchText,
            includeHiddenSystem: true
        ).filter { $0.isCustom }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                String(
                                    localized: "cashflow.category.settings.title",
                                    defaultValue: "Category settings",
                                    comment: "Category settings section title"
                                )
                            )
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)

                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
                                TextField(
                                    String(
                                        localized: "cashflow.operation.search_category",
                                        defaultValue: "Search category",
                                        comment: "Category settings search placeholder"
                                    ),
                                    text: $searchText
                                )
                                .textInputAutocapitalization(.words)
                                .foregroundStyle(AppColors.textPrimary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )

                            VStack(spacing: 10) {
                                ForEach(systemOptions) { option in
                                    categoryVisibilityRow(for: option)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(
                String(
                    localized: "cashflow.category.settings.title",
                    defaultValue: "Category settings",
                    comment: "Settings sheet title"
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    }
                    .accessibilityLabel(L("cashflow.common.close"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .overlay(alignment: .bottom) {
            if let option = pendingActionCategory {
                CashflowCategoryActionOverlay(
                    isPresented: showActionsDialog,
                    categoryName: option.displayName,
                    categoryIcon: option.icon,
                    accentColor: kind.accentColor,
                    primaryActionTitle: nil,
                    primaryActionIcon: nil,
                    onPrimaryAction: nil,
                    secondaryActionTitle: nil,
                    secondaryActionIcon: nil,
                    onSecondaryAction: nil,
                    onEdit: {
                        closeSettingsCategoryActions()
                        openEditSheet(for: option)
                    },
                    deleteActionTitle: option.isCustom
                        ? L("cashflow.category.actions.delete")
                        : String(
                            localized: "cashflow.category.actions.archive",
                            defaultValue: "Archive",
                            comment: "Archive system category action title"
                        ),
                    deleteActionIcon: option.isCustom ? "trash" : "archivebox",
                    onDelete: viewModel.canDeleteCategory(rawValue: option.rawValue, kind: kind.categoryKind) ? {
                        closeSettingsCategoryActions()
                        presentDeleteCategoryFlow(for: option)
                    } : nil,
                    onDismiss: closeSettingsCategoryActions
                )
            }
        }
        .sheet(item: $pendingDeletePreview) { preview in
            CashflowCategoryDeletionSheet(viewModel: viewModel, preview: preview) { targetRaw in
                guard let undoAction = viewModel.performCategoryRemoval(
                    rawValue: preview.rawValue,
                    kind: preview.kind,
                    targetRawValue: targetRaw
                ) else {
                    return
                }
                presentUndoAction(undoAction)
                pendingDeletePreview = nil
            }
        }
        .overlay(alignment: .bottom) {
            if let pendingUndoAction {
                CashflowCategoryUndoBanner(action: pendingUndoAction) {
                    guard viewModel.undoCategoryMutation(pendingUndoAction) else { return }
                    dismissUndoAction()
                } onDismiss: {
                    dismissUndoAction()
                }
            }
        }
        .fullScreenCover(isPresented: $showEditorSheet) {
            CashflowCategoryEditorSheet(
                mode: editorMode,
                name: $editorName,
                icon: $editorIcon
            ) { name, icon in
                handleSave(name: name, icon: icon)
            }
        }
    }

    private func categoryVisibilityRow(for option: CashflowCategoryOption) -> some View {
        let isVisible = viewModel.categoryOptions(for: kind.categoryKind).contains { $0.rawValue == option.rawValue }
        let canHide = option.rawValue != fallbackRaw

        return HStack(spacing: 12) {
            CashflowCategoryIconView(
                icon: option.icon,
                fontSize: 18,
                fontWeight: .semibold,
                tint: AnyShapeStyle(AppColors.textPrimary)
            )
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(option.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(
                    visibilityText(isVisible: isVisible, canHide: canHide)
                )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Button {
                openActions(for: option)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("cashflow.common.edit"))

            Toggle(
                "",
                isOn: Binding(
                    get: { isVisible },
                    set: { newValue in
                        _ = viewModel.setSystemCategoryHidden(
                            kind: kind.categoryKind,
                            categoryRaw: option.rawValue,
                            isHidden: !newValue
                        )
                    }
                )
            )
            .labelsHidden()
            .tint(AppColors.brandPrimary)
            .disabled(!canHide)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var fallbackRaw: String {
        kind.categoryKind == .income ? IncomeCategory.other.rawValue : ExpenseCategory.other.rawValue
    }

    private func openEditSheet(for option: CashflowCategoryOption) {
        editorMode = .edit(rawValue: option.rawValue)
        editorName = option.displayName
        editorIcon = option.icon
        showEditorSheet = true
    }

    private func openActions(for option: CashflowCategoryOption) {
        pendingActionCategory = option
        showActionsDialog = true
    }

    private func closeSettingsCategoryActions() {
        showActionsDialog = false
        pendingActionCategory = nil
    }

    private func presentDeleteCategoryFlow(for option: CashflowCategoryOption) {
        pendingDeletePreview = viewModel.categoryDeletionPreview(
            rawValue: option.rawValue,
            kind: kind.categoryKind
        )
    }

    private func presentUndoAction(_ action: CashflowCategoryMutationUndoAction) {
        undoDismissTask?.cancel()
        pendingUndoAction = action
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            pendingUndoAction = nil
        }
    }

    private func dismissUndoAction() {
        undoDismissTask?.cancel()
        undoDismissTask = nil
        pendingUndoAction = nil
    }

    private func visibilityText(isVisible: Bool, canHide: Bool) -> String {
        if !canHide {
            return L("cashflow.category.visibility.always")
        }
        if isVisible {
            return L("cashflow.category.visibility.visible")
        }
        return L("cashflow.category.visibility.hidden")
    }

    private func handleSave(name: String, icon: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch editorMode {
        case .create:
            break
        case .edit(let rawValue):
            guard viewModel.renameCategory(
                rawValue: rawValue,
                kind: kind.categoryKind,
                newName: trimmed,
                newIcon: icon
            ) else { return }
        }

        showEditorSheet = false
    }
}
