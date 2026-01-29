//
//  CashflowPeriodSelectorView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI

struct CashflowPeriodSelectorView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedPeriodType: PeriodType = .month
    @State private var selectedMonth: Date = Date()
    @State private var selectedQuarter: Date = Date()
    @State private var selectedYear: Date = Date()
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()
    
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
                        Picker("Тип периода", selection: $selectedPeriodType) {
                            Text("Месяц").tag(PeriodType.month)
                            Text("Квартал").tag(PeriodType.quarter)
                            Text("Год").tag(PeriodType.year)
                            Text("Свой период").tag(PeriodType.custom)
                        }
                        .foregroundStyle(AppColors.textPrimary)
                    } header: {
                        Text("Тип периода")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    
                    if selectedPeriodType == .month {
                        Section {
                            DatePicker("Месяц", selection: $selectedMonth, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .foregroundStyle(AppColors.textPrimary)
                        } header: {
                            Text("Выберите месяц")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    } else if selectedPeriodType == .quarter {
                        Section {
                            DatePicker("Квартал", selection: $selectedQuarter, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .foregroundStyle(AppColors.textPrimary)
                        } header: {
                            Text("Выберите квартал")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    } else if selectedPeriodType == .year {
                        Section {
                            DatePicker("Год", selection: $selectedYear, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .foregroundStyle(AppColors.textPrimary)
                        } header: {
                            Text("Выберите год")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    } else if selectedPeriodType == .custom {
                        Section {
                            CalendarRangeMonthView(startDate: $customStartDate, endDate: $customEndDate)
                        } header: {
                            Text("Выберите период")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Выбор периода")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Применить") {
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
