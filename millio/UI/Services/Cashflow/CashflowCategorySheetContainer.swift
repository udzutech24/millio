//
//  CashflowCategorySheetContainer.swift
//  millio
//
//  Monzo-style PageTabView: Расходы | Доходы | Все транзакции
//

import SwiftUI

// MARK: - Tab enum

enum CashflowSheetTab: Int, CaseIterable, Identifiable {
    case expenses = 0
    case incomes  = 1
    case all      = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .expenses: return L("cashflow.tab.expenses")
        case .incomes:  return L("cashflow.tab.incomes")
        case .all:      return L("cashflow.tab.all")
        }
    }
}

// MARK: - Container

struct CashflowCategorySheetContainer: View {
    @ObservedObject var viewModel: CashflowViewModel
    /// Начальная вкладка задаётся caller'ом (income/expense → первая/вторая, transfer → all).
    var initialTab: CashflowSheetTab

    @State private var selectedTab: CashflowSheetTab

    init(viewModel: CashflowViewModel, initialTab: CashflowSheetTab = .expenses) {
        self.viewModel = viewModel
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentPicker

            TabView(selection: $selectedTab) {
                CashflowCategoryTransactionSheet(
                    viewModel: viewModel,
                    kind: .expense,
                    initialHistoryCardID: nil
                )
                .tag(CashflowSheetTab.expenses)

                CashflowCategoryTransactionSheet(
                    viewModel: viewModel,
                    kind: .income,
                    initialHistoryCardID: nil
                )
                .tag(CashflowSheetTab.incomes)

                CashflowTransactionsHistoryView(
                    viewModel: viewModel,
                    showsDismissButton: true,
                    initialFilter: .all
                )
                .tag(CashflowSheetTab.all)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: selectedTab)
        }
        .background(Color.black)
    }

    // MARK: - Segment picker

    private var segmentPicker: some View {
        HStack(spacing: 4) {
            ForEach(CashflowSheetTab.allCases) { tab in
                segmentButton(for: tab)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func segmentButton(for tab: CashflowSheetTab) -> some View {
        let isSelected = selectedTab == tab
        let fg: Color = isSelected ? AppColors.textPrimary : AppColors.textPrimary.opacity(0.5)
        let bg: Color = isSelected ? Color.white.opacity(0.12) : .clear
        return Button(tab.title) {
            withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
        }
        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(fg)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(bg, in: Capsule())
        .animation(.easeInOut(duration: 0.18), value: selectedTab)
    }
}
