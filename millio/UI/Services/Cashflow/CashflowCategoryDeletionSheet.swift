//
//  CashflowCategoryDeletionSheet.swift
//  millio
//

import SwiftUI

struct CashflowCategoryDeletionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let preview: CashflowCategoryDeletionPreview
    let onDelete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTargetRaw: String

    init(
        viewModel: CashflowViewModel,
        preview: CashflowCategoryDeletionPreview,
        onDelete: @escaping (String) -> Void
    ) {
        self.viewModel = viewModel
        self.preview = preview
        self.onDelete = onDelete
        _selectedTargetRaw = State(initialValue: preview.suggestedTargetOption.rawValue)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    sourceCategoryRow
                } header: {
                    Text(
                        String(
                            localized: "cashflow.category.delete.review.header",
                            defaultValue: "Delete review",
                            comment: "Header for delete category review section"
                        )
                    )
                } footer: {
                    Text(impactSummaryText)
                }

                Section {
                    Picker(
                        String(
                            localized: "cashflow.category.delete.target.title",
                            defaultValue: "Move linked data to",
                            comment: "Picker title for category delete target"
                        ),
                        selection: $selectedTargetRaw
                    ) {
                        ForEach(preview.availableTargetOptions) { option in
                            HStack(spacing: 10) {
                                CashflowCategoryIconView(
                                    icon: option.icon,
                                    fontSize: 16,
                                    fontWeight: .semibold,
                                    tint: AnyShapeStyle(AppColors.textPrimary)
                                )
                                Text(option.displayName)
                            }
                            .tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text(
                        String(
                            localized: "cashflow.category.delete.target.footer",
                            defaultValue: "Transactions, budget limits, pins, and merchant mappings will be remapped to the selected category.",
                            comment: "Footer explaining what is remapped during category deletion"
                        )
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(GradientBackground())
            .navigationTitle(
                destructiveActionTitle
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cashflow.common.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        destructiveConfirmTitle,
                        role: .destructive
                    ) {
                        onDelete(selectedTargetRaw)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var sourceCategoryRow: some View {
        HStack(spacing: 12) {
            CashflowCategoryIconView(
                icon: preview.sourceOption.icon,
                fontSize: 20,
                fontWeight: .semibold,
                tint: AnyShapeStyle(AppColors.textPrimary)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(preview.sourceOption.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(categoryTypeText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()
        }
        .listRowBackground(Color.white.opacity(0.04))
    }

    private var categoryTypeText: String {
        if preview.sourceOption.isCustom {
            return String(
                localized: "cashflow.category.delete.kind.custom",
                defaultValue: "Custom category",
                comment: "Delete category subtitle for custom category"
            )
        }

        return String(
            localized: "cashflow.category.delete.kind.system",
            defaultValue: "System category will be hidden after migration",
            comment: "Delete category subtitle for system category"
        )
    }

    private var destructiveActionTitle: String {
        if preview.sourceOption.isCustom {
            return String(
                localized: "cashflow.category.actions.delete",
                defaultValue: "Delete",
                comment: "Delete category action title"
            )
        }

        return String(
            localized: "cashflow.category.actions.archive",
            defaultValue: "Archive",
            comment: "Archive system category action title"
        )
    }

    private var destructiveConfirmTitle: String {
        if preview.sourceOption.isCustom {
            return String(
                localized: "cashflow.category.delete.confirm",
                defaultValue: "Delete category",
                comment: "Confirm button title for category delete flow"
            )
        }

        return String(
            localized: "cashflow.category.archive.confirm",
            defaultValue: "Archive category",
            comment: "Confirm button title for system category archive flow"
        )
    }

    private var impactSummaryText: String {
        let transactionText = String.localizedStringWithFormat(
            String(
                localized: "cashflow.category.delete.transactions.summary",
                defaultValue: "%d linked transactions",
                comment: "Summary of linked transactions for category deletion"
            ),
            preview.linkedTransactionCount
        )
        let budgetText = String.localizedStringWithFormat(
            String(
                localized: "cashflow.category.delete.budgets.summary",
                defaultValue: "%d linked budget limits",
                comment: "Summary of linked budget limits for category deletion"
            ),
            preview.linkedBudgetLimitCount
        )
        let totalsText = preview.totalsByCurrency.isEmpty
            ? String(
                localized: "cashflow.category.delete.amounts.empty",
                defaultValue: "No transaction amounts linked to this category.",
                comment: "Delete category summary when there are no linked transaction amounts"
            )
            : preview.totalsByCurrency
                .map { "\($0.amount.formatted(.number.precision(.fractionLength(0...2)))) \($0.currency)" }
                .joined(separator: ", ")

        return [transactionText, budgetText, totalsText].joined(separator: " • ")
    }
}
