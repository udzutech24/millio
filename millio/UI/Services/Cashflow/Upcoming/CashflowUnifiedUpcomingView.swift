import SwiftUI
import SwiftData

/// Read-first destination for the complete mixed-source forecast.
struct CashflowUnifiedUpcomingView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @State private var filter: CashflowUpcomingFilter = .all
    @State private var editingTransaction: CashflowTransaction?
    @State private var selectedDepositAccount: Account?
    @State private var createKind: CashflowCategoryKind = .expense
    @State private var showCreateSheet = false

    private var items: [CashflowUpcomingItem] { viewModel.allUpcomingItems() }

    private var sections: [CashflowUpcomingDaySection] {
        CashflowUpcomingPresentation.sections(from: items, filter: filter, calendar: .current)
    }

    var body: some View {
        ZStack {
            GradientBackground()
            List {
                Picker(CashflowUpcomingLocalization.filterAccessibilityLabel, selection: $filter) {
                    ForEach(CashflowUpcomingFilter.allCases) { value in
                        Text(CashflowUpcomingLocalization.title(for: value)).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if sections.isEmpty {
                    Text(CashflowUpcomingLocalization.empty)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { item in
                                row(item)
                            }
                        } header: {
                            Text(dateText(section.day))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(CashflowUpcomingLocalization.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(CashflowUpcomingLocalization.addIncome) { create(.income) }
                    Button(CashflowUpcomingLocalization.addExpense) { create(.expense) }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(CashflowUpcomingLocalization.addAccessibilityLabel)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CashflowTransactionEditorView(
                viewModel: viewModel,
                transactionType: createKind == .income ? .income : .expense,
                showsTransactionTypeSection: false,
                showsRecurrenceSection: true,
                onSave: { showCreateSheet = false }
            )
        }
        .sheet(item: $editingTransaction) { transaction in
            CashflowTransactionEditorView(
                viewModel: viewModel,
                transaction: transaction,
                showsTransactionTypeSection: false,
                showsRecurrenceSection: true,
                onSave: { editingTransaction = nil }
            )
        }
        .sheet(item: $selectedDepositAccount) { account in
            NavigationStack {
                AccountDetailView(account: account, modelContext: viewModel.modelContext)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: CashflowUpcomingItem) -> some View {
        if item.source == .depositInterest {
            Button {
                open(item)
            } label: {
                rowContent(item, showsDisclosureIndicator: true)
            }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(CashflowUpcomingLocalization.accessibilityLabel(for: item, date: dateText(item.date)))
                .accessibilityHint(CashflowUpcomingLocalization.openAccountHint)
                .listRowBackground(Color.white.opacity(0.035))
        } else {
            Button {
                open(item)
            } label: {
                rowContent(item, showsDisclosureIndicator: false)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(CashflowUpcomingLocalization.accessibilityLabel(for: item, date: dateText(item.date)))
            .accessibilityHint(CashflowUpcomingLocalization.editHint)
            .listRowBackground(Color.white.opacity(0.035))
        }
    }

    private func rowContent(_ item: CashflowUpcomingItem, showsDisclosureIndicator: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.millioBodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                Text(CashflowUpcomingLocalization.subtitle(for: item))
                    .font(.millioCaption2)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(amountText(item))
                    .font(.millioBodySemibold)
                    .foregroundStyle(item.kind == .income ? AppColors.positiveColor : AppColors.negativeColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.millioCaption2)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(.vertical, 5)
    }

    private func open(_ item: CashflowUpcomingItem) {
        switch item.reference {
        case .transaction(let persistentID):
            editingTransaction = viewModel.state.transactions.first { $0.persistentModelID == persistentID }
        case .deposit(let accountID):
            let accounts = (try? viewModel.modelContext.fetch(FetchDescriptor<Account>())) ?? []
            selectedDepositAccount = CashflowUpcomingAccountResolver.resolve(accountID: accountID, in: accounts)
        }
    }

    private func create(_ kind: CashflowCategoryKind) {
        createKind = kind
        showCreateSheet = true
    }

    private func amountText(_ item: CashflowUpcomingItem) -> String {
        let signedAmount = item.kind == .income ? item.amount : -item.amount
        return "\(cashflowSignedAmountText(signedAmount)) \(cashflowCurrencyCodeLabel(item.currencyCode))"
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter.string(from: date)
    }
}
