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

@MainActor
enum FinancesDeepLinkHandler {
    static func openAddCardIfRequested(appState: AppState, viewModel: FinanceViewModel?) {
        guard appState.pendingOpenFinanceAddCard, let viewModel else { return }
        appState.pendingOpenFinanceAddCard = false
        viewModel.handle(.showAddAccountSheet(nil))
    }
}

struct FinancesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel: FinanceViewModel?
    private let currentRoute: AppRoute = .finances
    
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
                let createdViewModel = FinanceViewModel(modelContext: modelContext)
                viewModel = createdViewModel
                FinancesDeepLinkHandler.openAddCardIfRequested(
                    appState: appState,
                    viewModel: createdViewModel
                )
            } else {
                FinancesDeepLinkHandler.openAddCardIfRequested(
                    appState: appState,
                    viewModel: viewModel
                )
            }
        }
        .onChange(of: appState.pendingOpenFinanceAddCard) { _, _ in
            FinancesDeepLinkHandler.openAddCardIfRequested(appState: appState, viewModel: viewModel)
        }
        .onChange(of: appState.primaryCurrencyCode) { oldValue, newValue in
            viewModel?.handle(.syncPrimaryCurrencyChange(old: oldValue, new: newValue))
        }
        .onDisappear {
            viewModel?.handle(.setDisplayCurrency(appState.primaryCurrencyCode))
        }
        .navigationTitle("Финансы")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 6) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.96))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Назад")

                    Menu {
                        ForEach(MiniAppNavigation.destinations(excluding: currentRoute)) { destination in
                            Button {
                                MiniAppNavigation.navigate(to: destination.route, from: currentRoute, router: router)
                            } label: {
                                Label(destination.title, systemImage: destination.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.90))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Быстрая навигация по мини-приложениям")
                }
            }

            if let viewModel {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.handle(.showSavingsGoalSheet)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .accessibilityLabel("Настройки")
                }
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
            await viewModel.refreshCurrencyQuotes()
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
                VStack(spacing: 20) {
                    // Общая сумма
                    totalAmountSection
                    
                    // Список групп
                    groupsListSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
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
                                accentColor.opacity(0.18),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )

                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(fillGradient)
                                    .overlay(
                                        Circle()
                                            .fill(glowGradient)
                                            .opacity(0.6)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(accentColor.opacity(0.55), lineWidth: 1)
                                    )
                            )
                        
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
    }
    
    // MARK: - Total Amount Section
    
    private var totalAmountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formatBalance(viewModel.state.totalAmount, isHidden: viewModel.state.isAmountHidden))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Button {
                        viewModel.handle(.showDisplayCurrencySheet)
                    } label: {
                        Text(MonetaCurrency(rawValue: viewModel.state.displayCurrency)?.symbol ?? viewModel.state.displayCurrency)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        viewModel.handle(.toggleAmountVisibility)
                    } label: {
                        Image(systemName: viewModel.state.isAmountHidden ? "eye.slash" : "eye")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    refreshMenu
                }
            }

            if let secondaryCurrency = viewModel.state.secondaryDisplayCurrency {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatBalance(viewModel.state.secondaryTotalAmount, isHidden: viewModel.state.isAmountHidden))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)

                    Button {
                        viewModel.handle(.showSecondaryDisplayCurrencySheet)
                    } label: {
                        Text(MonetaCurrency(rawValue: secondaryCurrency)?.symbol ?? secondaryCurrency)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
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
                    let displayCurrency = MonetaCurrency(rawValue: viewModel.state.displayCurrency)?.symbol ?? viewModel.state.displayCurrency
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

    private var refreshMenu: some View {
        Menu {
            Button("Обновить котировки") {
                Task {
                    await viewModel.refreshCurrencyQuotes()
                }
            }
            .disabled(viewModel.state.isLoadingRates)

            Button("Обновить акции") {
                Task {
                    await viewModel.refreshStockPrices()
                }
            }
            .disabled(viewModel.state.isLoadingRates)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .frame(width: 26, height: 26)

                if viewModel.state.isLoadingRates {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppColors.textSecondary)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .accessibilityLabel(viewModel.state.isLoadingRates ? "Обновляем..." : "Обновить")
    }
    
    // MARK: - Groups List Section
    
    private var groupsListSection: some View {
        VStack(spacing: 12) {
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
