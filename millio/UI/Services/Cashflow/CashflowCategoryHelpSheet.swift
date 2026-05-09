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
            title: String(localized: "cashflow.operation.help.title"),
            notes: [
                String(localized: "cashflow.operation.help.note.currency_first"),
                String(localized: "cashflow.operation.help.note.category_month")
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
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(content.notes.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.brandPrimary)
                                    .padding(.top, 1)
                                Text(line)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
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
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(content.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "cashflow.common.close")) {
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
