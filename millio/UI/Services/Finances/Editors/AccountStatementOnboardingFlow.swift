import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AccountStatementCreateDraft {
    let createTemplate: CreateProductCommand

    func command(openingBalance: Decimal, asOf: Date) -> CreateProductCommand {
        CreateProductCommand(
            accountID: createTemplate.accountID,
            productType: createTemplate.productType,
            name: createTemplate.name,
            currency: createTemplate.currency,
            openingBalance: openingBalance,
            includeInTotal: createTemplate.includeInTotal,
            order: createTemplate.order,
            groupID: createTemplate.groupID,
            metadata: createTemplate.metadata,
            note: createTemplate.note,
            date: asOf,
            initialMarketPurchase: createTemplate.initialMarketPurchase,
            calendar: createTemplate.calendar
        )
    }
}

enum AccountStatementOnboardingPresentationPolicy {
    static func isEligible(option: FinanceAddAccountProductOption, cardType: CardType?) -> Bool {
        option == .account || (option == .card && cardType == .debit)
    }
}

enum AccountStatementBalanceResolverError: Error, Equatable {
    case invalidBankEvidence
    case currencyMismatch
    case manualConfirmationRequired
}

enum AccountStatementBalanceResolver {
    static func resolve(
        preview: CashflowStatementPreviewDTO,
        accountCurrency: String,
        manualAmount: Decimal?,
        manualDate: Date,
        isManualConfirmed: Bool
    ) throws -> AccountStatementBalanceConfirmation {
        if let evidence = preview.balances, let closing = evidence.closing {
            guard evidence.currency.uppercased() == accountCurrency.uppercased() else {
                throw AccountStatementBalanceResolverError.currencyMismatch
            }
            guard let amount = closing.validatedAmount,
                  let date = StatementISODateParser.date(closing.asOf) else {
                throw AccountStatementBalanceResolverError.invalidBankEvidence
            }
            return .bankDeclared(amount: amount, currency: evidence.currency, asOf: date, source: evidence.source)
        }
        guard isManualConfirmed, let manualAmount else {
            throw AccountStatementBalanceResolverError.manualConfirmationRequired
        }
        return .manual(amount: manualAmount, currency: accountCurrency, asOf: manualDate)
    }
}

enum StatementISODateParser {
    static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }
}

@MainActor
struct AccountStatementOnboardingFlow: View {
    let draft: AccountStatementCreateDraft
    let statementClient: any CashflowStatementImportClient
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @StateObject private var cashflowViewModel: CashflowViewModel
    @StateObject private var controller: CashflowStatementImportController
    @State private var showFileImporter = false
    @State private var showReview = false
    @State private var showFinalConfirmation = false
    @State private var manualAmountText: String
    @State private var manualBalanceDate: Date
    @State private var isManualBalanceConfirmed = false
    @State private var applyError: String?
    @State private var attachedIncomingItem: IncomingStatementInboxItem?

    init(
        draft: AccountStatementCreateDraft,
        modelContext: ModelContext,
        statementClient: any CashflowStatementImportClient,
        existingController: CashflowStatementImportController? = nil,
        onComplete: @escaping () -> Void
    ) {
        self.draft = draft
        self.statementClient = statementClient
        self.onComplete = onComplete
        let viewModel = CashflowViewModel(modelContext: modelContext)
        _cashflowViewModel = StateObject(wrappedValue: viewModel)
        let income = Set(viewModel.categoryOptions(for: .income, includeHiddenSystem: true).map(\.rawValue))
        let expense = Set(viewModel.categoryOptions(for: .expense, includeHiddenSystem: true).map(\.rawValue))
        _controller = StateObject(wrappedValue: existingController ?? CashflowStatementImportController(
                client: statementClient,
                selectedMonth: draft.createTemplate.date,
                categoryCatalog: .init(income: income, expense: expense)
            ))
        _manualAmountText = State(initialValue: NSDecimalNumber(decimal: draft.createTemplate.openingBalance).stringValue)
        _manualBalanceDate = State(initialValue: draft.createTemplate.date)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(draft.createTemplate.name, systemImage: "building.columns")
                    LabeledContent(
                        String(localized: "finances.statement.currency", defaultValue: "Currency"),
                        value: draft.createTemplate.currency.uppercased()
                    )
                }

                Section {
                    Button {
                        controller.beginSelection()
                        showFileImporter = true
                    } label: {
                        Label(
                            controller.preview == nil
                                ? String(localized: "finances.statement.upload", defaultValue: "Upload statement")
                                : String(localized: "finances.statement.replace", defaultValue: "Choose another statement"),
                            systemImage: "doc.text.magnifyingglass"
                        )
                    }
                }

                statusSection

                if controller.preview != nil {
                    balanceSection
                }

