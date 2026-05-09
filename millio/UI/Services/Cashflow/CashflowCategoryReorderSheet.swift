//
//  CashflowCategoryReorderSheet.swift
//  millio
//

import SwiftUI

struct CashflowCategoryReorderSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let kind: CashflowCategoryKind
    @Environment(\.dismiss) private var dismiss

    @State private var items: [CashflowCategoryOption] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { option in
                    HStack(spacing: 12) {
                        CashflowCategoryIconView(
                            icon: option.icon,
                            fontSize: 18,
                            fontWeight: .regular,
                            tint: AnyShapeStyle(AppColors.textPrimary)
                        )
                        Text(option.displayName)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                    }
                    .listRowBackground(Color(white: 0.12))
                }
                .onMove { source, destination in
                    items.move(fromOffsets: source, toOffset: destination)
                    viewModel.setCategoryOrder(items.map(\.rawValue), for: kind)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .environment(\.editMode, .constant(.active))
            .navigationTitle(
                kind == .expense
                ? String(localized: "cashflow.category.reorder.title.expense", defaultValue: "Expense order")
                : String(localized: "cashflow.category.reorder.title.income", defaultValue: "Income order")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "cashflow.category.reorder.reset", defaultValue: "Reset")) {
                        viewModel.clearCategoryOrder(for: kind)
                        items = viewModel.orderedCategoryOptions(for: kind)
                    }
                    .foregroundStyle(AppColors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "cashflow.common.done", defaultValue: "Done")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            items = viewModel.orderedCategoryOptions(for: kind)
        }
    }
}
