//
//  CashflowCategoryUndoBanner.swift
//  millio
//

import SwiftUI

struct CashflowCategoryUndoBanner: View {
    let action: CashflowCategoryMutationUndoAction
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: 8)

            Button(L("Undo")) {
                onUndo()
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AppColors.brandPrimary)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var title: String {
        action.isArchive
            ? String(
                localized: "cashflow.category.undo.archive.title",
                defaultValue: "Category archived",
                comment: "Undo banner title after archiving a category"
            )
            : String(
                localized: "cashflow.category.undo.delete.title",
                defaultValue: "Category deleted",
                comment: "Undo banner title after deleting a category"
            )
    }

    private var subtitle: String {
        let targetName = action.targetOption.displayName
        if action.isArchive {
            return String(
                localized: "cashflow.category.undo.archive.subtitle",
                defaultValue: "Linked data moved to %@.",
                comment: "Undo banner subtitle after archiving a category"
            ).replacingOccurrences(of: "%@", with: targetName)
        }

        return String(
            localized: "cashflow.category.undo.delete.subtitle",
            defaultValue: "Deleted category data moved to %@.",
            comment: "Undo banner subtitle after deleting a category"
        ).replacingOccurrences(of: "%@", with: targetName)
    }
}
