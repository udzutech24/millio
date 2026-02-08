//
//  FinancesView.swift
//  millio
//

import SwiftUI
import SwiftData

// MARK: - Finances Tab Enum

enum FinancesTab: String {
    case main = "main"
    case dynamics = "dynamics"
}

struct FinancesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: FinanceViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                FinancesContentViewInternal(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = FinanceViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Internal Content View

private struct FinancesContentViewInternal: View {
    @ObservedObject var viewModel: FinanceViewModel
    @State private var selectedTab: FinancesTab = .main
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Вкладка 1: Основной экран
            FinancesMainTabView(viewModel: viewModel)
                .tabItem {
                    Label("Финансы", systemImage: "creditcard")
                }
                .tag(FinancesTab.main)
            
            // Вкладка 2: Динамика
            FinanceDynamicsTabView(financeViewModel: viewModel)
                .tabItem {
                    Label("Динамика", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(FinancesTab.dynamics)
        }
        .task {
            await viewModel.refreshRates()
        }
    }
}

#Preview {
    let schema = AppSchema.create()
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    
    FinancesView()
        .modelContainer(container)
        .environment(AppState())
}

// MARK: - Finances Main Tab View

private struct FinancesMainTabView: View {
    @ObservedObject var viewModel: FinanceViewModel
    
    var body: some View {
        mainContent
            .modifier(SheetsModifier(viewModel: viewModel))
    }
    
    private var mainContent: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Общая сумма
                    totalAmountSection
                    
                    // Список групп
                    groupsListSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 100) // Дополнительный отступ снизу для FAB
            }
            
            // Floating Action Button (FAB) внизу справа
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        viewModel.handle(.showAddAccountSheet(nil))
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
    }
    
    // MARK: - Total Amount Section
    
    private var totalAmountSection: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    Button {
                        viewModel.handle(.showDisplayCurrencySheet)
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.state.displayCurrency)
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(
                            LinearGradient(
                                colors: AppColors.financesGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    }
                    
                    if let secondaryCurrency = viewModel.state.secondaryDisplayCurrency {
                        Button {
                            viewModel.handle(.showSecondaryDisplayCurrencySheet)
                        } label: {
                            HStack(spacing: 4) {
                                Text(secondaryCurrency)
                                    .font(.system(size: 12, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .foregroundStyle(AppColors.textTertiary)
                        }
                    } else {
                        Button {
                            viewModel.handle(.showSecondaryDisplayCurrencySheet)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Доп. валюта")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    
                    Button {
                        viewModel.handle(.showSavingsGoalSheet)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                
                Spacer()
                
                Button {
                    viewModel.handle(.toggleAmountVisibility)
                } label: {
                    Image(systemName: viewModel.state.isAmountHidden ? "eye.slash" : "eye")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: AppColors.financesGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formatBalance(viewModel.state.totalAmount, isHidden: viewModel.state.isAmountHidden))
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    
                    Text(currencyDisplay(viewModel.state.displayCurrency))
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                        .lineLimit(1)
                }
                
                if let secondaryCurrency = viewModel.state.secondaryDisplayCurrency, viewModel.state.secondaryTotalAmount > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(formatBalance(viewModel.state.secondaryTotalAmount, isHidden: viewModel.state.isAmountHidden))
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                        
                        Text(currencyDisplay(secondaryCurrency))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }

            if let warning = viewModel.state.currencyConversionWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.warning)

                    Text("Выбранная API не поддерживает часть валют, поэтому итоговые суммы могут быть неполными.")
                        .font(.system(size: 12, weight: .regular))
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
                .accessibilityLabel(Text(warning))
            }
            
            // Полоса прогресса цели накопления
            if viewModel.state.isSavingsGoalEnabled && viewModel.state.savingsGoalAmount > 0 {
                VStack(spacing: 8) {
                    let progress: Double = {
                        let savingsGoal = viewModel.state.savingsGoalAmount
                        guard savingsGoal > 0 else { return 0.0 }
                        let calculated = viewModel.state.totalAmount / savingsGoal
                        guard calculated.isFinite else { return 0.0 }
                        return max(0.0, min(1.0, calculated))
                    }()
                    let displayCurrency = currencyDisplay(viewModel.state.displayCurrency)
                    let totalText = formatBalance(viewModel.state.totalAmount, isHidden: viewModel.state.isAmountHidden)
                    let goalText = formatBalance(viewModel.state.savingsGoalAmount, isHidden: viewModel.state.isAmountHidden)
                    
                    goalProgressBar(progress: progress)
                    
                    HStack {
                        Text("\(totalText) \(displayCurrency) из \(goalText) \(displayCurrency)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.financesGradient.first ?? AppColors.brandPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        
                        Spacer()
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
                .padding(.top, 4)
            }
            
            if viewModel.state.isLoadingRates {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(AppColors.textTertiary)
            }
        }
        .padding(.vertical, 20)
        
     
        
    }
    
    // MARK: - Groups List Section
    
    private var groupsListSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Группы")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                if !viewModel.state.groups.isEmpty {
                    Text("\(viewModel.state.groups.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            
            if viewModel.state.groups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(AppColors.textTertiary)
                    
                    Text("Нет групп")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Text("Создайте первую группу")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                groupsListView
            }
        }
    }
    
    private var groupsListView: some View {
        VStack(spacing: 12) {
            ForEach(0..<viewModel.state.groups.count, id: \.self) { index in
                Group {
                    let group = viewModel.state.groups[index]
                    FinanceGroupRow(
                        group: group,
                        viewModel: viewModel
                    )
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatBalance(_ balance: Double, isHidden: Bool = false) -> String {
        if isHidden {
            // Подсчитываем количество цифр в числе
            let digits = Int(balance.rounded())
            let digitCount = String(digits).count
            // Возвращаем точки вместо цифр
            return String(repeating: "•", count: max(3, digitCount))
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
    }
    
    private func currencyDisplay(_ code: String) -> String {
        switch code.uppercased() {
        case "RUB": "₽"
        case "USD": "$"
        case "EUR": "€"
        case "GBP": "£"
        case "CNY": "¥"
        default: code
        }
    }
    
    private func goalProgressBar(progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: AppColors.financesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, proxy.size.width * progress))
            }
        }
        .frame(height: 10)
    }
}

// MARK: - Finance Dynamics Tab View

private struct FinanceDynamicsTabView: View {
    @ObservedObject var financeViewModel: FinanceViewModel
    
    var body: some View {
        FinanceDynamicsView(
            financeViewModel: financeViewModel,
            wrapInNavigationStack: false
        )
    }
}
