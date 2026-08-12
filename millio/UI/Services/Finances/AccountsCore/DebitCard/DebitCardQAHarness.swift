#if DEBUG
import SwiftData
import SwiftUI

/// Opt-in simulator harness for the debit render matrix. It is unreachable without an explicit
/// QA environment flag and never removes or rewrites existing simulator data.
struct DebitCardQAHarness: View {
    let modelContext: ModelContext
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var account: Account?

    private var mode: String { ProcessInfo.processInfo.environment["MILLIO_DEBIT_QA_MODE"] ?? "positive" }
    private var dark: Bool { ProcessInfo.processInfo.environment["MILLIO_DEBIT_QA_DARK"] == "1" }

    var body: some View {
        Group {
            if mode == "create" {
                FinanceAddAccountView(
                    viewModel: FinanceViewModel(modelContext: modelContext, skipInitialLoad: true),
                    preselectedAccountType: .card,
                    presentationStyle: .modal
                )
                .environment(appState)
                .environment(router)
            } else if let account, mode == "incomplete" {
                NavigationStack {
                    DebitCardDetailSection(
                        account: account,
                        snapshot: DebitCardSnapshot(
                            accountID: account.id,
                            actualBalance: 0,
                            currency: account.currency,
                            converted: .unavailable,
                            participatesInTotal: account.includeInTotal,
                            lifecycle: .active,
                            incompleteReason: "qa_missing_ledger",
                            canWrite: false
                        )
                    )
                        .padding()
                        .navigationTitle(account.name)
                        .navigationBarTitleDisplayMode(.inline)
                }
            } else if let account {
                NavigationStack {
                    AccountDetailView(account: account, modelContext: modelContext)
                }
                .alert(
                    L("accounts_core.detail.error.title"),
                    isPresented: .constant(mode == "error")
                ) {
                    Button("OK") {}
                } message: {
                    Text(L("accounts_core.detail.error.title"))
                }
            } else {
                ProgressView().task { seed() }
            }
        }
        .preferredColorScheme(dark ? .dark : .light)
    }

    @MainActor private func seed() {
        let value = Account(
            name: "QA Debit \(mode)", kind: .debitCard, productType: .debitCard,
            currency: "RUB", includeInTotal: mode != "excluded"
        )
        value.cardMeta = CardMeta(last4: "4242")
        if mode == "archived" { value.archivedAt = Date() }
        modelContext.insert(value)
        if mode != "empty" && mode != "incomplete" {
            let opening: Decimal = mode == "zero" ? 0 : 125_430
            modelContext.insert(AccountEvent(account: value, date: Date(), type: .openingBalance, amount: opening))
        }
        try? modelContext.save()
        account = value
    }
}
#endif
