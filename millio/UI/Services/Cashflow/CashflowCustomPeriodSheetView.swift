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

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        let sameYear = Calendar.current.component(.year, from: draftStartDate)
                            == Calendar.current.component(.year, from: draftEndDate)
                        let startFormat: Date.FormatStyle = sameYear
                            ? .dateTime.day().month(.abbreviated)
                            : .dateTime.day().month(.abbreviated).year()
                        let endFormat: Date.FormatStyle = .dateTime.day().month(.abbreviated).year()

                        Text(
                            String(
                                format: String(localized: "cashflow.history.date_range_format"),
                                min(draftStartDate, draftEndDate).formatted(startFormat),
                                max(draftStartDate, draftEndDate).formatted(endFormat)
                            )
                        )
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary)

                        Text("Select start and end dates on the calendar")
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top, 4)

                    CalendarRangeMonthView(startDate: $draftStartDate, endDate: $draftEndDate)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                let gradient = LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.02, blue: 0.12),
                        Color(red: 0.02, green: 0.12, blue: 0.10)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(spacing: 12) {
                    Button {
                        viewModel.handle(.resetToDefaultPeriod)
                        dismiss()
                    } label: {
                        Text("Reset")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
                            )
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        applyDraftPeriod()
                        dismiss()
                    } label: {
                        Text("Show")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(gradient)
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                LinearGradient(
                                                    colors: AppColors.cashflowGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                            )
                            .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
