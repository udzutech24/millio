import SwiftData
import SwiftUI

enum CashflowStatementReviewLocalization {
    static var monthHint: String { L("cashflow.statement_review.month_hint") }
    static var reconciliationPassed: String { L("cashflow.statement_review.reconciliation_passed") }
    static var reconciliationAttention: String { L("cashflow.statement_review.reconciliation_attention") }
    static var reviewMode: String { L("cashflow.statement_review.review_mode") }
    static var needsAttention: String { L("cashflow.statement_review.needs_attention") }
    static var categories: String { L("cashflow.statement_review.categories") }
    static var all: String { L("cashflow.statement_review.all") }
    static var searchPrompt: String { L("cashflow.statement_review.search_prompt") }
    static var title: String { L("cashflow.statement_review.title") }
    static var noImportableOperations: String { L("cashflow.statement_review.no_importable_operations") }
    static var confirmationHint: String { L("cashflow.statement_review.confirmation_hint") }
    static var reviewedEmptyTitle: String { L("cashflow.statement_review.reviewed_empty_title") }
    static var reviewedEmptyDescription: String { L("cashflow.statement_review.reviewed_empty_description") }
    static var category: String { L("cashflow.statement_review.category") }
    static var transferExcluded: String { L("cashflow.statement_review.transfer_excluded") }
    static var reclassify: String { L("cashflow.statement_review.reclassify") }
    static var asExpense: String { L("cashflow.statement_review.as_expense") }
    static var asIncome: String { L("cashflow.statement_review.as_income") }
    static var internalTransferExcluded: String { L("cashflow.statement_review.internal_transfer_excluded") }
    static var duplicateExcluded: String { L("cashflow.statement_review.duplicate_excluded") }
    static var technicalExcluded: String { L("cashflow.statement_review.technical_excluded") }
    static var userExcluded: String { L("cashflow.statement_review.user_excluded") }
    static var excludeAllTransfers: String { L("cashflow.statement_review.exclude_all_transfers") }
    static var month: String { L("cashflow.statement_review.month") }
    static var proposedImport: String { L("cashflow.statement_review.proposed_import") }
    static var importedCount: String { L("cashflow.statement_review.imported_count") }
    static var excludedCount: String { L("cashflow.statement_review.excluded_count") }
    static var reclassifiedCount: String { L("cashflow.statement_review.reclassified_count") }
    static var sourceReconciliation: String { L("cashflow.statement_review.source_reconciliation") }
    static var balanced: String { L("cashflow.statement_review.balanced") }
    static var discrepancy: String { L("cashflow.statement_review.discrepancy") }
    static var difference: String { L("cashflow.statement_review.difference") }
    static var account: String { L("cashflow.statement_review.account") }
    static var linkToAccount: String { L("cashflow.statement_review.link_to_account") }
    static var noMatchingAccounts: String { L("cashflow.statement_review.no_matching_accounts") }
    static var selectAccount: String { L("cashflow.statement_review.select_account") }
    static var balanceUnchanged: String { L("cashflow.statement_review.balance_unchanged") }
    static var confirmationTitle: String { L("cashflow.statement_review.confirmation_title") }
    static var cancel: String { L("common.cancel") }
    static var openReview: String { L("cashflow.statement_review.open_review") }

    static func operationCount(_ count: Int) -> String {
        String.localizedStringWithFormat(L("cashflow.statement_review.operation_count"), count)
    }

    static func importCount(_ count: Int) -> String {
        String.localizedStringWithFormat(L("cashflow.statement_review.import_count"), count)
    }

    static func confirmImportCount(_ count: Int) -> String {
        String.localizedStringWithFormat(L("cashflow.statement_review.confirm_import_count"), count)
    }
}

