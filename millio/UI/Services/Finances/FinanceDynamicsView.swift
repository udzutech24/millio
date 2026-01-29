//
//  FinanceDynamicsView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//
//  Обновлено: Новый дизайн графика с интерактивным выбором точки,
//  collapsing header и улучшенным UX.
//

import SwiftUI
import SwiftData
import Charts

// MARK: - Finance Dynamics View

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

    /// Счет для действий (редактирование/удаление) в режиме одного счета
    var initialAccount: FinanceAccount? = nil

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
                    initialAccountID: initialAccountID,
                    initialAccount: initialAccount
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
        .onChange(of: financeViewModel.state.availableCards.map {
            "\($0.cardUniqueID)_\($0.balance)_\($0.updatedAt.timeIntervalSince1970)"
        }) { _, _ in
            dynamicsViewModel?.handle(.loadData)
        }
        .onChange(of: financeViewModel.state.availableCredits.map {
            "\($0.creditUniqueID)_\($0.remainingAmount)_\($0.updatedAt.timeIntervalSince1970)"
        }) { _, _ in
            dynamicsViewModel?.handle(.loadData)
        }
        .onChange(of: financeViewModel.state.availableInvestments.map {
            "\($0.investmentUniqueID)_\($0.amount)_\($0.updatedAt.timeIntervalSince1970)"
        }) { _, _ in
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
    var initialAccount: FinanceAccount? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showEditForm = false
    @State private var collapseProgress: CGFloat = 0
    @State private var lastCollapseProgress: CGFloat = 0

    // Локальное состояние для кастомного периода
    @State private var useCustomPeriod: Bool = false
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()
    @State private var showCustomPeriodSheet: Bool = false
    @State private var draftStartDate: Date = Date()
    @State private var draftEndDate: Date = Date()

    // Кэшированные значения для графика
    @State private var cachedSelectedPoint: (date: Date, value: Double)? = nil

    var body: some View {
        ZStack {
            GradientBackground()

            if showEditForm, viewModel.state.isSingleAccountMode, let account = initialAccount {
                editForm(for: account)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Якорь для измерения скролла
                        Color.clear
                            .frame(height: 0)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear
                                        .preference(
                                            key: ScrollOffsetKey.self,
                                            value: proxy.frame(in: .named("dynScroll")).minY
                                        )
                                }
                            )

                        // Карточка графика
                        chartCard

                        if let warning = viewModel.state.currencyConversionWarning {
                            currencyWarningView(text: warning)
                        }

                        // Список динамики
                        dynamicsListCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .coordinateSpace(name: "dynScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { y in
                    let threshold: CGFloat = 140
                    let p = min(max(-y / threshold, 0), 1)
                    let quant: CGFloat = 0.02
                    if abs(p - lastCollapseProgress) > quant {
                        lastCollapseProgress = p
                        collapseProgress = p
                    }
                }
            }
        }
        .navigationTitle("Динамика")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if viewModel.state.isSingleAccountMode, initialAccount != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(showEditForm ? "Динамика" : "Редактировать") {
                        showEditForm.toggle()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showFilterSheet },
            set: { if !$0 { viewModel.handle(.hideFilterSheet) } }
        )) {
            FinanceDynamicsFilterSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showCustomPeriodSheet) {
            customPeriodSheet
        }
        .sheet(isPresented: $showSubscriptionSheet) {
            NavigationStack {
                SubscriptionView()
            }
        }
        .sheet(isPresented: Binding(
            get: {
                financeViewModel.state.showEditCardSheet ||
                financeViewModel.state.showEditCreditSheet ||
                financeViewModel.state.showEditInvestmentSheet
            },
            set: { if !$0 {
                if financeViewModel.state.showEditCardSheet { financeViewModel.handle(.hideEditCardSheet) }
                if financeViewModel.state.showEditCreditSheet { financeViewModel.handle(.hideEditCreditSheet) }
                if financeViewModel.state.showEditInvestmentSheet { financeViewModel.handle(.hideEditInvestmentSheet) }
            }}
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
        .onAppear {
            // Синхронизация с ViewModel при появлении
            if let customPeriod = viewModel.state.customPeriod {
                customStartDate = customPeriod.start
                customEndDate = customPeriod.end
                useCustomPeriod = viewModel.state.period == .custom
            }
        }
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        let expandedHeight: CGFloat = 260
        let minHeight: CGFloat = 64
        let currentHeight = minHeight + (expandedHeight - minHeight) * max(0, 1 - collapseProgress)

        return ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                // Header с балансом и дельтой
                chartHeader

                // График
                if !appState.isPro {
                    proBlockedView
                } else if viewModel.state.isLoading {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(0, currentHeight - 64))
                } else if viewModel.state.chartData.isEmpty {
                    emptyChartView
                        .frame(height: max(0, currentHeight - 64))
                } else {
                    chartContent
                        .frame(height: max(0, currentHeight - 64))
                        .padding(.top, 8)
                        .animation(.easeInOut(duration: 0.25), value: viewModel.state.period)
                        .animation(.easeInOut(duration: 0.25), value: viewModel.state.displayCurrency)
                }

                // Селектор периодов
                periodSelector
            }
            .scaleEffect(x: 1, y: max(CGFloat(0.6), CGFloat(1) - collapseProgress * CGFloat(0.6)), anchor: .top)
            .clipped()
            .opacity(Double(max(CGFloat(0.35), CGFloat(1) - collapseProgress * CGFloat(0.65))))

            // Градиент при сворачивании
            if collapseProgress > 0.05 {
                LinearGradient(
                    colors: [AppColors.textTertiary.opacity(0.14), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: max(12, 24 * collapseProgress))
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.3))
        }
        .clipped()
        .frame(height: currentHeight + 100)
    }

    // MARK: - Chart Header

    private var chartHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // Баланс с валютой
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
                    HStack(spacing: 6) {
                        Text(formatBalance(viewModel.state.currentBalance))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Text(String(viewModel.state.displayCurrency.prefix(1)))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(6)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Бейдж с дельтой
                if viewModel.state.chartData.count >= 2 {
                    let delta = viewModel.state.periodDelta
                    let color: Color = delta.absolute >= 0 ? .green : AppColors.error
                    HStack(spacing: 6) {
                        Text(formatDelta(delta.absolute))
                            .font(.caption.weight(.semibold))
                        Text(formatPercent(delta.percent))
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(color.opacity(0.18)))
                    .foregroundStyle(color)
                }
            }

            // Бейдж счета (если выбран один счет)
            if case .singleAccount(let accountID) = viewModel.state.dynamicsMode,
               let account = viewModel.getAccountsForSelectedGroups().first(where: { $0.accountUniqueID == accountID }),
               let accountInfo = viewModel.getAccountInfoForDynamics(account: account) {
                HStack(spacing: 6) {
                    Image(systemName: accountInfo.icon)
                        .font(.caption)
                    Text(accountInfo.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .foregroundStyle(AppColors.textSecondary)
            }

            // Период
            let (startDate, endDate) = viewModel.getPeriodDates()
            let sameYear = Calendar.current.component(.year, from: startDate) == Calendar.current.component(.year, from: endDate)
            let startFormat: Date.FormatStyle = sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
            let endFormat: Date.FormatStyle = .dateTime.day().month(.abbreviated).year()
            Text("\(startDate.formatted(startFormat)) — \(endDate.formatted(endFormat))")
                .font(.caption2)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, 12)
    }

    // MARK: - Chart Content

    private var chartContent: some View {
        let points = viewModel.state.chartData
        let values = points.map { $0.value }
        let niceY = NiceYScale.make(values: values)
        let (startDate, endDate) = viewModel.getPeriodDates()
        let xDomain = startDate...endDate

        return FinanceChartContainerView(
            points: points,
            selectedPoint: cachedSelectedPoint,
            seriesColor: Color.orange,
            niceY: niceY,
            xDomain: xDomain,
            xAxisStride: xAxisStride,
            xAxisCount: xAxisCount,
            currencyCode: viewModel.state.displayCurrency,
            onSelectPoint: { newPoint in
                if let pt = newPoint {
                    cachedSelectedPoint = (date: pt.0, value: pt.1)
                    viewModel.handle(.selectDateOnChart(pt.0))
                } else {
                    cachedSelectedPoint = nil
                    viewModel.handle(.selectDateOnChart(nil))
                }
            }
        )
    }

    // MARK: - Period Selector

    private var periodSelector: some View {
        HStack(spacing: 8) {
            // Кнопки периодов
            ForEach([DynamicsPeriod.all, .week, .month, .year], id: \.self) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.handle(.setPeriod(period))
                        useCustomPeriod = false
                    }
                    cachedSelectedPoint = nil
                } label: {
                    Text(period.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(
                                period == viewModel.state.period && !useCustomPeriod
                                    ? Color.white.opacity(0.18)
                                    : Color.white.opacity(0.06)
                            )
                        )
                        .overlay(
                            Capsule().stroke(
                                Color.white.opacity(
                                    period == viewModel.state.period && !useCustomPeriod ? 0.20 : 0.08
                                ),
                                lineWidth: 1
                            )
                        )
                        .foregroundStyle(
                            period == viewModel.state.period && !useCustomPeriod
                                ? AppColors.textPrimary
                                : AppColors.textSecondary
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            // Кнопка календаря
            Button {
                draftStartDate = customStartDate
                draftEndDate = customEndDate
                showCustomPeriodSheet = true
            } label: {
                Image(systemName: useCustomPeriod ? "calendar.badge.checkmark" : "calendar")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .foregroundStyle(useCustomPeriod ? AppColors.textPrimary : AppColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Custom Period Sheet

    private var customPeriodSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 16) {
                    // Header с информацией о периоде
                    VStack(alignment: .leading, spacing: 6) {
                        let sameYear = Calendar.current.component(.year, from: draftStartDate) == Calendar.current.component(.year, from: draftEndDate)
                        let startFormat: Date.FormatStyle = sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()
                        let endFormat: Date.FormatStyle = .dateTime.day().month(.abbreviated).year()
                        Text("Период: \(min(draftStartDate, draftEndDate).formatted(startFormat)) — \(max(draftStartDate, draftEndDate).formatted(endFormat))")
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Выберите начало и конец периода на календаре")
                            .font(.callout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)

                    // Календарь
                    CalendarRangeMonthView(startDate: $draftStartDate, endDate: $draftEndDate)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showCustomPeriodSheet = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button {
                        let start = min(draftStartDate, draftEndDate)
                        let end = max(draftStartDate, draftEndDate)
                        let clampedEnd = min(end, Calendar.current.startOfDay(for: Date()))
                        let clampedStart = min(start, clampedEnd)
                        customStartDate = clampedStart
                        customEndDate = clampedEnd
                        useCustomPeriod = true
                        viewModel.handle(.setCustomPeriod(start: clampedStart, end: clampedEnd))
                        cachedSelectedPoint = nil
                        showCustomPeriodSheet = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Готово").bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Dynamics List Card

    private var dynamicsListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Панель с фильтром и переключателем
            HStack(spacing: 8) {
                Button {
                    viewModel.handle(.showFilterSheet)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 20))
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)

                Picker("Режим", selection: Binding(
                    get: { viewModel.state.viewMode },
                    set: { viewModel.handle(.setViewMode($0)) }
                )) {
                    Text("Группы").tag(DynamicsViewMode.groups)
                    Text("Счета").tag(DynamicsViewMode.accounts)
                }
                .pickerStyle(.segmented)
            }

            // Таблица
            LazyVStack(spacing: 0) {
                // Заголовок таблицы
                tableHeader

                // Итого
                if let total = totalRow {
                    totalRowView(total)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    Divider().overlay(Color.white.opacity(0.06))
                }

                // Строки данных
                ForEach(viewModel.state.dynamicsBreakdown) { item in
                    rowView(item)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.3))
        )
    }

    // MARK: - Table Header

    private var tableHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 12)
                Text("Начало")
                    .font(.caption2).foregroundStyle(AppColors.textSecondary)
                    .frame(width: 92, alignment: .trailing)
                Text("Конец")
                    .font(.caption2).foregroundStyle(AppColors.textSecondary)
                    .frame(width: 92, alignment: .trailing)
            }
            .padding(.vertical, 4)
            Divider().overlay(Color.white.opacity(0.06))
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: - Row Views

    @ViewBuilder
    private func rowView(_ item: DynamicsBreakdownItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Иконка (для счетов)
                if viewModel.state.viewMode == .accounts, let icon = item.icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            (item.accountType == .credit || item.isCreditCard)
                                ? LinearGradient(colors: [AppColors.error, AppColors.error], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: AppColors.financesGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 20, height: 20)
                }

                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(AppColors.textPrimary)
                
                if item.isArchived {
                    Text("архив")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(formatBalance(item.startValue))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 92, alignment: .trailing)
                        Text(formatBalance(item.endValue))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 92, alignment: .trailing)
                    }

                    // Бейдж с изменением
                    let badgeColor = deltaColor(for: item)
                    let badgeText = "\(formatDelta(item.delta))  •  \(formatPercent(item.deltaPercent))"
                    Text(badgeText)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(badgeColor.opacity(0.14)))
                        .foregroundStyle(badgeColor)
                        .fixedSize()
                }
            }
        }
        .listRowSeparator(.visible)
    }

    @ViewBuilder
    private func totalRowView(_ item: DynamicsBreakdownItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(formatBalance(item.startValue))
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 92, alignment: .trailing)
                        Text(formatBalance(item.endValue))
                            .font(.footnote.monospacedDigit().weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 92, alignment: .trailing)
                    }

                    let badgeColor: Color = item.delta >= 0 ? .green : AppColors.error
                    let badgeText = "\(formatDelta(item.delta))  •  \(formatPercent(item.deltaPercent))"
                    Text(badgeText)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(badgeColor.opacity(0.14)))
                        .foregroundStyle(badgeColor)
                        .fixedSize()
                }
            }
        }
    }

    // MARK: - Total Row

    private var totalRow: DynamicsBreakdownItem? {
        guard !viewModel.state.dynamicsBreakdown.isEmpty else { return nil }
        let startSum = viewModel.state.dynamicsBreakdown.reduce(0) { $0 + $1.startValue }
        let endSum = viewModel.state.dynamicsBreakdown.reduce(0) { $0 + $1.endValue }
        let delta = endSum - startSum
        let percent: Double = abs(startSum) > 0.01 ? (delta / abs(startSum)) * 100 : 0
        return DynamicsBreakdownItem(
            id: "total",
            name: "Итого",
            startValue: startSum,
            endValue: endSum,
            delta: delta,
            deltaPercent: percent,
            icon: nil,
            accountType: nil,
            isCreditCard: false,
            isArchived: false
        )
    }

    // MARK: - Blocked/Empty Views

    private var proBlockedView: some View {
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
                            Capsule().stroke(
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
        .frame(height: 200)
        .padding(24)
    }

    private var emptyChartView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)

            Text("Нет данных для отображения")
                .font(.system(size: 16))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Edit Form

    @ViewBuilder
    private func editForm(for account: FinanceAccount) -> some View {
        switch account.accountType {
        case .card:
            if let card = financeViewModel.state.availableCards.first(where: { $0.cardUniqueID == account.accountID }) {
                FinanceEditCardView(
                    card: card,
                    viewModel: financeViewModel,
                    onClose: { showEditForm = false },
                    onDelete: { deleteAccountAndDismiss(account) }
                )
            }
        case .credit:
            if let credit = financeViewModel.state.availableCredits.first(where: { $0.creditUniqueID == account.accountID }) {
                FinanceEditCreditView(
                    credit: credit,
                    viewModel: financeViewModel,
                    onClose: { showEditForm = false },
                    onDelete: { deleteAccountAndDismiss(account) }
                )
            }
        case .investment:
            if let investment = financeViewModel.state.availableInvestments.first(where: { $0.investmentUniqueID == account.accountID }) {
                FinanceEditInvestmentView(
                    investment: investment,
                    viewModel: financeViewModel,
                    onClose: { showEditForm = false },
                    onDelete: { deleteAccountAndDismiss(account) }
                )
            }
        }
    }

    private func deleteAccountAndDismiss(_ account: FinanceAccount) {
        financeViewModel.handle(.deleteAccountPermanently(account))
        financeViewModel.handle(.hideAccountDynamics)
        dismiss()
    }

    // MARK: - Helpers

    private var xAxisStride: Calendar.Component {
        switch viewModel.state.period {
        case .week: return .day
        case .month: return .day
        case .year: return .month
        case .all, .custom: return .month
        }
    }

    private var xAxisCount: Int {
        switch viewModel.state.period {
        case .week: return 1
        case .month: return 7
        case .year: return 2
        case .all, .custom: return 3
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

    private func formatDelta(_ delta: Double) -> String {
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(formatBalance(delta))"
    }

    private func formatPercent(_ percent: Double) -> String {
        if abs(percent) >= 999999 {
            return percent > 0 ? "+∞" : "-∞"
        }
        return String(format: "%+.1f%%", percent)
    }

    private func deltaColor(for item: DynamicsBreakdownItem) -> Color {
        if item.accountType == .credit || item.isCreditCard {
            // Для долгов: уменьшение = хорошо (зеленый)
            let startAbs = abs(item.startValue)
            let endAbs = abs(item.endValue)
            if endAbs < startAbs { return .green }
            if endAbs > startAbs { return AppColors.error }
            return AppColors.textSecondary
        } else {
            return item.delta >= 0 ? .green : AppColors.error
        }
    }

    private func currencyWarningView(text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Filter Sheet

private struct FinanceDynamicsFilterSheet: View {
    @ObservedObject var viewModel: FinanceDynamicsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        currencyPicker

                        if !viewModel.state.isSingleGroupMode && !viewModel.state.isSingleAccountMode {
                            groupsFilterSection
                        }

                        if !viewModel.state.isSingleAccountMode &&
                           (!viewModel.state.selectedGroupIDs.isEmpty || viewModel.state.isSingleGroupMode) {
                            accountsFilterSection
                        }
                        
                        archivedToggleSection
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

                HStack(spacing: 12) {
                    Button { viewModel.handle(.selectAllGroups) } label: {
                        Text("Все")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    Button { viewModel.handle(.deselectAllGroups) } label: {
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
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.state.groups) { group in
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
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
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

                HStack(spacing: 12) {
                    Button { viewModel.handle(.selectAllAccounts) } label: {
                        Text("Все")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    Button { viewModel.handle(.deselectAllAccounts) } label: {
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
            } else {
                VStack(spacing: 8) {
                    ForEach(accounts) { account in
                        if let accountInfo = viewModel.getAccountInfoForDynamics(account: account) {
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

    private var archivedToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Архив")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            
            Toggle("Показывать архивные счета", isOn: Binding(
                get: { viewModel.state.showArchivedAccounts },
                set: { viewModel.handle(.setShowArchivedAccounts($0)) }
            ))
            .tint(AppColors.textPrimary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.3))
        )
    }
}

// MARK: - Scroll Offset Key

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
