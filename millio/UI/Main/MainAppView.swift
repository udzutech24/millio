//
//  MainAppView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import SwiftData

@MainActor
enum MainWidgetDeepLinkHandler {
    static func consumePendingActions(
        appState: AppState,
        router: AppRouter
    ) {
        if appState.pendingOpenConverterService {
            appState.pendingOpenConverterService = false
            router.navigationPath = NavigationPath()
            router.push(.courses)
        }

        if appState.pendingOpenMainExpenseSheet {
            appState.pendingOpenMainExpenseSheet = false
            appState.pendingOpenCashflowExpense = true
            router.navigationPath = NavigationPath()
            router.push(.cashflow)
        }

        if appState.pendingOpenMainIncomeSheet {
            appState.pendingOpenMainIncomeSheet = false
            appState.pendingOpenCashflowIncome = true
            router.navigationPath = NavigationPath()
            router.push(.cashflow)
        }
    }
}

struct MainAppView: View {
    @Bindable var router: AppRouter
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: MainAppViewModel
    @State private var services: [ServiceItem] = []
    @State private var draggedService: ServiceItem?
    @State private var cashflowViewModel: CashflowViewModel?
    @State private var showExpenseSheet = false
    @State private var showIncomeSheet = false
    @State private var showCashflowHistory = false
    @State private var showQuickSetupSheet = false
    @State private var showQuickSetupBanner = false
    private let serviceOrderManager = ServiceOrderManager()
    
    init(router: AppRouter) {
        self.router = router
        _viewModel = StateObject(wrappedValue: MainAppViewModel(router: router))
    }
    
