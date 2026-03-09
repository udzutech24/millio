//
//  CashflowPeriodSelectorView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI

/// Legacy selector for `ChartPeriod`.
/// Сейчас основной экран Cashflow использует только range-выбор через `CalendarRangeMonthView`
/// (см. `CashflowView.customPeriodSheet`). Оставлено для совместимости, пока проект не
/// отчищен от ссылок в `.xcodeproj`.
struct CashflowPeriodSelectorView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPeriodType: PeriodType = .month
    @State private var selectedMonth: Date = Date()
    @State private var selectedQuarter: Date = Date()
    @State private var selectedYear: Date = Date()
    @State private var customStartDate: Date = CashflowViewModel.defaultPeriodRange(referenceDate: Date()).start
    @State private var customEndDate: Date = CashflowViewModel.defaultPeriodRange(referenceDate: Date()).end
    
    enum PeriodType {
        case month
        case quarter
        case year
        case custom
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                Form {
                    Section {
                        Picker("Period type", selection: $selectedPeriodType) {
                            Text("Month").tag(PeriodType.month)
                            Text("Quarter").tag(PeriodType.quarter)
                            Text("Year").tag(PeriodType.year)
                            Text("Custom period").tag(PeriodType.custom)
                        }
                        .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Period type")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    if selectedPeriodType == .month {
                        Section {
                            DatePicker("Month", selection: $selectedMonth, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .foregroundStyle(AppColors.textPrimary)
                        } header: {
                            Text("Select month")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    } else if selectedPeriodType == .quarter {
                        Section {
                            DatePicker("Quarter", selection: $selectedQuarter, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .foregroundStyle(AppColors.textPrimary)
                        } header: {
                            Text("Select quarter")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    } else if selectedPeriodType == .year {
                        Section {
                            DatePicker("Year", selection: $selectedYear, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .foregroundStyle(AppColors.textPrimary)
                        } header: {
                            Text("Select year")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    } else if selectedPeriodType == .custom {
                        Section {
                            CalendarRangeMonthView(startDate: $customStartDate, endDate: $customEndDate)
                        } header: {
                            Text("Select period")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Period selection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        applyPeriod()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cashflowGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
            .onAppear {
                // Инициализируем значения из состояния
                switch viewModel.state.chartPeriod {
                case .specificMonth:
                    selectedPeriodType = .month
                    selectedMonth = viewModel.state.selectedMonth
                case .specificQuarter:
                    selectedPeriodType = .quarter
                    selectedQuarter = viewModel.state.selectedQuarter
                case .specificYear:
                    selectedPeriodType = .year
                    selectedYear = viewModel.state.selectedYear
                case .custom:
                    selectedPeriodType = .custom
                    customStartDate = viewModel.state.customStartDate
                    customEndDate = viewModel.state.customEndDate
                default:
                    break
                }
            }
        }
    }
    
    private func applyPeriod() {
        switch selectedPeriodType {
        case .month:
            viewModel.handle(.setSelectedMonth(selectedMonth))
        case .quarter:
            viewModel.handle(.setSelectedQuarter(selectedQuarter))
        case .year:
            viewModel.handle(.setSelectedYear(selectedYear))
        case .custom:
            viewModel.handle(.setCustomPeriod(start: customStartDate, end: customEndDate))
        }
        dismiss()
    }
}
