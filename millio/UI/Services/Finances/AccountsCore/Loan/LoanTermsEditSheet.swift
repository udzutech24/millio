import SwiftUI
import SwiftData

/// Экран «Условия кредита» — оболочка `LoanTermsFormCard` для правки уже существующего счёта.
///
/// Редактируются все условия, включая сумму и ставку: счёт, приехавший из старого мира, иначе
/// навсегда остался бы с нулевой ставкой и суммой, которую нечем исправить.
struct LoanTermsEditSheet: View {
    let account: Account
    let modelContext: ModelContext
    let contract: LoanContract?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: LoanTermsDraft
    @State private var errorMessage: String?
    /// Сумма, с которой экран открылся. Нужна, чтобы отличить правку суммы от правки любого
    /// другого условия: остаток догоняем только когда человек тронул именно эту строку.
    private let seededPrincipal: Decimal?

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
            seededPrincipal = terms.principal
        } else {
            let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
            _draft = State(initialValue: LoanTermsDraft(firstPaymentDate: nextMonth))
            seededPrincipal = nil
        }
    }

    /// Платежей по договору ещё не было → сумма кредита и есть остаток долга, и правка суммы
    /// имеет право догнать ленту (см. `save()`). Были → остаток за лентой, форма его не трогает.
    private var paymentsMade: Int { contract?.paymentsMade ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                LoanTermsFormCard(
                    currencyCode: account.currency,
                    draft: $draft,
                    principalFootnote: paymentsMade > 0
                        ? L("accounts_core.loan_form.principal_ledger_note")
                        : nil
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

    /// Человек тронул именно сумму. Без этой проверки правка одной только ставки переписывала бы
    /// остаток долга суммой договора — на легаси-счёте это молча стёрло бы уже погашенную часть.
    private var principalChanged: Bool { draft.principal != seededPrincipal }

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

            // Порядок как в `LoanPaymentRecorder`: договор правится ДО события, и `recordEvent`
            // (единственная точка записи) сохраняет всё разом — второго save-барьера нет.
            let correction = principalChanged
                ? try LoanPrincipalCorrection(modelContext: modelContext).alignOutstanding(
                    account: account,
                    to: terms.principal,
                    paymentsMade: paymentsMade
                )
                : nil
            if correction == nil { try modelContext.save() }

            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
