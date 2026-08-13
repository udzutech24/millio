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
        VStack(spacing: 0) {
            monthHero

            Picker("", selection: $filter) {
                Text(CashflowMonthWorkspaceLocalization.expense).tag(CashflowMonthFilter.expense)
                Text(CashflowMonthWorkspaceLocalization.income).tag(CashflowMonthFilter.income)
                Text(CashflowMonthWorkspaceLocalization.transfer).tag(CashflowMonthFilter.transfer)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            List {
                Section {
                    HStack {
                        Text(filterTitle)
                        Spacer()
                        Text("\(cashflowAmountText(total)) \(cashflowCurrencyCodeLabel(viewModel.state.displayCurrency))")
                            .font(.headline.monospacedDigit())
                    }

                    Label(
                        isClosed ? CashflowMonthWorkspaceLocalization.closed : CashflowMonthWorkspaceLocalization.open,
                        systemImage: isClosed ? "lock.fill" : "lock.open"
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if isClosed {
                        Text(CashflowMonthWorkspaceLocalization.closedExplanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button(isClosed ? CashflowMonthWorkspaceLocalization.reopenMonth : CashflowMonthWorkspaceLocalization.closeMonth) {
                        if isClosed { showReopenConfirmation = true } else { showClosureChecklist = true }
                    }
                    .disabled(!isClosed && !readiness.canClose)
                }

                if monthTransactions.isEmpty {
                    ContentUnavailableView {
                        Label(CashflowMonthWorkspaceLocalization.noTransactions, systemImage: "tray")
                    } description: {
                        Text(CashflowMonthWorkspaceLocalization.emptyHint)
                    } actions: {
                        Button(CashflowMonthWorkspaceLocalization.statement) { showImportHub = true }
                            .disabled(isClosed)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(monthTransactions) { transaction in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: transaction.transactionType.icon)
                                    .frame(width: 28, height: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(transaction.note?.isEmpty == false ? transaction.note! : transaction.transactionType.displayName)
                                        .lineLimit(2)
                                    Text(transaction.transactionDate, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(cashflowAmountText(transaction.amount)) \(cashflowCurrencyCodeLabel(transaction.currency))")
                                    .font(.body.monospacedDigit())
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            monthActions
        }
        .navigationTitle(monthTitle)
        .navigationBarTitleDisplayMode(.inline)
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

    private var monthSelector: some View {
        HStack(spacing: 12) {
            monthArrow(systemImage: "chevron.left", offset: -1, label: CashflowMonthWorkspaceLocalization.previousMonth)
            Button {
                showMonthPicker = true
            } label: {
                VStack(spacing: 2) {
                    Text(monthTitle)
                        .font(.headline)
                    Text(CashflowMonthWorkspaceLocalization.wholeMonthHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(CashflowMonthWorkspaceLocalization.chooseMonth): \(monthTitle)")
            monthArrow(systemImage: "chevron.right", offset: 1, label: CashflowMonthWorkspaceLocalization.nextMonth)
        }
    }

    private var monthHero: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                monthArrow(systemImage: "chevron.left", offset: -1, label: CashflowMonthWorkspaceLocalization.previousMonth)
                Button { showMonthPicker = true } label: {
                    VStack(spacing: 5) {
                        Text(monthTitle)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)
                        Label("Выбрать месяц", systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(CashflowMonthWorkspaceLocalization.chooseMonth): \(monthTitle)")
                .accessibilityHint("Открывает календарь выбора месяца")
                monthArrow(systemImage: "chevron.right", offset: 1, label: CashflowMonthWorkspaceLocalization.nextMonth)
            }
            Text(isClosed ? "Месяц закрыт — просмотр доступен, изменения заблокированы" : "Все новые операции и импорт попадут в \(monthTitle)")
                .font(.caption)
                .foregroundStyle(isClosed ? .orange : .secondary)
                .multilineTextAlignment(.center)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.accentColor.opacity(0.16), lineWidth: 1)
        }
        .padding(.horizontal)
        .padding(.top, 6)
        .padding(.bottom, 12)
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
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
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
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(isClosed)
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
