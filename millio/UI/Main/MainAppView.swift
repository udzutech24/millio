//
//  MainAppView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
                        .accessibilityLabel("История операций")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    // Service buttons grid
                    servicesGrid
                        .padding(.horizontal, 24)
                        .padding(.top, 34)
                    
                    Spacer()
                    
                    // Bottom action buttons
                    HStack(spacing: 16) {
                        ActionButton(
                            title: "Расход",
                            icon: .asset("minus"),
                            gradientColors: AppColors.expenseGradient
                        ) {
                            showExpenseSheet = true
                        }
                        
                        ActionButton(
                            title: "Доход",
                            icon: .asset("Plus"),
                            gradientColors: AppColors.incomeGradient
                        ) {
                            showIncomeSheet = true
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
            .onAppear {
                loadServices()
                if cashflowViewModel == nil {
                    cashflowViewModel = CashflowViewModel(modelContext: modelContext)
                }
                
                // Обновляем статус подписки при открытии главного экрана
                Task {
                    await SubscriptionManager.shared.checkSubscriptionStatus()
                    appState.subscriptionStatus = SubscriptionManager.shared.status
                    appState.subscriptionExpirationDate = SubscriptionManager.shared.expirationDate
                    appState.isTrialActive = SubscriptionManager.shared.isTrialActive
                }
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
    
    // MARK: - Services Grid
    
    private var servicesGrid: some View {
        VStack(spacing: 8) {
            ForEach(services) { service in
                ServiceButton(
                    title: service.title,
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
