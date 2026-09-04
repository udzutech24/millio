import SwiftUI
import SwiftData

/// Экран «Условия кредита» — оболочка `LoanTermsFormCard` для правки уже существующего счёта.
///
/// Режим определяется наличием договора, а не типом экрана: пока `LoanContract` не заведён,
/// сумма и ставка редактируемые. Иначе счёт, созданный старой формой (она никогда не собирала
/// ставку — `AccountsCoreAdditionBridge.loanMeta` пишет `rate: 0`), навсегда остался бы без ставки.
struct LoanTermsEditSheet: View {
    let account: Account
    let modelContext: ModelContext
    let contract: LoanContract?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: LoanTermsDraft
    @State private var errorMessage: String?

    init(
        account: Account,
        modelContext: ModelContext,
        contract: LoanContract?,
        onSaved: @escaping () -> Void
    ) {
        self.account = account
        self.modelContext = modelContext
        self.contract = contract
        self.onSaved = onSaved
        // Сид — только через резолвер (спека Р5): договор, иначе легаси-мета. Ни того, ни другого —
        // пустой черновик с первым платежом через месяц, как у типового графика.
        if let terms = LoanTermsResolver.terms(for: account, contract: contract) {
            _draft = State(initialValue: LoanTermsDraft(terms: terms))
        } else {
            let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
            _draft = State(initialValue: LoanTermsDraft(firstPaymentDate: nextMonth))
        }
    }

    private var mode: LoanTermsFormCard.Mode { contract == nil ? .create : .edit }

    var body: some View {
        NavigationStack {
            ScrollView {
                LoanTermsFormCard(
                    mode: mode,
                    currencyCode: account.currency,
                    draft: $draft
                )
                .padding(AppSpacing.l)
            }
            .navigationTitle(L("accounts_core.loan_form.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("accounts_core.detail.sheet.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done"), action: save)
                        .font(.millioCalloutSemibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.m)
                        .padding(.vertical, AppSpacing.xs)
                        .background(Capsule().fill(draft.terms == nil ? AppColors.textTertiary : AppColors.brandPrimary))
                        .disabled(draft.terms == nil)
                }
            }
            .alert(
                L("accounts_core.detail.error.title"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard let terms = draft.terms else { return }
        do {
            // `upsert` трогает только условия: `paymentsMade`, `paidInterestTotal` и страховка —
            // факт погашения, а не условие договора, и правкой условий не сбрасываются.
            try LoanContractStore(context: modelContext).upsert(accountID: account.id) { contract in
                contract.principal = terms.principal
                contract.annualRatePercent = terms.annualRatePercent
                contract.termPeriods = terms.termPeriods
                contract.firstPaymentDate = terms.firstPaymentDate
                contract.scheduleType = terms.scheduleType
                contract.frequency = terms.frequency
                contract.paymentOverride = terms.paymentOverride
            }
            try modelContext.save()
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
