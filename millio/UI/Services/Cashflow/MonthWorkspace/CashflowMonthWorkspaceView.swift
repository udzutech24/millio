import SwiftUI
import SwiftData

struct CashflowMonthWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CashflowMonthClosureEvent.occurredAt, order: .reverse) private var closureEvents: [CashflowMonthClosureEvent]
    @ObservedObject var viewModel: CashflowViewModel
    let statementClient: any CashflowStatementImportClient
    @State private var selectedMonth: Date
    @State private var filter: CashflowMonthFilter = .expense
    @State private var showImportHub = false
    @State private var showClosureChecklist = false
    @State private var showCloseConfirmation = false
    @State private var showReopenConfirmation = false
    @State private var showMonthPicker = false

    init(
        viewModel: CashflowViewModel,
        month: Date,
        statementClient: any CashflowStatementImportClient = UnavailableCashflowStatementImportClient()
    ) {
        self.viewModel = viewModel
        _selectedMonth = State(initialValue: CashflowMonthSelectionPolicy.canonicalMonth(month))
        self.statementClient = statementClient
    }

    private var monthTransactions: [CashflowTransaction] {
        let calendar = Calendar.autoupdatingCurrent
        return viewModel.state.transactions
            .filter { calendar.isDate($0.transactionDate, equalTo: selectedMonth, toGranularity: .month) }
            .filter { $0.transactionType == filter.transactionType }
            .filter(\.shouldAffectCashflowTotals)
            .sorted { $0.transactionDate > $1.transactionDate }
    }

    private var total: Double { monthTransactions.reduce(0) { $0 + $1.amount } }

    private var isClosed: Bool {
        guard let interval = Calendar.autoupdatingCurrent.dateInterval(of: .month, for: selectedMonth) else { return false }
        return closureEvents.first { interval.contains($0.monthStart) }?.kind == .close
    }

    private var readiness: CashflowMonthReadiness {
        CashflowMonthReadinessCalculator.calculate(.init(
            month: selectedMonth, now: .now, unresolvedImportRows: 0, duplicateRows: 0,
            uncategorizedRows: 0, reconciliationPassed: nil, accountAndMonthMatch: true,
            pendingScheduledWrites: 0
        ))
    }

    var body: some View {
        ZStack {
            CashflowSurfaceStyle.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    monthHero

                    Picker("", selection: $filter) {
                        Text(CashflowMonthWorkspaceLocalization.expense).tag(CashflowMonthFilter.expense)
                        Text(CashflowMonthWorkspaceLocalization.income).tag(CashflowMonthFilter.income)
                        Text(CashflowMonthWorkspaceLocalization.transfer).tag(CashflowMonthFilter.transfer)
                    }
                    .pickerStyle(.segmented)
                    .tint(CashflowSurfaceStyle.accent)

                    summaryCard
                    transactionsContent
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 92)
            }
        }
        .safeAreaInset(edge: .bottom) { monthActions }
        .navigationTitle(monthTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { monthManagementToolbar }
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { viewModel.state.showTransactionEditor },
            set: { if !$0 { viewModel.handle(.hideTransactionEditor) } }
        )) {
            if let type = viewModel.state.creatingTransactionType {
                CashflowUnifiedEntryContainer(
                    viewModel: viewModel,
                    initialTab: unifiedTab(for: type),
                    initialMonth: selectedMonth
                )
            }
        }
        .sheet(isPresented: $showImportHub) {
            CashflowImportHubView(viewModel: viewModel, month: selectedMonth, statementClient: statementClient)
        }
        .sheet(isPresented: $showMonthPicker) {
            CashflowMonthPickerSheet(selection: $selectedMonth)
        }
        .sheet(isPresented: $showClosureChecklist) {
            NavigationStack {
                List {
                    Label(
                        readiness.canClose ? CashflowMonthWorkspaceLocalization.ready : CashflowMonthWorkspaceLocalization.notReady,
                        systemImage: readiness.canClose ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    Text(CashflowMonthWorkspaceLocalization.closeExplanation)
                        .foregroundStyle(.secondary)
                }
                .navigationTitle(CashflowMonthWorkspaceLocalization.closeMonth)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(CashflowMonthWorkspaceLocalization.cancel) { showClosureChecklist = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(CashflowMonthWorkspaceLocalization.closeMonth) {
                            showClosureChecklist = false
                            showCloseConfirmation = true
                        }
                        .disabled(!readiness.canClose)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(CashflowMonthWorkspaceLocalization.confirmClose, isPresented: $showCloseConfirmation) {
            Button(CashflowMonthWorkspaceLocalization.closeMonth, role: .destructive) {
                try? CashflowMonthClosureService(modelContext: modelContext).close(
                    month: selectedMonth,
                    readiness: readiness,
                    evidenceJSON: "{\"source\":\"month_workspace\"}"
                )
            }
            Button(CashflowMonthWorkspaceLocalization.cancel, role: .cancel) {}
        } message: {
            Text(CashflowMonthWorkspaceLocalization.closeExplanation)
        }
        .confirmationDialog(CashflowMonthWorkspaceLocalization.confirmReopen, isPresented: $showReopenConfirmation) {
            Button(CashflowMonthWorkspaceLocalization.reopenMonth) {
                try? CashflowMonthClosureService(modelContext: modelContext).reopen(month: selectedMonth)
            }
            Button(CashflowMonthWorkspaceLocalization.cancel, role: .cancel) {}
        }
        .onAppear {
            viewModel.handle(.loadTransactions)
            viewModel.handle(.setSelectedMonth(selectedMonth))
        }
        .onChange(of: selectedMonth) { _, value in
            let canonical = CashflowMonthSelectionPolicy.canonicalMonth(value)
            if canonical != value {
                selectedMonth = canonical
            }
            viewModel.handle(.setSelectedMonth(canonical))
        }
    }

    @ToolbarContentBuilder
    private var monthManagementToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    if isClosed { showReopenConfirmation = true } else { showClosureChecklist = true }
                } label: {
                    Label(
                        isClosed ? CashflowMonthWorkspaceLocalization.reopenMonth : CashflowMonthWorkspaceLocalization.closeMonth,
                        systemImage: isClosed ? "lock.open" : "lock"
                    )
                }
                .disabled(!isClosed && !readiness.canClose)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(CashflowMonthWorkspaceLocalization.monthActions)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(filterTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CashflowSurfaceStyle.secondaryText)
                Spacer()
                Text("\(cashflowAmountText(total)) \(cashflowCurrencyCodeLabel(viewModel.state.displayCurrency))")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
            }

            HStack(spacing: 8) {
                Image(systemName: isClosed ? "lock.fill" : "lock.open")
                Text(isClosed ? CashflowMonthWorkspaceLocalization.closed : CashflowMonthWorkspaceLocalization.open)
                Spacer()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isClosed ? Color.orange : CashflowSurfaceStyle.secondaryText)

            if isClosed {
                Text(CashflowMonthWorkspaceLocalization.closedExplanation)
                    .font(.footnote)
                    .foregroundStyle(CashflowSurfaceStyle.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(CashflowSurfaceStyle.card())
    }

    @ViewBuilder
    private var transactionsContent: some View {
        if monthTransactions.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.title)
                    .foregroundStyle(CashflowSurfaceStyle.secondaryText)
                Text(CashflowMonthWorkspaceLocalization.noTransactions)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(CashflowMonthWorkspaceLocalization.emptyHint)
                    .font(.subheadline)
                    .foregroundStyle(CashflowSurfaceStyle.secondaryText)
                    .multilineTextAlignment(.center)
                Button(CashflowMonthWorkspaceLocalization.importData) { showImportHub = true }
                    .buttonStyle(.bordered)
                    .tint(CashflowSurfaceStyle.secondaryText)
                    .disabled(isClosed)
            }
            .frame(maxWidth: .infinity, minHeight: 210)
            .padding(20)
            .background(CashflowSurfaceStyle.card())
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(monthTransactions.enumerated()), id: \.element.id) { index, transaction in
                    transactionRow(transaction)
                    if index < monthTransactions.count - 1 {
                        Divider().overlay(CashflowSurfaceStyle.separator)
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(CashflowSurfaceStyle.card())
        }
    }

    private func transactionRow(_ transaction: CashflowTransaction) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: transaction.transactionType.icon)
                .foregroundStyle(transaction.transactionType == .expense ? CashflowSurfaceStyle.negative : CashflowSurfaceStyle.positive)
                .frame(width: 30, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.note?.isEmpty == false ? transaction.note! : transaction.transactionType.displayName)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(transaction.transactionDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(CashflowSurfaceStyle.secondaryText)
            }
            Spacer(minLength: 8)
            Text("\(cashflowAmountText(transaction.amount)) \(cashflowCurrencyCodeLabel(transaction.currency))")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var monthHero: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                monthArrow(systemImage: "chevron.left", offset: -1, label: CashflowMonthWorkspaceLocalization.previousMonth)
                Button { showMonthPicker = true } label: {
                    VStack(spacing: 5) {
                        Text(monthTitle)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Label(CashflowMonthWorkspaceLocalization.chooseMonth, systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CashflowSurfaceStyle.accent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(CashflowMonthWorkspaceLocalization.chooseMonth): \(monthTitle)")
                .accessibilityHint(CashflowMonthWorkspaceLocalization.chooseMonthHint)
                monthArrow(systemImage: "chevron.right", offset: 1, label: CashflowMonthWorkspaceLocalization.nextMonth)
            }
            Text(isClosed ? CashflowMonthWorkspaceLocalization.closedExplanation : CashflowMonthWorkspaceLocalization.monthDestinationHint(monthTitle))
                .font(.caption)
                .foregroundStyle(isClosed ? .orange : CashflowSurfaceStyle.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .background(CashflowSurfaceStyle.card())
    }

    private var monthActions: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                monthActionButton(
                    title: CashflowMonthWorkspaceLocalization.add,
                    subtitle: monthTitle,
                    systemImage: "plus.circle.fill",
                    prominent: true,
                    action: addTransaction
                )
                monthActionButton(
                    title: CashflowMonthWorkspaceLocalization.importData,
                    subtitle: monthTitle,
                    systemImage: "arrow.down.doc.fill",
                    prominent: false,
                    action: { showImportHub = true }
                )
            }
            if isClosed {
                Label(CashflowMonthWorkspaceLocalization.closedExplanation, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.94))
    }

    private func monthActionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.subheadline.weight(.bold)).lineLimit(1)
                    Text(subtitle).font(.caption2).lineLimit(1).opacity(0.8)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(prominent ? CashflowSurfaceStyle.accent : Color.white.opacity(0.90))
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(CashflowSurfaceStyle.actionCard(isProminent: prominent))
        }
        .buttonStyle(.plain)
        .disabled(isClosed)
        .accessibilityIdentifier(prominent ? "cashflow.month.add" : "cashflow.month.import")
        .accessibilityLabel("\(title), \(monthTitle)")
        .accessibilityHint(isClosed ? CashflowMonthWorkspaceLocalization.closedExplanation : "")
    }

    private func monthArrow(systemImage: String, offset: Int, label: String) -> some View {
        Button {
            if let value = CashflowMonthSelectionPolicy.offset(selectedMonth, by: offset) {
                selectedMonth = value
            }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var filterTitle: String {
        switch filter {
        case .expense: CashflowMonthWorkspaceLocalization.expense
        case .income: CashflowMonthWorkspaceLocalization.income
        case .transfer: CashflowMonthWorkspaceLocalization.transfer
        }
    }

    private var monthTitle: String {
        selectedMonth.formatted(.dateTime.month(.wide).year().locale(AppLocalization.currentAppLocale))
    }

    private func addTransaction() { viewModel.handle(.addTransaction(filter.transactionType)) }

    private func unifiedTab(for type: CashflowTransactionType) -> CashflowSheetTab {
        switch type {
        case .income: .incomes
        case .expense: .expenses
        default: .transfer
        }
    }
}
