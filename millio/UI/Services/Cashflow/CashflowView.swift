//
//  CashflowView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI
import SwiftData

struct CashflowView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CashflowViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                CashflowContentView(
                    viewModel: viewModel
                )
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = CashflowViewModel(modelContext: modelContext)
            }
            // Перезагружаем данные при каждом появлении экрана
            viewModel?.handle(.loadCards)
            viewModel?.handle(.loadTransactions)
        }
    }
}

// MARK: - Cashflow Content View

private struct CashflowContentView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @State private var draftStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var draftEndDate: Date = Date()
    @State private var showAssetChangeInfoSheet: Bool = false
    @State private var showIncomeBreakdown: Bool = false
    @State private var showExpenseBreakdown: Bool = false
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Выбор периода
                    periodSelectionSection

                    // Сводка активов за период
                    assetBreakdownSection

                    if let warning = viewModel.state.currencyConversionWarning {
                        currencyWarningView(text: warning)
                    }
                    
                    // Кнопки действий
                    actionButtonsSection
                    
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Кэшфлоу")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { topToolbar }
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
                switch creatingType {
                case .income:
                    CashflowIncomeTransactionSheet(viewModel: viewModel)
                case .expense:
                    CashflowExpenseTransactionSheet(viewModel: viewModel)
                case .transfer:
                    CashflowTransferTransactionSheet(viewModel: viewModel)
                case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
                    CashflowTransactionEditorView(
                        viewModel: viewModel,
                        transactionType: creatingType
                    )
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showPeriodSelector },
            set: { if !$0 { viewModel.handle(.hidePeriodSelector) } }
        )) {
            customPeriodSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showTransactionsHistory },
            set: { if !$0 { viewModel.handle(.hideTransactionsHistory) } }
        )) {
            CashflowTransactionsHistoryView(viewModel: viewModel)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCurrencySelector },
            set: { if !$0 { viewModel.handle(.hideCurrencySelector) } }
        )) {
            CashflowCurrencySelectorView(viewModel: viewModel)
        }
        .sheet(isPresented: $showAssetChangeInfoSheet) {
            assetChangeInfoSheet
        }
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            // Кнопка Доход
            CashflowActionButton(
                accessibilityLabel: "Доход",
                icon: "plus",
                gradientColors: AppColors.incomeGradient
            ) {
                viewModel.handle(.addTransaction(.income))
            }
            
            // Кнопка Расход
            CashflowActionButton(
                accessibilityLabel: "Расход",
                icon: "minus",
                gradientColors: AppColors.expenseGradient
            ) {
                viewModel.handle(.addTransaction(.expense))
            }
            
            // Кнопка Перевод
            CashflowActionButton(
                accessibilityLabel: "Перевод",
                icon: "arrow.left.arrow.right",
                gradientColors: AppColors.cashflowGradient
            ) {
                viewModel.handle(.addTransaction(.transfer))
            }
        }
    }
    
    // MARK: - Period Stats Section
    
    private var assetBreakdownSection: some View {
        VStack(spacing: 10) {
            statRow(
                title: "Активы на начало периода",
                value: formatMoney(viewModel.state.assetsAtPeriodStart),
                valueColor: AppColors.textPrimary
            )

            expandableStatRow(
                title: "Доходы",
                value: formatSignedMoney(viewModel.state.totalIncome),
                valueColor: positiveColor(for: viewModel.state.totalIncome),
                isExpanded: $showIncomeBreakdown
            )
            
            if showIncomeBreakdown {
                breakdownList(
                    entries: viewModel.state.incomeBreakdown,
                    signedAmount: { $0 },
                    valueColor: { positiveColor(for: $0) }
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Text("Изменение стоимости активов")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                        Button {
                            showAssetChangeInfoSheet = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text(formatSignedMoney(viewModel.state.assetValueChange))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(positiveColor(for: viewModel.state.assetValueChange))
                }

            }
            .padding(12)
            .background(financeInnerBackground(cornerRadius: 16))

            expandableStatRow(
                title: "Расходы внесенные",
                value: formatSignedMoney(-viewModel.state.contributedExpense),
                valueColor: negativeColor(for: -viewModel.state.contributedExpense),
                isExpanded: $showExpenseBreakdown
            )
            
            if showExpenseBreakdown {
                breakdownList(
                    entries: viewModel.state.expenseBreakdown,
                    signedAmount: { -$0 },
                    valueColor: { negativeColor(for: -$0) }
                )
            }

            VStack(spacing: 8) {
                statRow(
                    title: "Активы на конец периода",
                    value: formatMoney(viewModel.state.assetsAtPeriodEnd),
                    valueColor: AppColors.textPrimary
                )

                Divider()
                    .overlay(AppColors.textSecondary.opacity(0.3))

                HStack {
                    Text("Итого")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text(formatSignedMoney(viewModel.state.periodTotalChange))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(positiveColor(for: viewModel.state.periodTotalChange))
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
            }
            .padding(12)
            .background(financeInnerBackground(cornerRadius: 16))
        }
        .padding(12)
        .background(financeCardBackground(cornerRadius: 20))
    }

    private func statRow(title: String, value: String, valueColor: Color) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .padding(12)
        .background(financeInnerBackground(cornerRadius: 16))
    }

    private func expandableStatRow(
        title: String,
        value: String,
        valueColor: Color,
        isExpanded: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded.wrappedValue ? "minus.circle" : "plus.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded.wrappedValue ? "Скрыть детали" : "Показать детали")
            }
        }
        .padding(12)
        .background(financeInnerBackground(cornerRadius: 16))
    }

    private func breakdownList(
        entries: [CashflowCategoryBreakdownEntry],
        signedAmount: @escaping (Double) -> Double,
        valueColor: @escaping (Double) -> Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                Text("Нет операций")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                ForEach(entries) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.title)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(2)
                        Spacer()
                        let value = signedAmount(entry.convertedAmount)
                        Text(formatSignedMoney(value))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(valueColor(entry.convertedAmount))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(12)
        .background(financeInnerBackground(cornerRadius: 16))
    }

    private func currencyWarningView(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.warning)

            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(3)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.warning.opacity(0.4), lineWidth: 1)
        }
        .accessibilityLabel(Text(text))
    }
    
    // MARK: - Period Selection Section
    
    private var periodSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    viewModel.handle(.movePeriodBackward)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 8) {
                    Text(viewModel.currentPeriodHeaderTitle())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    Button {
                        draftStartDate = viewModel.state.customStartDate
                        draftEndDate = viewModel.state.customEndDate
                        viewModel.handle(.showPeriodSelector)
                    } label: {
                        Image("calendar")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .padding(7)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    viewModel.handle(.movePeriodForward)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(viewModel.canMovePeriodForward() ? AppColors.textPrimary : AppColors.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canMovePeriodForward())
            }

            let range = viewModel.currentDateRange()
            Text("\(formatPeriod(range.0)) — \(formatPeriod(range.1))")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(12)
        .background(financeCardBackground(cornerRadius: 18))
    }
    
    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button {
                    viewModel.handle(.showCurrencySelector)
                } label: {
                    Image(systemName: "rublesign.circle.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Выбор валюты отображения")
                
                Button {
                    viewModel.handle(.showTransactionsHistory)
                } label: {
                    Image("operations")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        
                }
                .accessibilityLabel("История операций")
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
    
    private func formatPeriod(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    private func formatMoney(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: NSNumber(value: amount)) ?? "0"
        let symbol = MonetaCurrency(rawValue: viewModel.state.displayCurrency)?.symbol ?? viewModel.state.displayCurrency
        return "\(value) \(symbol)"
    }

    private func formatSignedMoney(_ amount: Double) -> String {
        let absolute = formatMoney(abs(amount))
        if amount > 0.0000001 {
            return "+\(absolute)"
        }
        if amount < -0.0000001 {
            return "-\(absolute)"
        }
        return absolute
    }

    private func financeCardBackground(cornerRadius: CGFloat) -> some View {
        let accentColor = AppColors.financesGradient.first ?? .cyan
        let fillGradient = LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.07, blue: 0.11),
                Color(red: 0.02, green: 0.04, blue: 0.06),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let glowGradient = LinearGradient(
            colors: [
                accentColor.opacity(0.16),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fillGradient)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(glowGradient)
                    .opacity(0.6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accentColor.opacity(0.55), lineWidth: 1)
            )
    }

    private func financeInnerBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            )
    }

    private func positiveColor(for value: Double) -> Color {
        if value > 0.0000001 {
            return Color(.sRGB, red: 127.0 / 255.0, green: 1.0, blue: 189.0 / 255.0, opacity: 1.0)
        }
        if value < -0.0000001 {
            return Color(.sRGB, red: 1.0, green: 0.37, blue: 0.37, opacity: 1.0)
        }
        return AppColors.textSecondary
    }

    private func negativeColor(for value: Double) -> Color {
        if value < -0.0000001 {
            return Color(.sRGB, red: 1.0, green: 0.37, blue: 0.37, opacity: 1.0)
        }
        if value > 0.0000001 {
            return Color(.sRGB, red: 127.0 / 255.0, green: 1.0, blue: 189.0 / 255.0, opacity: 1.0)
        }
        return AppColors.textSecondary
    }

    private var assetChangeInfoSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Как считается изменение стоимости активов?")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)

                        Text("Формула:\nИзменение = (Итого на конец – Итого на начало) – Доходы + Расходы.")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)

                        Text("Подстановка:")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)

                        Group {
                            Text("Итого на начало: \(formatMoney(viewModel.state.assetsAtPeriodStart))")
                            Text("Итого на конец: \(formatMoney(viewModel.state.assetsAtPeriodEnd))")
                            Text("Доходы: \(formatSignedMoney(viewModel.state.totalIncome))")
                            Text("Расходы: \(formatSignedMoney(-viewModel.state.contributedExpense))")
                            Text("Изменение: \(formatSignedMoney(viewModel.state.assetValueChange))")
                        }
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary)

                        Text("Проверка баланса:")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)

                        let checkValue = abs(
                            (viewModel.state.assetsAtPeriodEnd - viewModel.state.assetsAtPeriodStart) -
                            (viewModel.state.totalIncome + viewModel.state.assetValueChange - viewModel.state.contributedExpense)
                        )
                        Text(checkValue < 0.01 ? "Сходится" : "Не сходится")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(checkValue < 0.01 ? Color.green : Color.red)

                        Text("Пояснение: это переоценка/движение стоимости активов за период после учета явных притоков (доходов) и учтенных расходов.")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(24)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAssetChangeInfoSheet = false
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    private var customPeriodSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 16) {
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
                    .padding(.top, 4)

                    CalendarRangeMonthView(startDate: $draftStartDate, endDate: $draftEndDate)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.handle(.hidePeriodSelector)
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
                        viewModel.handle(.setSelectedMonth(Date()))
                        viewModel.handle(.hidePeriodSelector)
                    } label: {
                        Text("Сбросить")
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
                        let start = min(draftStartDate, draftEndDate)
                        let end = max(draftStartDate, draftEndDate)
                        let clampedEnd = min(end, Calendar.current.startOfDay(for: Date()))
                        let clampedStart = min(start, clampedEnd)
                        viewModel.handle(.setCustomPeriod(start: clampedStart, end: clampedEnd))
                        viewModel.handle(.hidePeriodSelector)
                    } label: {
                        Text("Показать")
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
}

// MARK: - Cashflow Action Button

private struct CashflowActionButton: View {
    let accessibilityLabel: String
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
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
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
