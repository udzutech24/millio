//
//  FinanceDynamicsPeriodSelectorView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI

struct FinanceDynamicsPeriodSelectorView: View {
    @ObservedObject var viewModel: FinanceDynamicsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()
    @State private var selectingStart: Bool = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Информация о выбранных датах
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("finances.dynamics.period.start")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(AppColors.textSecondary)
                                    
                                    Button {
                                        selectingStart = true
                                    } label: {
                                        HStack {
                                            Text(formatDate(customStartDate))
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(AppColors.textPrimary)
                                            Spacer()
                                            if selectingStart {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(
                                                        LinearGradient(
                                                            colors: AppColors.financesGradient,
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(selectingStart ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                                        )
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("finances.dynamics.period.end")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(AppColors.textSecondary)
                                    
                                    Button {
                                        selectingStart = false
                                    } label: {
                                        HStack {
                                            Text(formatDate(customEndDate))
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(AppColors.textPrimary)
                                            Spacer()
                                            if !selectingStart {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(
                                                        LinearGradient(
                                                            colors: AppColors.financesGradient,
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(!selectingStart ? Color.white.opacity(0.2) : Color.white.opacity(0.1))
                                        )
                                    }
                                }
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.black.opacity(0.3))
                        )
                        
                        // Один календарь для выбора даты
                        datePickerSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("finances.dynamics.period.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("finances.common.cancel") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("finances.common.apply") {
                        applyPeriod()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
            .onAppear {
                // Инициализируем значения из состояния, если есть кастомный период
                if let customPeriod = viewModel.state.customPeriod {
                    customStartDate = customPeriod.start
                    customEndDate = customPeriod.end
                } else {
                    // Используем значения по умолчанию (последние 30 дней)
                    let calendar = Calendar.current
                    customStartDate = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                    customEndDate = Date()
                }
            }
        }
    }
    
    // MARK: - Date Picker Section
    
    private var datePickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectingStart
                 ? String(localized: "finances.dynamics.period.choose_start")
                 : String(localized: "finances.dynamics.period.choose_end"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 20)
            
            datePicker
                .datePickerStyle(.graphical)
                .foregroundStyle(AppColors.textPrimary)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.3))
                )
        }
    }
    
    private var datePicker: some View {
        Group {
            if selectingStart {
                DatePicker(
                    "",
                    selection: $customStartDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .onChange(of: customStartDate) { _, newDate in
                    handleStartDateSelection(newDate)
                }
            } else {
                DatePicker(
                    "",
                    selection: $customEndDate,
                    in: customStartDate...Date(),
                    displayedComponents: .date
                )
                .onChange(of: customEndDate) { _, newDate in
                    handleEndDateSelection(newDate)
                }
            }
        }
    }
    
    private func handleStartDateSelection(_ newDate: Date) {
        customStartDate = newDate
        // Автоматически устанавливаем конечную дату на следующий день от выбранной начальной
        let calendar = Calendar.current
        let today = Date()
        if let nextDay = calendar.date(byAdding: .day, value: 1, to: customStartDate) {
            // Убеждаемся, что конечная дата не позже сегодняшнего дня
            customEndDate = min(nextDay, today)
        }
        // Автоматически переключаемся на выбор конца
        selectingStart = false
    }
    
    private func handleEndDateSelection(_ newDate: Date) {
        // Ограничиваем выбор конечной даты сегодняшним днем
        let today = Date()
        customEndDate = min(newDate, today)
        // Автоматически переключаемся на выбор начала, если конечная дата раньше начальной
        if customEndDate < customStartDate {
            selectingStart = true
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
    
    private func applyPeriod() {
        // Убеждаемся, что начальная дата не позже конечной
        let startDate = min(customStartDate, customEndDate)
        let endDate = max(customStartDate, customEndDate)
        
        viewModel.handle(.setCustomPeriod(start: startDate, end: endDate))
        dismiss()
    }
}
