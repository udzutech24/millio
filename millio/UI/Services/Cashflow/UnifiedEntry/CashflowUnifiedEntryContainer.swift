//
//  CashflowUnifiedEntryContainer.swift
//  millio
//
//  Единый свайп-контейнер add-flow: Расход | Доход | Перевод (Фаза 3 редизайна).
//  Таб «Всё» (browse-history) убран по требованию владельца (§2.1.2) — история
//  доступна отдельной точкой входа на главном экране Cashflow.
//

import SwiftUI

// MARK: - Tab enum

enum CashflowSheetTab: Int, CaseIterable, Identifiable {
    case expenses = 0
    case incomes  = 1
    case transfer = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .expenses: return L("cashflow.tab.expenses")
        case .incomes:  return L("cashflow.tab.incomes")
        case .transfer: return L("cashflow.tab.transfer")
        }
    }
}

// MARK: - Container

struct CashflowUnifiedEntryContainer: View {
    @ObservedObject var viewModel: CashflowViewModel
    /// Начальная вкладка задаётся caller'ом (income/expense/transfer → соответствующий таб).
    var initialTab: CashflowSheetTab
    let initialMonth: Date?

    @State private var selectedTab: CashflowSheetTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        viewModel: CashflowViewModel,
        initialTab: CashflowSheetTab = .expenses,
        initialMonth: Date? = nil
    ) {
        self.viewModel = viewModel
        self.initialTab = initialTab
        self.initialMonth = initialMonth
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentPicker

            TabView(selection: $selectedTab) {
                CashflowCategoryTransactionSheet(
                    viewModel: viewModel,
                    kind: .expense,
                    initialHistoryCardID: nil,
                    initialMonth: initialMonth
                )
                .tag(CashflowSheetTab.expenses)

                CashflowCategoryTransactionSheet(
                    viewModel: viewModel,
                    kind: .income,
                    initialHistoryCardID: nil,
                    initialMonth: initialMonth
                )
                .tag(CashflowSheetTab.incomes)

                // Перевод: полный редактор без секции выбора типа операции —
                // функционально идентичен прежнему CashflowTransferTransactionSheet.
                CashflowTransactionEditorView(
                    viewModel: viewModel,
                    transactionType: .transfer,
                    showsTransactionTypeSection: false,
                    customNavigationTitle: L("cashflow.operation.new_transfer"),
                    initialTransactionDate: initialMonth.map {
                        CashflowCategorySheetBootstrap.initialTransactionDate(forSelectedMonth: $0)
                    },
                    refreshesAccountsOnAppear: false
                )
                .tag(CashflowSheetTab.transfer)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? nil : AppAnimation.medium, value: selectedTab)
            .onChange(of: selectedTab) { oldValue, newValue in
                let signpostID = CashflowUnifiedEntryTelemetry.beginTabTransition(from: oldValue, to: newValue)
                Task { @MainActor in
                    try? await Task.sleep(
                        nanoseconds: CashflowUnifiedEntryTelemetry.tabTransitionSettlingNanoseconds
                    )
                    CashflowUnifiedEntryTelemetry.endTabTransition(signpostID, selectedTab: newValue)
                }
            }
        }
        .background(Color.black)
        // Сегменты — страницы TabView, поэтому их собственный .onAppear срабатывает на КАЖДОЕ
        // переключение. Загрузка счетов и всей ленты операций (prepare) должна выполняться один раз
        // на открытие экрана ввода, иначе тап по сегменту тянет работу масштаба холодного старта
        // на том же потоке, что рисует анимацию перелистывания.
        //
        // Порядок относительно .onAppear страниц не важен: prepare() синхронен, а месячный срез
        // страницы считается в MainActor-Task, который стартует только после всего прохода обновления
        // SwiftUI — то есть state.transactions к этому моменту уже заполнен.
        .onAppear {
            CashflowCategorySheetBootstrap.prepare(viewModel: viewModel)
        }
    }

    // MARK: - Segment picker

    private var segmentPicker: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(CashflowSheetTab.allCases) { tab in
                segmentButton(for: tab)
            }
        }
        .padding(.horizontal, AppSpacing.l)
        .padding(.top, AppSpacing.m)
        .padding(.bottom, AppSpacing.s)
    }

    private func segmentButton(for tab: CashflowSheetTab) -> some View {
        let isSelected = selectedTab == tab
        let fg: Color = isSelected ? AppColors.textPrimary : AppColors.textPrimary.opacity(0.5)
        let bg: Color = isSelected ? Color.white.opacity(0.12) : .clear
        return Button(tab.title) {
            selectedTab = tab
        }
        .font(isSelected ? .millioBodySemibold : .millioBodyRegular)
        .foregroundStyle(fg)
        .padding(.horizontal, AppSpacing.ml)
        .padding(.vertical, AppSpacing.s)
        .background(bg, in: Capsule())
        .accessibilityIdentifier("cashflow.unified.tab.\(tab.rawValue)")
    }
}
