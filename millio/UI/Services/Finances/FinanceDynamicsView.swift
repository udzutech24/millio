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
    
    /// ID группы для предустановки фильтров (опционально)
    var initialGroupID: String? = nil
    
    /// Валюта группы для предустановки (опционально)
    var initialGroupCurrency: String? = nil
    
    /// ID счета для предустановки фильтров (опционально)
    var initialAccountID: String? = nil
    
    /// Валюта счета для предустановки (опционально)
    var initialAccountCurrency: String? = nil
    
    /// Нужно ли оборачивать в NavigationStack (для sheet'ов нужен, для navigationDestination - нет)
    var wrapInNavigationStack: Bool = true
    
    var body: some View {
        let content = Group {
            if let dynamicsViewModel = dynamicsViewModel {
                FinanceDynamicsContentView(
                    viewModel: dynamicsViewModel,
                    appState: appState,
                    showSubscriptionSheet: $showSubscriptionSheet,
                    financeViewModel: financeViewModel,
                    initialAccountID: initialAccountID
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
                    financeViewModel: financeViewModel,
                    initialGroupID: initialGroupID,
                    initialGroupCurrency: initialGroupCurrency,
                    initialAccountID: initialAccountID,
                    initialAccountCurrency: initialAccountCurrency
                )
                dynamicsViewModel?.handle(.loadData)
            } else {
                // Обновляем данные при возврате на экран
                dynamicsViewModel?.handle(.loadData)
            }
        }
        .onChange(of: financeViewModel.state.availableCards.count) { _, _ in
            // Обновляем данные при изменении списка карт
            dynamicsViewModel?.handle(.loadData)
        }
        
        if wrapInNavigationStack {
            NavigationStack {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Finance Dynamics Content View

private struct FinanceDynamicsContentView: View {
    @ObservedObject var viewModel: FinanceDynamicsViewModel
    @Bindable var appState: AppState
    @Binding var showSubscriptionSheet: Bool
    @ObservedObject var financeViewModel: FinanceViewModel
    var initialAccountID: String? = nil
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Верхняя панель с балансом и дельтой
                    topPanel
                    
                    // График
                    chartSection
                    
                    // Список динамики
                    dynamicsList
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Динамика")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { viewModel.state.showFilterSheet },
            set: { if !$0 { viewModel.handle(.hideFilterSheet) } }
        )) {
            FinanceDynamicsFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showPeriodSelector },
            set: { if !$0 { viewModel.handle(.hidePeriodSelector) } }
        )) {
            FinanceDynamicsPeriodSelectorView(viewModel: viewModel)
        }
        .sheet(isPresented: $showSubscriptionSheet) {
            NavigationStack {
                SubscriptionView()
            }
        }
        .sheet(isPresented: Binding(
            get: { financeViewModel.state.showEditCardSheet || financeViewModel.state.showEditCreditSheet || financeViewModel.state.showEditInvestmentSheet },
            set: { if !$0 {
                if financeViewModel.state.showEditCardSheet {
                    financeViewModel.handle(.hideEditCardSheet)
                }
                if financeViewModel.state.showEditCreditSheet {
                    financeViewModel.handle(.hideEditCreditSheet)
                }
                if financeViewModel.state.showEditInvestmentSheet {
                    financeViewModel.handle(.hideEditInvestmentSheet)
                }
            } }
        )) {
            if let cardID = financeViewModel.state.editingCardID,
               let card = financeViewModel.state.availableCards.first(where: { $0.cardUniqueID == cardID }) {
                FinanceEditCardView(card: card, viewModel: financeViewModel)
            } else if let creditID = financeViewModel.state.editingCreditID,
                      let credit = financeViewModel.state.availableCredits.first(where: { $0.creditUniqueID == creditID }) {
                FinanceEditCreditView(credit: credit, viewModel: financeViewModel)
            } else if let investmentID = financeViewModel.state.editingInvestmentID,
                      let investment = financeViewModel.state.availableInvestments.first(where: { $0.investmentUniqueID == investmentID }) {
                FinanceEditInvestmentView(investment: investment, viewModel: financeViewModel)
            }
        }
    }
    
    // MARK: - Filter Sheet View
    
    private struct FinanceDynamicsFilterSheet: View {
        @ObservedObject var viewModel: FinanceDynamicsViewModel
        @Environment(\.dismiss) private var dismiss
        
        var body: some View {
            NavigationStack {
                ZStack {
                    GradientBackground()
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            // Валюта
                            currencyPicker
                            
                            // Фильтр групп (скрываем в режиме одной группы или одного счета)
                            if !viewModel.state.isSingleGroupMode && !viewModel.state.isSingleAccountMode {
                                groupsFilterSection
                            }
                            
                            // Фильтр счетов (скрываем в режиме одного счета, показываем если выбраны группы или в режиме одной группы)
                            if !viewModel.state.isSingleAccountMode && (!viewModel.state.selectedGroupIDs.isEmpty || viewModel.state.isSingleGroupMode) {
                                accountsFilterSection
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                }
                .navigationTitle("Фильтры")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Готово") {
                            dismiss()
                        }
                        .foregroundStyle(AppColors.textPrimary)
                    }
                }
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
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.3))
            )
        }
        
        private var groupsFilterSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Группы")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Spacer()
                    
                    // Кнопки управления
                    HStack(spacing: 12) {
                        Button {
                            viewModel.handle(.selectAllGroups)
                        } label: {
                            Text("Все")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        
                        Button {
                            viewModel.handle(.deselectAllGroups)
                        } label: {
                            Text("Снять")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                
                if viewModel.state.groups.isEmpty {
                    Text("Нет групп")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 12) {
                        ForEach(viewModel.state.groups) { group in
                            let groupAccounts = group.accounts ?? []
                            
                            // Показываем группу только если в ней есть счета или выбраны все счета
                            if !groupAccounts.isEmpty || viewModel.state.selectedAccountIDs.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Button {
                                            viewModel.handle(.toggleGroup(group.groupUniqueID))
                                        } label: {
                                            HStack {
                                                Circle()
                                                    .fill(group.color)
                                                    .frame(width: 12, height: 12)
                                                
                                                Text(group.name)
                                                    .font(.system(size: 16, weight: .medium))
                                                    .foregroundStyle(AppColors.textPrimary)
                                                
                                                Spacer()
                                                
                                                Image(systemName: viewModel.state.selectedGroupIDs.contains(group.groupUniqueID) ? "checkmark.circle.fill" : "circle")
                                                    .font(.system(size: 20))
                                                    .foregroundStyle(viewModel.state.selectedGroupIDs.contains(group.groupUniqueID) ? Color.green : AppColors.textTertiary)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    // Показываем счета группы, если группа выбрана
                                    if viewModel.state.selectedGroupIDs.contains(group.groupUniqueID) || viewModel.state.selectedGroupIDs.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text("Счета")
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(AppColors.textSecondary)
                                                
                                                Spacer()
                                                
                                                HStack(spacing: 12) {
                                                    Button {
                                                        // Выбрать все счета группы
                                                        let allAccountIDs = Set(groupAccounts.map { $0.accountUniqueID })
                                                        let currentSelected = viewModel.state.selectedAccountIDs
                                                        let newSelected = currentSelected.union(allAccountIDs)
                                                        viewModel.handle(.selectAccounts(newSelected))
                                                    } label: {
                                                        Text("Все")
                                                            .font(.system(size: 12, weight: .medium))
                                                            .foregroundStyle(AppColors.textSecondary)
                                                    }
                                                    
                                                    Button {
                                                        // Снять выбор всех счетов группы
                                                        let groupAccountIDs = Set(groupAccounts.map { $0.accountUniqueID })
                                                        let newSelected = viewModel.state.selectedAccountIDs.subtracting(groupAccountIDs)
                                                        viewModel.handle(.selectAccounts(newSelected))
                                                    } label: {
                                                        Text("Снять")
                                                            .font(.system(size: 12, weight: .medium))
                                                            .foregroundStyle(AppColors.textSecondary)
                                                    }
                                                }
                                            }
                                            
                                            if groupAccounts.isEmpty {
                                                Text("Нет счетов")
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(AppColors.textTertiary)
                                                    .padding(.leading, 24)
                                            } else {
                                                ForEach(groupAccounts) { account in
                                                    if let accountInfo = viewModel.financeViewModel.getAccountInfo(account: account) {
                                                        Button {
                                                            viewModel.handle(.toggleAccount(account.accountUniqueID))
                                                        } label: {
                                                            HStack {
                                                                Image(systemName: accountInfo.icon)
                                                                    .font(.system(size: 14))
                                                                    .foregroundStyle(AppColors.textSecondary)
                                                                    .frame(width: 20)
                                                                
                                                                Text(accountInfo.name)
                                                                    .font(.system(size: 14, weight: .regular))
                                                                    .foregroundStyle(AppColors.textPrimary)
                                                                
                                                                Spacer()
                                                                
                                                                Image(systemName: viewModel.state.selectedAccountIDs.contains(account.accountUniqueID) ? "checkmark.circle.fill" : "circle")
                                                                    .font(.system(size: 18))
                                                                    .foregroundStyle(viewModel.state.selectedAccountIDs.contains(account.accountUniqueID) ? Color.green : AppColors.textTertiary)
                                                            }
                                                            .padding(.leading, 24)
                                                        }
                                                        .buttonStyle(.plain)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                )
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.3))
            )
        }
        
        private var accountsFilterSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Счета")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Spacer()
                    
                    // Кнопки управления
                    HStack(spacing: 12) {
                        Button {
                            viewModel.handle(.selectAllAccounts)
                        } label: {
                            Text("Все")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        
                        Button {
                            viewModel.handle(.deselectAllAccounts)
                        } label: {
                            Text("Снять")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                
                let accounts = viewModel.getAccountsForSelectedGroups()
                
                if accounts.isEmpty {
                    Text("Нет счетов")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 8) {
                        ForEach(accounts) { account in
                            if let accountInfo = viewModel.financeViewModel.getAccountInfo(account: account) {
                                Button {
                                    viewModel.handle(.toggleAccount(account.accountUniqueID))
                                } label: {
                                    HStack {
                                        Image(systemName: accountInfo.icon)
                                            .font(.system(size: 14))
                                            .foregroundStyle(AppColors.textSecondary)
                                            .frame(width: 20)
                                        
                                        Text(accountInfo.name)
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundStyle(AppColors.textPrimary)
                                        
                                        Spacer()
                                        
                                        Image(systemName: viewModel.state.selectedAccountIDs.contains(account.accountUniqueID) ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundStyle(viewModel.state.selectedAccountIDs.contains(account.accountUniqueID) ? Color.green : AppColors.textTertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.3))
            )
        }
    }
    
    // MARK: - Chart Section
    
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            customPeriodHeader
            
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
                financeChart
                
                // Выбор периода под графиком
                periodSelectorUnderChart
            }
        }
    }
    
    // MARK: - Custom Period Header
    
    private var customPeriodHeader: some View {
        Group {
            if viewModel.state.period == .custom, let customPeriod = viewModel.state.customPeriod {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    Text(formatPeriodRange(customPeriod.start, customPeriod.end))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
            }
        }
    }
    
    // MARK: - Finance Chart
    
    private var financeChart: some View {
        let seriesColor = Color(red: 1.0, green: 0.5, blue: 0.0)
        
        // Вычисляем нижнюю границу для AreaMark (минимальное значение с небольшим отступом)
        let values = viewModel.state.chartData.map { $0.value }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let range = maxValue - minValue
        let niceLower = minValue - max(0.5, range * 0.05)
        
        let chartContent = buildChartContent(
            seriesColor: seriesColor,
            niceLower: niceLower
        )
        
        let chartWithAxes = chartContent
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine()
                        .foregroundStyle(AppColors.textTertiary.opacity(0.4))
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text(formatCompactAmount(doubleValue))
                                .foregroundStyle(AppColors.textSecondary)
                                .font(.system(size: 10))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine()
                        .foregroundStyle(AppColors.textTertiary.opacity(0.4))
                    if viewModel.state.period != .all {
                        AxisValueLabel {
                            if let dateValue = value.as(Date.self) {
                                Text(formatDate(dateValue))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
            }
        
        let chartWithSelection = chartWithAxes
            .chartXSelection(value: Binding(
                get: { viewModel.state.selectedDate },
                set: { date in
                    viewModel.handle(.selectDateOnChart(date))
                }
            ))
            .chartGesture { proxy in
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in
                        viewModel.handle(.selectDateOnChart(nil))
                    }
            }
        
        return chartWithSelection
            .overlay(alignment: .top) {
                chartAnnotation(seriesColor: seriesColor)
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.state.chartData)
            .animation(.easeInOut(duration: 0.2), value: viewModel.state.selectedDate)
            .frame(height: 300)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.3))
            )
    }
    
    // MARK: - Chart Content Builder
    
    @ViewBuilder
    private func buildChartContent(seriesColor: Color, niceLower: Double) -> some View {
        Chart {
            // Всегда используем AreaMark с плавной интерполяцией для агрегированных данных
            ForEach(viewModel.state.chartData) { dataPoint in
                AreaMark(
                    x: .value("Дата", dataPoint.date, unit: .day),
                    yStart: .value("Низ", niceLower),
                    yEnd: .value("Сумма", dataPoint.value)
                )
                .interpolationMethod(.cardinal)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            seriesColor.opacity(0.35),
                            seriesColor.opacity(0.20),
                            seriesColor.opacity(0.10),
                            seriesColor.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                LineMark(
                    x: .value("Дата", dataPoint.date, unit: .day),
                    y: .value("Сумма", dataPoint.value)
                )
                .interpolationMethod(.cardinal)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(seriesColor)
            }
            
            // Визуализация выбранной точки
            if let selectedDate = viewModel.state.selectedDate {
                // Вертикальная линия на выбранной дате
                RuleMark(x: .value("Дата", selectedDate, unit: .day))
                    .foregroundStyle(seriesColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                
                // Точка на выбранной дате
                PointMark(
                    x: .value("Дата", selectedDate, unit: .day),
                    y: .value("Сумма", viewModel.state.currentBalance)
                )
                .foregroundStyle(.white)
                .symbolSize(80)
                .shadow(color: seriesColor.opacity(0.6), radius: 4)
            }
        }
    }
    
    
    // MARK: - Chart Annotation
    
    private func chartAnnotation(seriesColor: Color) -> some View {
        Group {
            if let selectedDate = viewModel.state.selectedDate {
                VStack(spacing: 4) {
                    Text(formatBalance(viewModel.state.currentBalance))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text(formatDate(selectedDate))
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(seriesColor.opacity(0.3), lineWidth: 1)
                        }
                }
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Period Selector Under Chart
    
    private var periodSelectorUnderChart: some View {
        HStack(spacing: 8) {
            // Кнопки периодов
            ForEach([DynamicsPeriod.all, .week, .month, .year], id: \.self) { period in
                Button {
                    viewModel.handle(.setPeriod(period))
                } label: {
                    Text(period.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(viewModel.state.period == period ? Color.white : AppColors.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if viewModel.state.period == period {
                                    Color.white.opacity(0.2)
                                } else {
                                    Color.white.opacity(0.1)
                                }
                            }
                        )
                        .clipShape(Capsule())
                }
            }
            
            // Кнопка календаря для кастомного периода
            Button {
                viewModel.handle(.showPeriodSelector)
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(viewModel.state.period == .custom ? Color.white : AppColors.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if viewModel.state.period == .custom {
                                Color.white.opacity(0.2)
                            } else {
                                Color.white.opacity(0.1)
                            }
                        }
                    )
                    .clipShape(Capsule())
            }
        }
    }
    
    private func formatCompactAmount(_ amount: Double) -> String {
        let absAmount = abs(amount)
        
        if absAmount >= 1_000_000_000 {
            return String(format: "%.1f млрд", amount / 1_000_000_000)
        } else if absAmount >= 1_000_000 {
            return String(format: "%.1f млн", amount / 1_000_000)
        } else if absAmount >= 1_000 {
            return String(format: "%.0f тыс", amount / 1_000)
        } else {
            return String(format: "%.0f", amount)
        }
    }
    
    // MARK: - Top Panel
    
    private var topPanel: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Текущий баланс
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatBalance(viewModel.state.currentBalance))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    // Подпись периода
                    Text(periodLabel)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                Spacer()
                
                // Дельта за период
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(viewModel.state.periodDelta.absolute >= 0 ? "+" : "")
                            .font(.system(size: 18, weight: .semibold))
                        Text(formatBalance(viewModel.state.periodDelta.absolute))
                            .font(.system(size: 18, weight: .semibold))
                        Text(viewModel.state.displayCurrency)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(viewModel.state.periodDelta.absolute >= 0 ? Color.green : AppColors.error)
                    
                    HStack(spacing: 4) {
                        if abs(viewModel.state.periodDelta.percent) >= 999999.0 {
                            Text("∞")
                                .font(.system(size: 14, weight: .medium))
                        } else {
                            Text(viewModel.state.periodDelta.percent >= 0 ? "+" : "")
                                .font(.system(size: 14, weight: .medium))
                            Text(String(format: "%.1f", viewModel.state.periodDelta.percent))
                                .font(.system(size: 14, weight: .medium))
                            Text("%")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .foregroundStyle(viewModel.state.periodDelta.percent >= 0 ? Color.green : AppColors.error)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill((viewModel.state.periodDelta.absolute >= 0 ? Color.green : AppColors.error).opacity(0.2))
                )
            }
            
            // Бейдж счета (если выбран один счет)
            if case .singleAccount(let accountID) = viewModel.state.dynamicsMode,
               let account = viewModel.getAccountsForSelectedGroups().first(where: { $0.accountUniqueID == accountID }),
               let accountInfo = financeViewModel.getAccountInfo(account: account) {
                HStack {
                    Image(systemName: accountInfo.icon)
                        .font(.system(size: 14))
                    Text(accountInfo.name)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.3))
        )
    }
    
    private var periodLabel: String {
        if let selectedDate = viewModel.state.selectedDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM yyyy"
            return "До \(formatter.string(from: selectedDate))"
        } else {
            switch viewModel.state.period {
            case .week: return "За 1W"
            case .month: return "За 1M"
            case .year: return "За 1Y"
            case .all: return "За All"
            case .custom: return "За период"
            }
        }
    }
    
    private func formatBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
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
        
        switch viewModel.state.period {
        case .week:
            formatter.dateFormat = "dd.MM"
        case .month:
            formatter.dateFormat = "dd.MM"
        case .year:
            formatter.dateFormat = "MMM"
        case .all:
            formatter.dateFormat = "MMM yyyy"
        case .custom:
            formatter.dateFormat = "dd.MM"
        }
        
        return formatter.string(from: date)
    }
    
    private func formatPeriodRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        
        let startString = formatter.string(from: start)
        let endString = formatter.string(from: end)
        
        return "\(startString) - \(endString)"
    }
    
    // MARK: - Dynamics List
    
    private var dynamicsList: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Панель переключения и фильтр
            HStack(spacing: 12) {
                // Кнопка фильтра
                Button {
                    viewModel.handle(.showFilterSheet)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColors.textSecondary)
                }
                
                // Переключение групп/счетов
                Picker("Режим просмотра", selection: Binding(
                    get: { viewModel.state.viewMode },
                    set: { viewModel.handle(.setViewMode($0)) }
                )) {
                    Text("Группы").tag(DynamicsViewMode.groups)
                    Text("Счета").tag(DynamicsViewMode.accounts)
                }
                .pickerStyle(.segmented)
            }
            
            // Таблица динамики
            if viewModel.state.dynamicsBreakdown.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("Нет данных")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    // Заголовки таблицы
                    HStack(spacing: 12) {
                        // Отступ для иконки (если есть счета с иконками)
                        if viewModel.state.viewMode == .accounts && viewModel.state.dynamicsBreakdown.contains(where: { $0.icon != nil }) {
                            Spacer()
                                .frame(width: 20)
                        } else if viewModel.state.viewMode == .accounts {
                            // Если режим счетов, но нет иконок, все равно добавляем отступ для выравнивания
                            Spacer()
                                .frame(width: 0)
                        }
                        
                        Text("Название")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                        
                        Text("Начало")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 80, alignment: .trailing)
                        
                        Text("Конец")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 100, alignment: .trailing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    
                    // Строки данных
                    ForEach(viewModel.state.dynamicsBreakdown) { item in
                        HStack(spacing: 12) {
                            // Иконка счета (если есть) или фиксированное место для выравнивания
                            if viewModel.state.viewMode == .accounts {
                                if let icon = item.icon {
                                    Image(systemName: icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(
                                            (item.accountType == .credit || item.isCreditCard)
                                                ? LinearGradient(
                                                    colors: [AppColors.error, AppColors.error],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                                : LinearGradient(
                                                    colors: AppColors.financesGradient,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                        )
                                        .frame(width: 20, height: 20)
                                } else {
                                    // Фиксированное место для выравнивания, если иконки нет
                                    Spacer()
                                        .frame(width: 20)
                                }
                            }
                            
                            Text(item.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Text(formatBalance(item.startValue))
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(width: 80, alignment: .trailing)
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatBalance(item.endValue))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(AppColors.textPrimary)
                                
                                // Для кредитов инвертируем логику: уменьшение долга = хорошо (зеленый плюс)
                                let isCredit = item.accountType == .credit
                                let displayDelta = isCredit ? -item.delta : item.delta
                                let displayDeltaPercent = isCredit ? -item.deltaPercent : item.deltaPercent
                                
                                HStack(spacing: 4) {
                                    Text(displayDelta >= 0 ? "+" : "")
                                        .font(.system(size: 11, weight: .medium))
                                    Text(formatBalance(abs(displayDelta)))
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(displayDelta >= 0 ? Color.green : AppColors.error)
                                
                                HStack(spacing: 4) {
                                    if abs(displayDeltaPercent) >= 999999.0 {
                                        Text("∞")
                                            .font(.system(size: 10))
                                    } else {
                                        Text(displayDeltaPercent >= 0 ? "+" : "")
                                            .font(.system(size: 10))
                                        Text(String(format: "%.1f", abs(displayDeltaPercent)))
                                            .font(.system(size: 10))
                                        Text("%")
                                            .font(.system(size: 10))
                                    }
                                }
                                .foregroundStyle(displayDeltaPercent >= 0 ? Color.green : AppColors.error)
                            }
                            .frame(width: 100, alignment: .trailing)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.05))
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
