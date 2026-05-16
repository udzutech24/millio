//
//  CashflowCategoryHelpSheet.swift
//  millio
//

import SwiftUI

/// Тестируемый источник кратких подсказок для экранов "Новый доход/расход".
struct CashflowCategoryHelpContent {
    let title: String
    let notes: [String]

    static func make(for kind: CashflowCategoryTransactionSheetKind) -> CashflowCategoryHelpContent {
        return CashflowCategoryHelpContent(
            title: L("cashflow.operation.help.title"),
            notes: [
                L("cashflow.operation.help.note.currency_first"),
                L("cashflow.operation.help.note.category_month")
            ]
        )
    }
}

struct CashflowCategoryHelpSheet: View {
    let kind: CashflowCategoryTransactionSheetKind
    @Environment(\.dismiss) private var dismiss

    private var content: CashflowCategoryHelpContent {
        CashflowCategoryHelpContent.make(for: kind)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.m) {
                        ForEach(Array(content.notes.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.millioSubheadline)
                                    .foregroundStyle(AppColors.brandPrimary)
                                    .padding(.top, 1)
                                Text(line)
                                    .font(.millioBody)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppSpacing.ml)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(.horizontal, AppSpacing.l)
                    .padding(.top, AppSpacing.m)
                    .padding(.bottom, AppSpacing.xxl)
                }
            }
            .navigationTitle(content.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cashflow.common.close")) {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
