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
                    // Кнопки действий
                    actionButtonsSection
                    
                    // График
                    chartSection
                    
                    // История операций
                    transactionsHistorySection
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
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        HStack(spacing: 16) {
            // Кнопка Доход
            ActionButton(
                title: "Доход",
                icon: "plus",
                gradientColors: AppColors.incomeGradient
            ) {
                viewModel.handle(.addTransaction(.income))
            }
            
            // Кнопка Расход
            ActionButton(
                title: "Расход",
                icon: "minus",
                gradientColors: AppColors.expenseGradient
            ) {
                viewModel.handle(.addTransaction(.expense))
            }
            
            // Кнопка Перевод
            ActionButton(
                title: "Перевод",
                icon: "arrow.left.arrow.right",
                gradientColors: AppColors.cashflowGradient
            ) {
                viewModel.handle(.addTransaction(.transfer))
            }
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
                
                Picker("Период", selection: Binding(
                    get: { viewModel.state.chartPeriod },
                    set: { viewModel.handle(.setChartPeriod($0)) }
                )) {
                    ForEach(ChartPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
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
                    // Доходы
                    ForEach(viewModel.state.incomeChartData) { dataPoint in
                        LineMark(
                            x: .value("Дата", dataPoint.date, unit: .day),
                            y: .value("Доходы", dataPoint.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.incomeGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                        
                        AreaMark(
                            x: .value("Дата", dataPoint.date, unit: .day),
                            y: .value("Доходы", dataPoint.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.incomeGradient.map { $0.opacity(0.3) },
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                    
                    // Расходы
                    ForEach(viewModel.state.expenseChartData) { dataPoint in
                        LineMark(
                            x: .value("Дата", dataPoint.date, unit: .day),
                            y: .value("Расходы", dataPoint.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.expenseGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                        
                        AreaMark(
                            x: .value("Дата", dataPoint.date, unit: .day),
                            y: .value("Расходы", dataPoint.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.expenseGradient.map { $0.opacity(0.3) },
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
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
                        AxisGridLine()
                            .foregroundStyle(AppColors.textTertiary.opacity(0.2))
                        AxisValueLabel {
                            if let dateValue = value.as(Date.self) {
                                Text(formatDate(dateValue))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
                .chartXAxisLabel("Дата")
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
    
    // MARK: - Transactions History Section
    
    private var transactionsHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("История операций")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            
            if viewModel.state.filteredTransactions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("Нет операций")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.state.filteredTransactions) { transaction in
                        CashflowTransactionRow(
                            transaction: transaction,
                            viewModel: viewModel
                        )
                    }
                }
            }
        }
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
        case .month:
            formatter.dateFormat = "dd.MM"
        case .quarter:
            formatter.dateFormat = "dd.MM"
        case .year:
            formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }
}

// MARK: - Cashflow Transaction Row

private struct CashflowTransactionRow: View {
    let transaction: CashflowTransaction
    @ObservedObject var viewModel: CashflowViewModel
    
    var body: some View {
        Button {
            viewModel.handle(.editTransaction(transaction))
        } label: {
            HStack(spacing: 16) {
                // Иконка типа транзакции
                Image(systemName: transaction.transactionType.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: getGradientColors(),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    // Категория или тип
                    Text(getCategoryName())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    // Дата
                    Text(formatDate(transaction.transactionDate))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    // Карта или перевод
                    if let cardName = getCardName() {
                        Text(cardName)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Сумма
                    Text(formatAmount(transaction.amount))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            transaction.transactionType == .expense ? AppColors.error : AppColors.textPrimary
                        )
                    
                    // Валюта
                    Text(transaction.currency)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                viewModel.handle(.deleteTransaction(transaction))
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }
    
    private func getGradientColors() -> [Color] {
        switch transaction.transactionType {
        case .income:
            return AppColors.incomeGradient
        case .expense:
            return AppColors.expenseGradient
        case .transfer:
            return AppColors.cashflowGradient
        }
    }
    
    private func getCategoryName() -> String {
        switch transaction.transactionType {
        case .income:
            return transaction.incomeCategory?.displayName ?? "Доход"
        case .expense:
            return transaction.expenseCategory?.displayName ?? "Расход"
        case .transfer:
            return "Перевод"
        }
    }
    
    private func getCardName() -> String? {
        switch transaction.transactionType {
        case .income, .expense:
            if let cardID = transaction.cardID,
               let card = viewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID }) {
                return card.name
            }
            return nil
            
        case .transfer:
            if let fromCardID = transaction.cardID,
               let toCardID = transaction.toCardID,
               let fromCard = viewModel.state.availableCards.first(where: { $0.cardUniqueID == fromCardID }),
               let toCard = viewModel.state.availableCards.first(where: { $0.cardUniqueID == toCardID }) {
                return "\(fromCard.name) → \(toCard.name)"
            }
            return nil
        }
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
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }
}
