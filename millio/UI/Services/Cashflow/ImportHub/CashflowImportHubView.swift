import SwiftUI
import UniformTypeIdentifiers
import SwiftData

struct CashflowImportHubView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showManualBulk = false
    @State private var showFileImporter = false
    @State private var showFinalImportConfirmation = false
    @State private var selectedAccountID = ""
    @State private var linksOperationsToAccount = true
    @State private var showStatementReview = false
    @State private var showMonthPicker = false
    @State private var selectedMonth: Date
    @StateObject private var statementController: CashflowStatementImportController

    init(
        viewModel: CashflowViewModel,
        month: Date,
        statementClient: any CashflowStatementImportClient = UnavailableCashflowStatementImportClient()
    ) {
        self.viewModel = viewModel
        let canonicalMonth = CashflowMonthSelectionPolicy.canonicalMonth(month)
        _selectedMonth = State(initialValue: canonicalMonth)
        let income = Set(viewModel.categoryOptions(for: .income, includeHiddenSystem: true).map(\.rawValue))
        let expense = Set(viewModel.categoryOptions(for: .expense, includeHiddenSystem: true).map(\.rawValue))
        _statementController = StateObject(wrappedValue: CashflowStatementImportController(
            client: statementClient,
            selectedMonth: canonicalMonth,
            categoryCatalog: .init(income: income, expense: expense)
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                Section(CashflowMonthWorkspaceLocalization.importMonth) {
                    Button { showMonthPicker = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar")
                            Text(monthTitle(selectedMonth))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Text(CashflowMonthWorkspaceLocalization.importMonthHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showManualBulk = true
                    } label: {
                        Label(CashflowMonthWorkspaceLocalization.manualBulk, systemImage: "square.and.pencil")
                    }
                    .accessibilityHint(CashflowMonthWorkspaceLocalization.manualBulk)

                    Button {
                        statementController.beginSelection()
                        showFileImporter = true
                    } label: {
                        Label(CashflowMonthWorkspaceLocalization.statement, systemImage: "doc.text.magnifyingglass")
                    }
                    .accessibilityHint(CashflowMonthWorkspaceLocalization.statement)
                }

                statementStatusSection

                Section {
                    Text(CashflowMonthWorkspaceLocalization.privacy)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(CashflowMonthWorkspaceLocalization.importData)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(String(localized: "common.close", defaultValue: "Close"))
                }
            }
            .sheet(isPresented: $showManualBulk) {
                CashflowBulkExpenseImportSheet(viewModel: viewModel, month: selectedMonth, onComplete: {
                    showManualBulk = false
                    dismiss()
                })
            }
            .sheet(isPresented: $showMonthPicker) {
                CashflowMonthPickerSheet(selection: $selectedMonth)
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: statementContentTypes,
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task {
                    await statementController.preview(fileURL: url)
                    statementController.annotateLocalDuplicates(existingStatementFingerprints())
                    if case .needsReview = statementController.state { showStatementReview = true }
                }
            }
            .confirmationDialog(
                CashflowMonthWorkspaceLocalization.confirmImport,
                isPresented: $showFinalImportConfirmation,
                titleVisibility: .visible
            ) {
                Button(CashflowMonthWorkspaceLocalization.applySelected) {
                    guard let preview = statementController.preview else { return }
                    applyReviewed(preview)
                }
                Button(CashflowMonthWorkspaceLocalization.cancel, role: .cancel) {}
            } message: {
                Text(CashflowMonthWorkspaceLocalization.confirmImportMessage)
            }
            .navigationDestination(isPresented: $showStatementReview) {
                CashflowStatementReviewView(
                    viewModel: viewModel,
                    controller: statementController,
                    month: selectedMonth
                )
            }
            .onChange(of: selectedMonth) { _, month in
                statementController.selectMonth(month)
            }
        }
    }

    @ViewBuilder
    private var statementStatusSection: some View {
        switch statementController.state {
        case .idle, .selectingFile:
            EmptyView()
        case .uploading, .processing:
            Section { ProgressView(CashflowMonthWorkspaceLocalization.statement) }
        case .backendUnavailable:
            Section { Label(CashflowMonthWorkspaceLocalization.unavailable, systemImage: "wifi.exclamationmark") }
        case .unsupported:
            Section { Label(CashflowMonthWorkspaceLocalization.unsupported, systemImage: "doc.badge.ellipsis") }
        case .reconciliationFailed:
            Section { Label(CashflowMonthWorkspaceLocalization.reconciliationFailed, systemImage: "exclamationmark.triangle") }
        case .monthMismatch:
            Section {
                Label(CashflowMonthWorkspaceLocalization.monthMismatch, systemImage: "calendar.badge.exclamationmark")
                if let detectedMonth = statementController.detectedStatementMonth {
                    Button(CashflowMonthWorkspaceLocalization.switchToMonth(monthTitle(detectedMonth))) {
                        selectedMonth = detectedMonth
                    }
                }
                Button(CashflowMonthWorkspaceLocalization.chooseAnotherMonth) {
                    showMonthPicker = true
                }
            }
        case .needsReview:
            Section {
                NavigationLink("Открыть проверку выписки") {
                    CashflowStatementReviewView(viewModel: viewModel, controller: statementController, month: selectedMonth)
                }
            }
        case .applying:
            Section { ProgressView(CashflowMonthWorkspaceLocalization.applying) }
        case .completed(let count):
            Section { Label("\(CashflowMonthWorkspaceLocalization.importData): \(count)", systemImage: "checkmark.circle") }
        case .failed(let retryable):
            Section { Label(retryable ? CashflowMonthWorkspaceLocalization.retryFailure : CashflowMonthWorkspaceLocalization.applyFailure, systemImage: "xmark.octagon") }
        }
    }

    @ViewBuilder
    private var statementReviewSection: some View {
        if let preview = statementController.preview {
            let summary = CashflowStatementReviewSummary(
                preview: preview,
                includedFingerprints: statementController.includedFingerprints
            )
            Section(CashflowMonthWorkspaceLocalization.account) {
                Toggle(CashflowMonthWorkspaceLocalization.linkToAccount, isOn: $linksOperationsToAccount)
                if linksOperationsToAccount {
                    Picker(CashflowMonthWorkspaceLocalization.account, selection: $selectedAccountID) {
                        Text(CashflowMonthWorkspaceLocalization.selectAccount).tag("")
                        ForEach(viewModel.state.availableCards, id: \.cardUniqueID) { card in
                            Text(card.name).tag(card.cardUniqueID)
                        }
                    }
                }
                Label(CashflowMonthWorkspaceLocalization.accountBalanceUnchanged, systemImage: "shield.checkered")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section(CashflowMonthWorkspaceLocalization.summary) {
                LabeledContent(CashflowMonthWorkspaceLocalization.totalRows, value: "\(summary.total)")
                LabeledContent(CashflowMonthWorkspaceLocalization.includedRows, value: "\(summary.included)")
                LabeledContent(CashflowMonthWorkspaceLocalization.excludedRows, value: "\(summary.excluded)")
                if summary.duplicates > 0 {
                    LabeledContent(CashflowMonthWorkspaceLocalization.duplicates, value: "\(summary.duplicates)")
                }
                if summary.transfers > 0 {
                    LabeledContent(CashflowMonthWorkspaceLocalization.transfers, value: "\(summary.transfers)")
                }
            }
            Section(CashflowMonthWorkspaceLocalization.reconciliation) {
                Label(
                    CashflowMonthWorkspaceLocalization.reconciliationSuccess,
                    systemImage: "checkmark.seal.fill"
                )
                .foregroundStyle(.green)
                LabeledContent(
                    CashflowMonthWorkspaceLocalization.difference,
                    value: "\(preview.reconciliation.difference) \(preview.operations.first?.currency ?? "")"
                )
            }
            Section(CashflowMonthWorkspaceLocalization.categoryBreakdown) {
                ForEach(categoryBreakdown(for: preview)) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .frame(width: 24)
                            .foregroundStyle(item.amount >= 0 ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(CashflowMonthWorkspaceLocalization.transactionCount(item.transactionCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.amount, format: .currency(code: item.currency))
                            .fontWeight(.semibold)
                            .foregroundStyle(item.amount >= 0 ? .green : .primary)
                    }
                }
            }
            Section(CashflowMonthWorkspaceLocalization.review) {
                ForEach(preview.operations) { operation in
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { statementController.includedFingerprints.contains(operation.fingerprint) },
                            set: { included in
                                if included { statementController.includedFingerprints.insert(operation.fingerprint) }
                                else { statementController.includedFingerprints.remove(operation.fingerprint) }
                            }
                        )) {
                            Text(operation.description)
                            Text("\(operation.amount) \(operation.currency)").font(.caption).foregroundStyle(.secondary)
                        }
                        .disabled(!statementController.canInclude(operation))
                        if statementController.isLocalDuplicate(operation) {
                            Label(CashflowMonthWorkspaceLocalization.duplicates, systemImage: "doc.on.doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let reason = CashflowStatementExclusionReason.resolve(operation) {
                            Label(reason.title, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Picker(
                                CashflowMonthWorkspaceLocalization.category,
                                selection: Binding(
                                    get: { statementController.categoryByFingerprint[operation.fingerprint] ?? "other" },
                                    set: { statementController.setCategory($0, for: operation) }
                                )
                            ) {
                                ForEach(categoryOptions(for: operation), id: \.rawValue) { option in
                                    Label(option.displayName, systemImage: option.icon).tag(option.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .disabled(!statementController.includedFingerprints.contains(operation.fingerprint))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Button(CashflowMonthWorkspaceLocalization.applySelected) {
                    showFinalImportConfirmation = true
                }
                    .disabled((linksOperationsToAccount && selectedAccountID.isEmpty) || statementController.includedFingerprints.isEmpty)
            }
        }
    }

    private func categoryOptions(for operation: CashflowStatementPreviewDTO.Operation) -> [CashflowCategoryOption] {
        viewModel.categoryOptions(for: (operation.validatedAmount ?? 0) > 0 ? .income : .expense)
    }

    private func categoryBreakdown(for preview: CashflowStatementPreviewDTO) -> [CashflowStatementCategoryBreakdownItem] {
        let options = viewModel.categoryOptions(for: .expense) + viewModel.categoryOptions(for: .income)
        return CashflowStatementCategoryBreakdown.make(
            preview: preview,
            includedFingerprints: statementController.includedFingerprints,
            categoryByFingerprint: statementController.categoryByFingerprint,
            categoryOptionsByRawValue: Dictionary(options.map { ($0.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
        )
    }

    private var statementContentTypes: [UTType] {
        [.commaSeparatedText, .pdf, UTType(filenameExtension: "xlsx") ?? .spreadsheet]
    }

    private func applyReviewed(_ preview: CashflowStatementPreviewDTO) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        let operations = preview.operations.compactMap { operation -> CashflowApprovedStatementOperation? in
            guard statementController.includedFingerprints.contains(operation.fingerprint),
                  statementController.canInclude(operation),
                  let date = formatter.date(from: operation.operationDate),
                  let amount = operation.validatedAmount else { return nil }
            let type: CashflowTransactionType = amount > 0 ? .income : .expense
            return .init(
                fingerprint: operation.fingerprint,
                date: date,
                amount: amount,
                currency: operation.currency,
                type: type,
                categoryRaw: statementController.categoryByFingerprint[operation.fingerprint] ?? "other",
                accountID: linksOperationsToAccount ? selectedAccountID : nil,
                note: operation.description
            )
        }
        guard operations.count == statementController.includedFingerprints.count else {
            statementController.markApplyFailure()
            return
        }
        statementController.markApplying()
        do {
            let result = try CashflowStatementApplyService(modelContext: modelContext).apply(operations)
            statementController.markCompleted(result: result)
            viewModel.handle(.loadTransactions)
        } catch {
            statementController.markApplyFailure()
        }
    }

    private func existingStatementFingerprints() -> Set<String> {
        let transactions = (try? modelContext.fetch(FetchDescriptor<CashflowTransaction>())) ?? []
        return Set(transactions.compactMap { transaction in
            transaction.importSourceRaw == CashflowStatementApplyService.importSource
                ? transaction.importReferenceKey
                : nil
        })
    }

    private func monthTitle(_ month: Date) -> String {
        month.formatted(.dateTime.month(.wide).year().locale(AppLocalization.currentAppLocale))
    }
}
