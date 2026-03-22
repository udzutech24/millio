//
//  CashflowCustomPeriodSheetView.swift
//  millio
//
//  Reusable sheet for selecting a custom date range for Cashflow period.
//  Used both from the main Cashflow screen and from the expanded chart.
//

import SwiftUI

struct CashflowCustomPeriodSheetView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Binding var draftStartDate: Date
    @Binding var draftEndDate: Date

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                CalendarRangePickerPanel(
                    title: CalendarRangePickerCopy.sheetTitle(),
                    subtitle: String(localized: "cashflow.custom_period.calendar_hint"),
                    startDate: $draftStartDate,
                    endDate: $draftEndDate,
                    theme: .cashflow
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
                    secondaryTitle: String(localized: "cashflow.common.reset"),
                    primaryTitle: String(localized: "cashflow.custom_period.show"),
                    theme: .cashflow
                ) {
                        viewModel.handle(.resetToDefaultPeriod)
                        dismiss()
                } primaryAction: {
                        applyDraftPeriod()
                        dismiss()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    private func applyDraftPeriod(referenceDate: Date = Date()) {
        let range = CashflowViewModel.clampCustomPeriodRange(
            start: draftStartDate,
            end: draftEndDate,
            referenceDate: referenceDate,
            calendar: .current
        )
        viewModel.handle(.setCustomPeriod(start: range.start, end: range.end))
    }
}
