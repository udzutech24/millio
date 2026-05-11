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
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                CalendarRangePickerPanel(
                    title: CalendarRangePickerCopy.sheetTitle(locale: locale),
                    subtitle: L("cashflow.custom_period.calendar_hint"),
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
                        accessibilityLabel: L("cashflow.common.dismiss")
                    ) {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                CalendarRangeSheetActionBar(
                    secondaryTitle: L("cashflow.common.reset"),
                    primaryTitle: L("cashflow.custom_period.show"),
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