                if let applyError {
                    Section {
                        Label(applyError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(String(localized: "finances.statement.title", defaultValue: "Create from statement"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel")) { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .pdf, UTType(filenameExtension: "xlsx") ?? .spreadsheet],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task { await loadPreview(url) }
            }
            .navigationDestination(isPresented: $showReview) {
                CashflowStatementReviewView(
                    viewModel: cashflowViewModel,
                    controller: controller,
                    month: controller.selectedMonth,
                    context: .accountOnboarding {
                        showFinalConfirmation = true
                    }
                )
            }
            .sheet(isPresented: $showFinalConfirmation) {
                finalConfirmation
            }
            .onAppear {
                appState.isStatementOnboardingActive = true
                attachPendingIncomingStatementIfNeeded()
                if case .needsReview = controller.state, controller.preview != nil {
                    showReview = true
                }
            }
            .onDisappear { appState.isStatementOnboardingActive = false }
            .onChange(of: appState.pendingIncomingStatementItem) { _, _ in
                attachPendingIncomingStatementIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch controller.state {
        case .idle, .selectingFile:
            EmptyView()
        case .uploading, .processing:
            Section { ProgressView(String(localized: "finances.statement.processing", defaultValue: "Processing statement…")) }
        case .needsReview(let count):
            Section {
                Button {
                    showReview = true
                } label: {
                    Label(
                        String.localizedStringWithFormat(
                            String(localized: "finances.statement.review_count", defaultValue: "Review operations: %lld"),
                            count
                        ),
                        systemImage: "checklist"
                    )
                }
            }
        case .backendUnavailable:
            failureLabel(String(localized: "finances.statement.backend_unavailable", defaultValue: "Statement service is unavailable. Your account draft is preserved."))
        case .unsupported:
            failureLabel(String(localized: "finances.statement.unsupported", defaultValue: "This statement format is not supported."))
        case .reconciliationFailed:
            failureLabel(String(localized: "finances.statement.reconciliation_failed", defaultValue: "Statement totals did not reconcile. Nothing was saved."))
        case .monthMismatch:
            failureLabel(String(localized: "finances.statement.multimonth", defaultValue: "Use a statement for one calendar month."))
        case .failed:
            failureLabel(String(localized: "finances.statement.apply_failed", defaultValue: "Could not create the account. Nothing was saved."))
        case .applying:
            Section { ProgressView(String(localized: "finances.statement.creating", defaultValue: "Creating account…")) }
        case .completed(let count):
            Section { Label("\(count)", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
        }
    }

    private func failureLabel(_ text: String) -> some View {
        Section { Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
    }

    @ViewBuilder
    private var balanceSection: some View {
        if let evidence = controller.preview?.balances, let closing = evidence.closing {
            Section(String(localized: "finances.statement.balance", defaultValue: "Balance")) {
                LabeledContent(
                    String(localized: "finances.statement.bank_declared", defaultValue: "Declared by bank"),
                    value: "\(closing.amount) \(evidence.currency.uppercased())"
                )
                LabeledContent(String(localized: "finances.statement.as_of", defaultValue: "As of"), value: closing.asOf)
            }
        } else {
            Section(String(localized: "finances.statement.manual_balance", defaultValue: "Confirm balance manually")) {
                TextField(String(localized: "finances.statement.balance", defaultValue: "Balance"), text: $manualAmountText)
                    .keyboardType(.decimalPad)
                DatePicker(
                    String(localized: "finances.statement.as_of", defaultValue: "As of"),
                    selection: $manualBalanceDate,
                    displayedComponents: .date
                )
                Toggle(
                    String(localized: "finances.statement.manual_confirm", defaultValue: "I confirm this balance and date"),
                    isOn: $isManualBalanceConfirmed
                )
                Text(String(localized: "finances.statement.manual_not_derived", defaultValue: "The balance is not calculated from statement turnover."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var finalConfirmation: some View {
        NavigationStack {
            List {
                Section(String(localized: "finances.statement.account", defaultValue: "Account")) {
                    LabeledContent(String(localized: "finances.statement.name", defaultValue: "Name"), value: draft.createTemplate.name)
                    LabeledContent(String(localized: "finances.statement.type", defaultValue: "Type"), value: draft.createTemplate.productType.rawValue)
                }
                if let confirmation = try? balanceConfirmation {
                    Section(String(localized: "finances.statement.balance", defaultValue: "Balance")) {
                        LabeledContent(
                            confirmation.currency.uppercased(),
                            value: NSDecimalNumber(decimal: confirmation.amount).stringValue
                        )
                        LabeledContent(
                            String(localized: "finances.statement.as_of", defaultValue: "As of"),
                            value: confirmation.asOf.formatted(date: .abbreviated, time: .omitted)
                        )
                    }
                }
                let summary = CashflowStatementConfirmationSummary(rows: controller.reviewRows)
                Section(String(localized: "finances.statement.operations", defaultValue: "Operations")) {
                    LabeledContent(CashflowStatementReviewLocalization.importedCount, value: "\(summary.includedCount)")
                    LabeledContent(CashflowStatementReviewLocalization.excludedCount, value: "\(summary.excludedCount)")
                    if summary.reclassifiedCount > 0 {
                        LabeledContent(CashflowStatementReviewLocalization.reclassifiedCount, value: "\(summary.reclassifiedCount)")
                    }
                    ForEach(summary.totalsByCurrency.keys.sorted(), id: \.self) { currency in
                        LabeledContent(currency, value: summary.totalsByCurrency[currency] ?? 0, format: .currency(code: currency))
                    }
                    Label(CashflowStatementReviewLocalization.balanceUnchanged, systemImage: "shield.checkered")
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button(String(localized: "finances.statement.create", defaultValue: "Create account and import")) {
                        apply()
                    }
                    .disabled((try? balanceConfirmation) == nil || controller.state == .applying)
                }
            }
            .navigationTitle(String(localized: "finances.statement.confirmation", defaultValue: "Final confirmation"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel", defaultValue: "Cancel")) { showFinalConfirmation = false }
                }
            }
        }
    }

    private var manualAmount: Decimal? {
        Decimal(string: manualAmountText.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
    }

    private var balanceConfirmation: AccountStatementBalanceConfirmation {
        get throws {
            guard let preview = controller.preview else {
                throw AccountStatementBalanceResolverError.invalidBankEvidence
            }
            return try AccountStatementBalanceResolver.resolve(
                preview: preview,
                accountCurrency: draft.createTemplate.currency,
                manualAmount: manualAmount,
                manualDate: manualBalanceDate,
                isManualConfirmed: isManualBalanceConfirmed
            )
        }
    }

    private func loadPreview(_ url: URL) async {
        applyError = nil
        await controller.preview(fileURL: url)
        if case .monthMismatch = controller.state,
           let detectedMonth = controller.detectedStatementMonth {
            controller.selectMonth(detectedMonth)
        }
        guard case .needsReview = controller.state, let preview = controller.preview else { return }
        let includedRows = preview.operations.filter { controller.includedFingerprints.contains($0.fingerprint) }
        let currencies = Set(includedRows.map { $0.currency.uppercased() })
        let targetCurrency = draft.createTemplate.currency.uppercased()
        if !currencies.isSubset(of: [targetCurrency])
            || preview.balances.map({ $0.currency.uppercased() != targetCurrency }) == true {
            applyError = String(localized: "finances.statement.currency_mismatch", defaultValue: "The account, balance and all imported operations must use one currency.")
            controller.markApplyFailure()
            return
        }
        let requested = controller.includedFingerprints
        let existing = (try? modelContext.fetch(FetchDescriptor<CashflowTransaction>())) ?? []
        if existing.contains(where: {
            $0.importSourceRaw == CashflowStatementStagingService.importSource
                && $0.importReferenceKey.map(requested.contains) == true
        }) {
            applyError = String(localized: "finances.statement.duplicate_conflict", defaultValue: "Some statement operations were imported earlier. Resolve that import before creating this account.")
            controller.markApplyFailure()
            return
        }
        showReview = true
    }

    private func attachPendingIncomingStatementIfNeeded() {
        guard attachedIncomingItem == nil,
              let item = appState.pendingIncomingStatementItem else { return }
        attachedIncomingItem = item
        appState.pendingIncomingStatementItem = nil
        Task { await loadPreview(item.fileURL) }
    }

    private func completeAttachedIncomingStatement() {
        guard let item = attachedIncomingItem else { return }
        try? IncomingStatementCoordinator.appGroup().complete(item)
        attachedIncomingItem = nil
    }

    private func apply() {
        guard let preview = controller.preview,
              let from = StatementISODateParser.date(preview.statement.period.from),
              let to = StatementISODateParser.date(preview.statement.period.to) else {
            controller.markApplyFailure()
            return
        }
        do {
            let confirmation = try balanceConfirmation
            let command = draft.command(openingBalance: confirmation.amount, asOf: confirmation.asOf)
            let operations = try CashflowApprovedStatementOperationBuilder.build(
                preview: preview,
                controller: controller,
                accountID: command.accountID.uuidString
            )
            controller.markApplying()
            let result = try AccountStatementOnboardingCoordinator(modelContext: modelContext).apply(.init(
                create: command,
                operations: operations,
                balanceConfirmation: confirmation,
                statementPeriodFrom: from,
                statementPeriodTo: to,
                onboardingID: command.accountID.uuidString
            ))
            controller.markCompleted(result: .init(
                insertedFingerprints: result.insertedFingerprints,
                skippedFingerprints: result.skippedFingerprints
            ))
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            EventBus.shared.publish(FinanceEvent.transactionsUpdated)
            completeAttachedIncomingStatement()
            showFinalConfirmation = false
            onComplete()
        } catch {
            applyError = String(localized: "finances.statement.apply_failed", defaultValue: "Could not create the account. Nothing was saved.")
            controller.markApplyFailure()
            showFinalConfirmation = false
        }
    }
}
