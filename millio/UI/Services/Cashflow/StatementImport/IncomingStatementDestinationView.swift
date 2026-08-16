import SwiftData
import SwiftUI

@MainActor
struct IncomingStatementDestinationView: View {
    let item: IncomingStatementInboxItem
    @ObservedObject var financeViewModel: FinanceViewModel
    @ObservedObject var cashflowViewModel: CashflowViewModel
    let statementClient: any CashflowStatementImportClient
    let complete: () -> Void
    let discard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var controller: CashflowStatementImportController
    @State private var destination: Destination?

    private enum Destination: Hashable {
        case createAccount
        case importCashflow
    }

    init(
        item: IncomingStatementInboxItem,
        financeViewModel: FinanceViewModel,
        cashflowViewModel: CashflowViewModel,
        statementClient: any CashflowStatementImportClient,
        complete: @escaping () -> Void,
        discard: @escaping () -> Void
    ) {
        self.item = item
        self.financeViewModel = financeViewModel
        self.cashflowViewModel = cashflowViewModel
        self.statementClient = statementClient
        self.complete = complete
        self.discard = discard
        let income = Set(cashflowViewModel.categoryOptions(for: .income, includeHiddenSystem: true).map(\.rawValue))
        let expense = Set(cashflowViewModel.categoryOptions(for: .expense, includeHiddenSystem: true).map(\.rawValue))
        _controller = StateObject(wrappedValue: CashflowStatementImportController(
            client: statementClient,
            categoryCatalog: .init(income: income, expense: expense)
        ))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    switch controller.state {
                    case .uploading, .processing, .idle, .selectingFile:
                        ProgressView(String(localized: "finances.statement.processing", defaultValue: "Processing statement…"))
                    case .needsReview(let count):
                        Label(
                            String.localizedStringWithFormat(
                                String(localized: "finances.statement.review_count", defaultValue: "Review operations: %lld"),
                                count
                            ),
                            systemImage: "checkmark.seal"
                        )
                    case .backendUnavailable:
                        errorRow(String(localized: "finances.statement.backend_unavailable", defaultValue: "Statement service is unavailable."))
                    case .unsupported:
                        errorRow(String(localized: "finances.statement.unsupported", defaultValue: "This statement format is not supported."))
                    case .reconciliationFailed:
                        errorRow(String(localized: "finances.statement.reconciliation_failed", defaultValue: "Statement totals did not reconcile."))
                    case .monthMismatch:
                        errorRow(String(localized: "finances.statement.multimonth", defaultValue: "Use a statement for one calendar month."))
                    case .failed:
                        errorRow(String(localized: "finances.statement.apply_failed", defaultValue: "Could not import the statement."))
                    case .applying:
                        ProgressView()
                    case .completed:
                        Label(String(localized: "common.done", defaultValue: "Done"), systemImage: "checkmark.circle.fill")
                    }
                }

                if case .needsReview = controller.state {
                    Section(String(localized: "finances.statement.destination", defaultValue: "What do you want to do?")) {
                        Button {
                            destination = .createAccount
                        } label: {
                            Label(String(localized: "finances.statement.destination.create", defaultValue: "Create a new account"), systemImage: "plus.rectangle.on.folder")
                        }
                        Button {
                            annotateOrdinaryImportDuplicates()
                            destination = .importCashflow
                        } label: {
                            Label(String(localized: "finances.statement.destination.import", defaultValue: "Import into Cashflow"), systemImage: "arrow.down.doc")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "finances.statement.incoming", defaultValue: "Incoming statement"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close", defaultValue: "Close")) { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(String(localized: "common.delete", defaultValue: "Discard"), role: .destructive) {
                        discard()
                        dismiss()
                    }
                }
            }
            .navigationDestination(item: $destination) { destination in
                switch destination {
                case .createAccount:
                    FinanceAddAccountView(
                        viewModel: financeViewModel,
                        preselectedAccountType: .card,
                        presentationStyle: .pushed,
                        incomingStatementController: controller
                    )
                case .importCashflow:
                    CashflowStatementReviewView(
                        viewModel: cashflowViewModel,
                        controller: controller,
                        month: controller.selectedMonth
                    )
                }
            }
            .task(id: item.id) {
                guard controller.preview == nil else { return }
                await controller.preview(fileURL: item.fileURL)
                if case .monthMismatch = controller.state,
                   let detected = controller.detectedStatementMonth {
                    controller.selectMonth(detected)
                }
            }
            .onChange(of: controller.state) { _, state in
                if case .completed = state {
                    complete()
                    dismiss()
                }
            }
        }
    }

    private func errorRow(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
    }

    private func annotateOrdinaryImportDuplicates() {
        let transactions = (try? modelContext.fetch(FetchDescriptor<CashflowTransaction>())) ?? []
        let fingerprints = Set(transactions.compactMap { transaction in
            transaction.importSourceRaw == CashflowStatementStagingService.importSource
                ? transaction.importReferenceKey
                : nil
        })
        controller.annotateLocalDuplicates(fingerprints)
    }
}
