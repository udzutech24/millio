//
//  FinanceDynamicsPeriodSelectorView.swift
//  millio
//
//  Legacy wrapper kept for project compatibility.
//  Runtime Finance Dynamics uses the shared custom-period sheet in `FinanceDynamicsView`,
//  and this view now mirrors the same Apple-like range selection flow.
//

import SwiftUI

struct FinanceDynamicsPeriodSelectorView: View {
    @ObservedObject var viewModel: FinanceDynamicsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @State private var draftStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var draftEndDate: Date = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                CalendarRangePickerPanel(
                    title: CalendarRangePickerCopy.sheetTitle(locale: locale),
                    subtitle: String(localized: "finances.dynamics.custom_period.subtitle"),
                    startDate: $draftStartDate,
                    endDate: $draftEndDate,
                    theme: .finances
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ToolbarGlassIconButton(
                        systemName: "xmark",
                        accessibilityLabel: String(localized: "cashflow.common.dismiss")
                    ) {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                CalendarRangeSheetActionBar(
                    secondaryTitle: String(localized: "finances.common.reset"),
                    primaryTitle: String(localized: "finances.common.apply"),
                    theme: .finances
                ) {
                    resetToDefaultPeriod()
                    dismiss()
                } primaryAction: {
                    applyPeriod()
                }
            }
            .onAppear {
                if let customPeriod = viewModel.state.customPeriod {
                    draftStartDate = customPeriod.start
                    draftEndDate = customPeriod.end
                } else {
                    let defaultEnd = Date()
                    let defaultStart = Calendar.current.date(byAdding: .day, value: -30, to: defaultEnd) ?? defaultEnd
                    draftStartDate = defaultStart
                    draftEndDate = defaultEnd
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func resetToDefaultPeriod() {
        viewModel.handle(.setPeriod(.month))
    }

    private func applyPeriod() {
        viewModel.handle(.setCustomPeriod(start: draftStartDate, end: draftEndDate))
        dismiss()
    }
}