    var body: some View {
        NavigationStack(path: $router.navigationPath) {
            ZStack {
                GradientBackground()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        // Аватарка или иконка профиля слева
                        Button {
                            viewModel.handle(.navigateToProfile)
                        } label: {
                            headerProfileImage
                        }
                        
                        Spacer()
                        
                        // История операций справа
                        Button {
                            prepareCashflowQuickAccess()
                            showCashflowHistory = true
                        } label: {
                        Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.95))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.95), lineWidth: 1.3)
                                )
                        }
                        .accessibilityLabel(MainLocalization.text(MainLocalization.historyAccessibility))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    // Service buttons grid
                    if showQuickSetupBanner {
                        quickSetupBanner
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                    }

                    servicesGrid
                        .padding(.horizontal, 24)
                        .padding(.top, showQuickSetupBanner ? 20 : 28)
                    
                    Spacer()
                    
                    // Bottom action buttons
                    HStack(spacing: 16) {
                        ForEach(MainQuickActionsLayout.buttonOrder, id: \.self) { action in
                            switch action {
                            case .expense:
                                ActionButton(
                                    title: MainLocalization.text(MainLocalization.quickActionExpense),
                                    icon: .system(QuickActionIcons.expense),
                                    gradientColors: AppColors.expenseGradient
                                ) {
                                    prepareCashflowQuickAccess()
                                    showExpenseSheet = true
                                }
                            case .income:
                                ActionButton(
                                    title: MainLocalization.text(MainLocalization.quickActionIncome),
                                    icon: .system(QuickActionIcons.income),
                                    gradientColors: AppColors.incomeGradient
                                ) {
                                    prepareCashflowQuickAccess()
                                    showIncomeSheet = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                routeView(for: route)
            }
            .sheet(isPresented: $showExpenseSheet) {
                if let cashflowViewModel = cashflowViewModel {
                    CashflowExpenseTransactionSheet(viewModel: cashflowViewModel)
                }
            }
            .sheet(isPresented: $showIncomeSheet) {
                if let cashflowViewModel = cashflowViewModel {
                    CashflowIncomeTransactionSheet(viewModel: cashflowViewModel)
                }
            }
            .sheet(isPresented: $showCashflowHistory) {
                if let cashflowViewModel = cashflowViewModel {
                    CashflowTransactionsHistoryView(viewModel: cashflowViewModel)
                }
            }
            .sheet(isPresented: $showQuickSetupSheet) {
                QuickSetupView(
                    appState: appState,
                    mode: .settings,
                    onCompleted: {
                        showQuickSetupBanner = false
                    }
                )
            }
            .onAppear {
                loadServices()
                showQuickSetupBanner = !SettingsManager.shared.isQuickSetupCompleted
                    && !SettingsManager.shared.isQuickSetupBannerHidden
                prepareCashflowQuickAccess()
                MainWidgetDeepLinkHandler.consumePendingActions(
                    appState: appState,
                    router: router
                )
            }
            .onChange(of: appState.primaryCurrencyCode) { _, _ in
                prepareCashflowQuickAccess()
            }
            .onChange(of: showExpenseSheet) { _, isPresented in
                if isPresented {
                    prepareCashflowQuickAccess()
                } else {
                    cashflowViewModel = nil
                }
            }
            .onChange(of: showIncomeSheet) { _, isPresented in
                if isPresented {
                    prepareCashflowQuickAccess()
                } else {
                    cashflowViewModel = nil
                }
            }
            .onChange(of: showCashflowHistory) { _, isPresented in
                if isPresented {
                    prepareCashflowQuickAccess()
                } else {
                    cashflowViewModel = nil
                }
            }
            .onChange(of: appState.pendingOpenConverterService) { _, _ in
                MainWidgetDeepLinkHandler.consumePendingActions(
                    appState: appState,
                    router: router
                )
            }
            .onChange(of: appState.pendingOpenMainExpenseSheet) { _, _ in
                MainWidgetDeepLinkHandler.consumePendingActions(
                    appState: appState,
                    router: router
                )
            }
            .onChange(of: appState.pendingOpenMainIncomeSheet) { _, _ in
                MainWidgetDeepLinkHandler.consumePendingActions(
                    appState: appState,
                    router: router
                )
            }
        }
    }
    
    private var headerProfileImage: some View {
        let size: CGFloat = 40
        return Group {
            if let path = appState.profileAvatarPath,
               FileManager.default.fileExists(atPath: path),
               let uiImage = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("profile")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var quickSetupBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Быстрая настройка")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("Язык, валюты, категории и продукты за 1 минуту")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)

                Button {
                    showQuickSetupSheet = true
                } label: {
                    Text("Открыть")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(AppColors.textPrimary.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

            Spacer()

            Button {
                showQuickSetupBanner = false
                SettingsManager.shared.isQuickSetupBannerHidden = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(AppColors.textPrimary.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(GlassBackground(gradient: AppColors.financesGradient))
    }
    
    // MARK: - Services Grid
    
    private var servicesGrid: some View {
        VStack(spacing: 12) {
            ForEach(services) { service in
                ServiceButton(
                    title: MainLocalization.text(service.titleKey),
                    icon: service.icon,
                    gradientColors: service.gradientColors
                ) {
                    viewModel.handle(.navigateToService(service.route))
                }
                .frame(maxWidth: .infinity)
                .opacity(draggedService?.id == service.id ? 0.75 : 1.0)
                .onDrag {
                    draggedService = service
                    return NSItemProvider(object: NSString(string: service.id))
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: ServiceReorderDropDelegate(
                        targetService: service,
                        services: $services,
                        draggedService: $draggedService,
                        onReorderFinished: persistServiceOrder
                    )
                )
            }
        }
    }
    
    // MARK: - Helpers
    
    private func loadServices() {
        services = serviceOrderManager.getOrderedServices()
    }

    private func persistServiceOrder() {
        serviceOrderManager.saveOrder(services.map(\.id))
    }

    private func prepareCashflowQuickAccess() {
        let viewModel = CashflowViewModel(modelContext: modelContext)
        viewModel.handle(.syncDisplayCurrencyWithPrimary(appState.primaryCurrencyCode))
        viewModel.handle(.loadCards)
        viewModel.handle(.loadTransactions)
        cashflowViewModel = viewModel
    }
    
    @ViewBuilder
    private func routeView(for route: AppRoute) -> some View {
        switch route {
        case .finances:
            FinancesView()
        case .courses:
            CoursesView()
        case .cashback:
            CashbackView()
        case .cashflow:
            CashflowView()
        case .profile:
            ProfileView(router: router)
        case .subscription:
            SubscriptionView()
        default:
            EmptyView()
        }
    }
}

private struct ServiceReorderDropDelegate: DropDelegate {
    let targetService: ServiceItem
    @Binding var services: [ServiceItem]
    @Binding var draggedService: ServiceItem?
    let onReorderFinished: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedService, draggedService != targetService else { return }
        guard let fromIndex = services.firstIndex(of: draggedService),
              let toIndex = services.firstIndex(of: targetService) else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            services.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedService = nil
        onReorderFinished()
        return true
    }
}

#Preview {
    MainAppView(router: AppRouter())
        .environment(AppState())
}
