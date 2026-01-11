//
//  CashflowView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData
import Charts

struct CashflowView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CashflowViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                CashflowContentView(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = CashflowViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Cashflow Content View

private struct CashflowContentView: View {
    @ObservedObject var viewModel: CashflowViewModel
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Статистика за период
                    periodStatsSection
                    
                    // График
                    chartSection
                    
                    // Кнопки действий
                    actionButtonsSection
                    
                    // Кнопка для открытия истории операций
                    historyButtonSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Кэшфлоу")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { viewModel.state.showTransactionEditor },
            set: { if !$0 { viewModel.handle(.hideTransactionEditor) } }
        )) {
            if let editingTransaction = viewModel.state.editingTransaction {
                CashflowTransactionEditorView(
                    viewModel: viewModel,
                    transaction: editingTransaction
                )
            } else if let creatingType = viewModel.state.creatingTransactionType {
                CashflowTransactionEditorView(
                    viewModel: viewModel,
                    transactionType: creatingType
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showPeriodSelector },
            set: { if !$0 { viewModel.handle(.hidePeriodSelector) } }
        )) {
            CashflowPeriodSelectorView(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showTransactionsHistory },
            set: { if !$0 { viewModel.handle(.hideTransactionsHistory) } }
        )) {
            CashflowTransactionsHistoryView(viewModel: viewModel)
        }
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        
        return LazyVGrid(columns: columns, spacing: 12) {
            // Кнопка Доход
            CashflowActionButton(
                title: "Доход",
                icon: "plus",
                gradientColors: AppColors.incomeGradient
            ) {
                viewModel.handle(.addTransaction(.income))
            }
            
            // Кнопка Расход
            CashflowActionButton(
                title: "Расход",
                icon: "minus",
                gradientColors: AppColors.expenseGradient
            ) {
                viewModel.handle(.addTransaction(.expense))
            }
            
            // Кнопка Перевод
            CashflowActionButton(
                title: "Перевод",
                icon: "arrow.left.arrow.right",
                gradientColors: AppColors.cashflowGradient
            ) {
                viewModel.handle(.addTransaction(.transfer))
            }
            
            // Кнопка Обмен
            CashflowActionButton(
                title: "Обмен",
                icon: "arrow.triangle.2.circlepath.circle.fill",
                gradientColors: AppColors.coursesGradient
            ) {
                viewModel.handle(.addTransaction(.exchange))
            }
        }
    }
    
    // MARK: - Period Stats Section
    
    private var periodStatsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Доходы
                VStack(alignment: .leading, spacing: 8) {
                    Text("Заработано")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatAmount(viewModel.state.totalIncome))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.incomeGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("RUB")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.3))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: AppColors.incomeGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                        }
                )
                
                // Расходы
                VStack(alignment: .leading, spacing: 8) {
                    Text("Потрачено")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatAmount(viewModel.state.totalExpense))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.expenseGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("RUB")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.3))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: AppColors.expenseGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 2
                                )
                        }
                )
            }
            
            // Баланс
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Баланс")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatAmount(viewModel.state.periodBalance))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(
                                viewModel.state.periodBalance >= 0 ?
                                LinearGradient(
                                    colors: AppColors.incomeGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ) :
                                LinearGradient(
                                    colors: AppColors.expenseGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("RUB")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                
                Spacer()
                
                if viewModel.state.periodBalance != 0 {
                    Image(systemName: viewModel.state.periodBalance >= 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            viewModel.state.periodBalance >= 0 ?
                            LinearGradient(
                                colors: AppColors.incomeGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            ) :
                            LinearGradient(
                                colors: AppColors.expenseGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.3))
            )
        }
    }
    
    // MARK: - Chart Section
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Динамика")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                Menu {
                    Button {
                        viewModel.handle(.setChartPeriod(.month))
                    } label: {
                        HStack {
                            Text("Месяц")
                            if viewModel.state.chartPeriod == .month {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button {
                        viewModel.handle(.setChartPeriod(.quarter))
                    } label: {
                        HStack {
                            Text("Квартал")
                            if viewModel.state.chartPeriod == .quarter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button {
                        viewModel.handle(.setChartPeriod(.year))
                    } label: {
                        HStack {
                            Text("Год")
                            if viewModel.state.chartPeriod == .year {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        viewModel.handle(.showPeriodSelector)
                    } label: {
                        HStack {
                            Text("Конкретный месяц")
                            if viewModel.state.chartPeriod == .specificMonth {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button {
                        viewModel.handle(.showPeriodSelector)
                    } label: {
                        HStack {
                            Text("Конкретный квартал")
                            if viewModel.state.chartPeriod == .specificQuarter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Button {
                        viewModel.handle(.showPeriodSelector)
                    } label: {
                        HStack {
                            Text("Конкретный год")
                            if viewModel.state.chartPeriod == .specificYear {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        viewModel.handle(.showPeriodSelector)
                    } label: {
                        HStack {
                            Text("Свой период")
                            if viewModel.state.chartPeriod == .custom {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(getPeriodDisplayName())
                            .font(.system(size: 14, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                }
            }
            
            if viewModel.state.incomeChartData.isEmpty && viewModel.state.expenseChartData.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("Нет данных для отображения")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
            } else {
                Chart {
                    // Доходы - левая полоса
                    BarMark(
                        x: .value("Тип", "Доходы"),
                        y: .value("Сумма", viewModel.state.totalIncome)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.incomeGradient,
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(8)
                    
                    // Расходы - правая полоса
                    BarMark(
                        x: .value("Тип", "Расходы"),
                        y: .value("Сумма", viewModel.state.totalExpense)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.expenseGradient,
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(8)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                            .foregroundStyle(AppColors.textTertiary.opacity(0.3))
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(formatAmount(doubleValue))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let stringValue = value.as(String.self) {
                                Text(stringValue)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                    }
                }
                .chartYAxisLabel("Сумма (RUB)")
                .frame(height: 300)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.3))
                )
            }
        }
    }
    
    // MARK: - History Button Section
    
    private var historyButtonSection: some View {
        Button {
            viewModel.handle(.showTransactionsHistory)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("История операций")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("\(viewModel.state.filteredTransactions.count) операций")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "0.00"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch viewModel.state.chartPeriod {
        case .month, .specificMonth:
            formatter.dateFormat = "dd.MM"
        case .quarter, .specificQuarter:
            formatter.dateFormat = "dd.MM"
        case .year, .specificYear:
            formatter.dateFormat = "MMM"
        case .custom:
            formatter.dateFormat = "dd.MM"
        }
        return formatter.string(from: date)
    }
    
    private func getPeriodDisplayName() -> String {
        switch viewModel.state.chartPeriod {
        case .month:
            return "Месяц"
        case .quarter:
            return "Квартал"
        case .year:
            return "Год"
        case .specificMonth:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: viewModel.state.selectedMonth)
        case .specificQuarter:
            let calendar = Calendar.current
            let month = calendar.component(.month, from: viewModel.state.selectedQuarter)
            let quarter = (month - 1) / 3 + 1
            let year = calendar.component(.year, from: viewModel.state.selectedQuarter)
            return "Q\(quarter) \(year)"
        case .specificYear:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            return formatter.string(from: viewModel.state.selectedYear)
        case .custom:
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yyyy"
            return "\(formatter.string(from: viewModel.state.customStartDate)) - \(formatter.string(from: viewModel.state.customEndDate))"
        }
    }
}

// MARK: - Cashflow Action Button

private struct CashflowActionButton: View {
    let title: String
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors.map { $0.opacity(0.2) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.3))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 2
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