struct CashflowStatementReviewView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @ObservedObject var controller: CashflowStatementImportController
    let month: Date
    let context: CashflowStatementReviewContext
    @Environment(\.modelContext) private var modelContext
    @State private var filter: CashflowStatementReviewFilter = .needsAttention
    @State private var searchText = ""
    @State private var showConfirmation = false

    init(
        viewModel: CashflowViewModel,
        controller: CashflowStatementImportController,
        month: Date,
        context: CashflowStatementReviewContext = .cashflowImport
    ) {
        self.viewModel = viewModel
        self.controller = controller
        self.month = month
        self.context = context
    }

    private var rows: [CashflowStatementReviewRow] {
        let filtered = CashflowStatementReviewPresentationBuilder.rows(controller.reviewRows, filter: filter)
        guard !searchText.isEmpty else { return filtered }
        return filtered.filter { $0.operation.description.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(month.formatted(.dateTime.month(.wide).year().locale(AppLocalization.currentAppLocale)))
                            .font(.headline)
                        Text(CashflowStatementReviewLocalization.monthHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let preview = controller.preview {
                    Label(
                        preview.reconciliation.balanced ? CashflowStatementReviewLocalization.reconciliationPassed : CashflowStatementReviewLocalization.reconciliationAttention,
                        systemImage: preview.reconciliation.balanced ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(preview.reconciliation.balanced ? .green : .orange)
                }
            }

            Picker(CashflowStatementReviewLocalization.reviewMode, selection: $filter) {
                Text(CashflowStatementReviewLocalization.needsAttention).tag(CashflowStatementReviewFilter.needsAttention)
                Text(CashflowStatementReviewLocalization.categories).tag(CashflowStatementReviewFilter.categories)
                Text(CashflowStatementReviewLocalization.all).tag(CashflowStatementReviewFilter.all)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            if filter == .categories {
                categoryGroups
            } else {
                operationRows
            }
        }
        .searchable(text: $searchText, prompt: CashflowStatementReviewLocalization.searchPrompt)
        .navigationTitle(CashflowStatementReviewLocalization.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                switch context {
                case .cashflowImport:
                    showConfirmation = true
                case .accountOnboarding(let continueReview):
                    continueReview()
                }
            } label: {
                Label(
                    context.isAccountOnboarding
                        ? String(localized: "finances.statement.continue", defaultValue: "Continue")
                        : CashflowStatementReviewLocalization.importCount(controller.includedFingerprints.count),
                    systemImage: "checkmark.shield.fill"
                )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.includedFingerprints.isEmpty && !context.isAccountOnboarding)
            .accessibilityHint(
                controller.includedFingerprints.isEmpty && !context.isAccountOnboarding
                    ? CashflowStatementReviewLocalization.noImportableOperations
                    : CashflowStatementReviewLocalization.confirmationHint
            )
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showConfirmation) {
            CashflowStatementConfirmationView(
                viewModel: viewModel,
                controller: controller,
                month: month,
                apply: applyReviewed
            )
        }
    }

    @ViewBuilder
    private var operationRows: some View {
        if rows.isEmpty {
            ContentUnavailableView(CashflowStatementReviewLocalization.reviewedEmptyTitle, systemImage: "checkmark.circle", description: Text(CashflowStatementReviewLocalization.reviewedEmptyDescription))
                .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(rows) { row in rowView(row) }
            }
            transferActions
        }
    }

    private var categoryGroups: some View {
        ForEach(CashflowStatementReviewPresentationBuilder.groups(rows: controller.reviewRows)) { group in
            Section {
                DisclosureGroup {
                    ForEach(group.rows) { row in rowView(row) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(categoryTitle(group.key.categoryRaw, kind: group.key.kind))
                            Text(CashflowStatementReviewLocalization.operationCount(group.rows.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(group.amount, format: .currency(code: group.key.currency))
                            .font(.body.monospacedDigit().weight(.semibold))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: CashflowStatementReviewRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.operation.description).lineLimit(2)
                    Text(row.operation.operationDate).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(row.amount, format: .currency(code: row.currency))
                    .font(.body.monospacedDigit())
            }
            dispositionControls(row)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func dispositionControls(_ row: CashflowStatementReviewRow) -> some View {
        switch row.disposition {
        case .included(let kind):
            Picker(CashflowStatementReviewLocalization.category, selection: Binding(
                get: { controller.categoryByFingerprint[row.id] ?? "other" },
                set: { controller.setCategory($0, for: row.operation) }
            )) {
                ForEach(viewModel.categoryOptions(for: kind), id: \.rawValue) { option in
                    Label(option.displayName, systemImage: option.icon).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
        case .excludedExternalTransfer:
            HStack {
                Label(CashflowStatementReviewLocalization.transferExcluded, systemImage: "arrow.left.arrow.right")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu(CashflowStatementReviewLocalization.reclassify) {
                    Button(CashflowStatementReviewLocalization.asExpense) { controller.reclassifyExternalTransfer(row.operation, as: .expense, categoryRaw: "other") }
                    Button(CashflowStatementReviewLocalization.asIncome) { controller.reclassifyExternalTransfer(row.operation, as: .income, categoryRaw: "other") }
                }
            }
        case .excludedInternalTransfer:
            Label(CashflowStatementReviewLocalization.internalTransferExcluded, systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
        case .excludedDuplicate:
            Label(CashflowStatementReviewLocalization.duplicateExcluded, systemImage: "doc.on.doc")
                .font(.caption).foregroundStyle(.secondary)
        case .excludedTechnical:
            Label(CashflowStatementReviewLocalization.technicalExcluded, systemImage: "gearshape")
                .font(.caption).foregroundStyle(.secondary)
        case .excludedByUser:
            Label(CashflowStatementReviewLocalization.userExcluded, systemImage: "minus.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var transferActions: some View {
        if controller.reviewRows.contains(where: { $0.operation.type.hasPrefix("transfer_") }) {
            Section {
                Button(CashflowStatementReviewLocalization.excludeAllTransfers) { controller.excludeAllTransfers() }
            }
        }
    }

    private func categoryTitle(_ raw: String, kind: CashflowCategoryKind) -> String {
        viewModel.categoryOption(for: raw, kind: kind).displayName
    }

    private func applyReviewed(accountID: String?) {
        guard let preview = controller.preview else { return }
        if let accountID {
            viewModel.handle(.loadCards)
            let options = CashflowStatementAccountSelectionPolicy.options(
                cards: viewModel.state.availableCards,
                newCoreAccounts: viewModel.newCoreAccountsForCashflowPicker(),
                statementCurrencies: Set(controller.reviewRows.filter(\.disposition.isIncluded).map(\.currency))
            )
            guard CashflowStatementAccountSelectionPolicy.isValid(accountID, in: options) else {
                controller.markApplyFailure()
                return
            }
        }
        guard let operations = try? CashflowApprovedStatementOperationBuilder.build(
            preview: preview,
            controller: controller,
            accountID: accountID
        ) else {
            controller.markApplyFailure()
            return
        }
        controller.markApplying()
        do {
            let result = try CashflowStatementApplyService(modelContext: modelContext).apply(operations)
            controller.markCompleted(result: result)
            viewModel.handle(.loadTransactions)
            showConfirmation = false
        } catch {
            controller.markApplyFailure()
        }
    }
}

enum CashflowStatementReviewContext {
    case cashflowImport
    case accountOnboarding(continueReview: () -> Void)

    var isAccountOnboarding: Bool {
        if case .accountOnboarding = self { return true }
        return false
    }
}

private struct CashflowStatementConfirmationView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @ObservedObject var controller: CashflowStatementImportController
    let month: Date
    let apply: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var linksToAccount = false
    @State private var accountID = ""

    private var summary: CashflowStatementConfirmationSummary {
        .init(rows: controller.reviewRows)
    }

    private var selectableAccounts: [CashflowSelectableAccount] {
        CashflowStatementAccountSelectionPolicy.options(
            cards: viewModel.state.availableCards,
            newCoreAccounts: viewModel.newCoreAccountsForCashflowPicker(),
            statementCurrencies: Set(controller.reviewRows.filter(\.disposition.isIncluded).map(\.currency))
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section(CashflowStatementReviewLocalization.month) {
                    Label(month.formatted(.dateTime.month(.wide).year()), systemImage: "calendar")
                }
                Section(CashflowStatementReviewLocalization.proposedImport) {
                    LabeledContent(CashflowStatementReviewLocalization.importedCount, value: "\(summary.includedCount)")
                    LabeledContent(CashflowStatementReviewLocalization.excludedCount, value: "\(summary.excludedCount)")
                    if summary.reclassifiedCount > 0 {
                        LabeledContent(CashflowStatementReviewLocalization.reclassifiedCount, value: "\(summary.reclassifiedCount)")
                    }
                    ForEach(summary.totalsByCurrency.keys.sorted(), id: \.self) { currency in
                        LabeledContent(currency, value: summary.totalsByCurrency[currency] ?? 0, format: .currency(code: currency))
                    }
                }
                if let preview = controller.preview {
                    Section(CashflowStatementReviewLocalization.sourceReconciliation) {
                        Label(preview.reconciliation.balanced ? CashflowStatementReviewLocalization.balanced : CashflowStatementReviewLocalization.discrepancy, systemImage: preview.reconciliation.balanced ? "checkmark.seal" : "exclamationmark.triangle")
                        LabeledContent(CashflowStatementReviewLocalization.difference, value: preview.reconciliation.difference)
                    }
                }
                Section(CashflowStatementReviewLocalization.account) {
                    Toggle(CashflowStatementReviewLocalization.linkToAccount, isOn: $linksToAccount)
                    if linksToAccount {
                        if selectableAccounts.isEmpty {
                            Label(CashflowStatementReviewLocalization.noMatchingAccounts, systemImage: "creditcard.trianglebadge.exclamationmark")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker(CashflowStatementReviewLocalization.account, selection: $accountID) {
                                Text(CashflowStatementReviewLocalization.selectAccount).tag("")
                                ForEach(selectableAccounts) { account in
                                    Text("\(account.pickerTitle) · \(account.currency)")
                                        .tag(account.cardID ?? "")
                                }
                            }
                        }
                    }
                    Label(CashflowStatementReviewLocalization.balanceUnchanged, systemImage: "shield.checkered")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button(CashflowStatementReviewLocalization.confirmImportCount(summary.includedCount)) {
                        apply(linksToAccount ? accountID : nil)
                    }
                    .disabled(
                        summary.includedCount == 0
                            || (linksToAccount && !CashflowStatementAccountSelectionPolicy.isValid(accountID, in: selectableAccounts))
                    )
                }
            }
            .navigationTitle(CashflowStatementReviewLocalization.confirmationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(CashflowStatementReviewLocalization.cancel) { dismiss() } }
            }
            .onAppear {
                viewModel.handle(.loadCards)
            }
            .onChange(of: selectableAccounts.map(\.id)) { _, _ in
                if !CashflowStatementAccountSelectionPolicy.isValid(accountID, in: selectableAccounts) {
                    accountID = ""
                }
            }
        }
    }
}
