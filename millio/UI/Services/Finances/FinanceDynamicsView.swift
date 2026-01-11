//
//  FinanceDynamicsView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData
import Charts

struct FinanceDynamicsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @ObservedObject var financeViewModel: FinanceViewModel
    @State private var dynamicsViewModel: FinanceDynamicsViewModel?
    @State private var showSubscriptionSheet = false
    
    var body: some View {
        Group {
            if let dynamicsViewModel = dynamicsViewModel {
                FinanceDynamicsContentView(
                    viewModel: dynamicsViewModel,
                    appState: appState,
                    showSubscriptionSheet: $showSubscriptionSheet
                )
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if dynamicsViewModel == nil {
                dynamicsViewModel = FinanceDynamicsViewModel(
                    modelContext: modelContext,
                    financeViewModel: financeViewModel
                )
                dynamicsViewModel?.handle(.loadData)
            }
        }
    }
}

// MARK: - Finance Dynamics Content View

private struct FinanceDynamicsContentView: View {
    @ObservedObject var viewModel: FinanceDynamicsViewModel
    @Bindable var appState: AppState
    @Binding var showSubscriptionSheet: Bool
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Фильтры
                    filtersSection
                    
                    // График
                    chartSection
                    
                    // Кнопка для открытия деталей
                    if !viewModel.state.chartData.isEmpty {
                        detailsButton
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Динамика")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { viewModel.state.showDetailsSheet },
            set: { if !$0 { viewModel.handle(.hideDetailsSheet) } }
        )) {
            FinanceDynamicsDetailsView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSubscriptionSheet) {
            NavigationStack {
                SubscriptionView()
            }
        }
    }
    
    // MARK: - Filters Section
    
    private var filtersSection: some View {
        VStack(spacing: 16) {
            // Период
            periodPicker
            
            // Валюта
            currencyPicker
            
            // Группы
            groupsFilter
            
            // Счета (показываем только если выбраны группы)
            if !viewModel.state.selectedGroupIDs.isEmpty {
                accountsFilter
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.3))
        )
    }
    
    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Период")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            
            Picker("Период", selection: Binding(
                get: { viewModel.state.period },
                set: { viewModel.handle(.setPeriod($0)) }
            )) {
                ForEach(DynamicsPeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var currencyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Валюта")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            
            if viewModel.state.availableCurrencies.isEmpty {
                HStack {
                    Text("Загрузка...")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(AppColors.textTertiary)
                }
            } else {
                Menu {
                    ForEach(viewModel.state.availableCurrencies, id: \.self) { currency in
                        Button {
                            viewModel.handle(.setDisplayCurrency(currency))
                        } label: {
                            HStack {
                                Text(currency)
                                if currency == viewModel.state.displayCurrency {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(viewModel.state.displayCurrency)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                }
            }
        }
    }
    
    private var groupsFilter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Группы")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            
            if viewModel.state.groups.isEmpty {
                Text("Нет групп")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Кнопка "Все"
                        FilterChip(
                            title: "Все",
                            isSelected: viewModel.state.selectedGroupIDs.isEmpty,
                            color: AppColors.financesGradient
                        ) {
                            viewModel.handle(.selectGroups([]))
                        }
                        
                        // Кнопки групп
                        ForEach(viewModel.state.groups) { group in
                            FilterChip(
                                title: group.name,
                                isSelected: viewModel.state.selectedGroupIDs.contains(group.groupUniqueID),
                                color: [group.color]
                            ) {
                                viewModel.handle(.toggleGroup(group.groupUniqueID))
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    
    private var accountsFilter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Счета")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            
            let accounts = viewModel.getAccountsForSelectedGroups()
            
            if accounts.isEmpty {
                Text("Нет счетов")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Кнопка "Все"
                        FilterChip(
                            title: "Все",
                            isSelected: viewModel.state.selectedAccountIDs.isEmpty,
                            color: AppColors.financesGradient
                        ) {
                            viewModel.handle(.selectAccounts([]))
                        }
                        
                        // Кнопки счетов
                        ForEach(accounts) { account in
                            if let accountInfo = viewModel.financeViewModel.getAccountInfo(account: account) {
                                FilterChip(
                                    title: accountInfo.name,
                                    isSelected: viewModel.state.selectedAccountIDs.contains(account.accountUniqueID),
                                    color: AppColors.financesGradient
                                ) {
                                    viewModel.handle(.toggleAccount(account.accountUniqueID))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }
    
    // MARK: - Chart Section
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("График")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            
            if !appState.isPro {
                // Блокировка графика для бесплатной версии
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("График доступен в PRO версии")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Оформите подписку для доступа к расширенной аналитике")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        showSubscriptionSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 14))
                            Text("Оформить PRO")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Capsule()
                                        .stroke(
                                            LinearGradient(
                                                colors: AppColors.incomeGradient,
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
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .padding(24)
            } else if viewModel.state.isLoading {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
            } else if viewModel.state.chartData.isEmpty {
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
                Chart(viewModel.state.chartData) { dataPoint in
                    LineMark(
                        x: .value("Дата", dataPoint.date, unit: .day),
                        y: .value("Сумма", dataPoint.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    
                    AreaMark(
                        x: .value("Дата", dataPoint.date, unit: .day),
                        y: .value("Сумма", dataPoint.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient.map { $0.opacity(0.3) },
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    PointMark(
                        x: .value("Дата", dataPoint.date, unit: .day),
                        y: .value("Сумма", dataPoint.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .symbolSize(60)
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
                .chartYAxisLabel("Сумма (\(viewModel.state.displayCurrency))")
                .frame(height: 300)
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.3))
                )
            }
        }
    }
    
    // MARK: - Details Button
    
    private var detailsButton: some View {
        Button {
            viewModel.handle(.showDetailsSheet)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Детали")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("\(viewModel.state.chartData.count) записей")
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
        let calendar = Calendar.current
        
        switch viewModel.state.period {
        case .day:
            formatter.dateFormat = "HH:mm"
        case .week:
            formatter.dateFormat = "dd.MM"
        case .month:
            formatter.dateFormat = "dd.MM"
        case .year:
            formatter.dateFormat = "MMM"
        }
        
        return formatter.string(from: date)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let color: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : AppColors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isSelected {
                            LinearGradient(
                                colors: color,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        } else {
                            Color.white.opacity(0.1)
                        }
                    }
                )
                .clipShape(Capsule())
        }
    }
}
