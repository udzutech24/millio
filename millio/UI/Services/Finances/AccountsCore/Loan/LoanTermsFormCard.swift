import SwiftUI

/// Форма «Условия кредита» (макет, ЭКРАН 2) — один компонент и для создания, и для правки.
///
/// Все условия, включая сумму и ставку, редактируемые в обоих случаях. Read-only сумма и ставка
/// из макета не пережили реальные данные: у счетов, приехавших из старого мира, ставка нулевая, а
/// сумма может быть мусорной, и чинить их было бы нечем (баг владельца 2026-09-04).
///
/// Собран из существующих примитивов тёмного языка (`AccountDetailsBoxCard`,
/// `AccountDetailsFieldRow`, `AccountDetailsToggleRow`, `AccountFieldPickerSheet`,
/// `AccountSelectionChip`) — своих строк формы не заводит.
struct LoanTermsFormCard: View {
    let currencyCode: String
    @Binding var draft: LoanTermsDraft
    /// Сноска под суммой кредита: показывается, когда правка суммы уже НЕ двигает остаток долга
    /// (по договору были платежи). `nil` — сноски нет.
    var principalFootnote: String? = nil

    private enum ActiveFieldSheet: Identifiable {
        case principal, rate, term, firstPaymentDate, payment
        var id: Int { hashValue }
    }

    @State private var activeFieldSheet: ActiveFieldSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            amountAndRateSection
            termSection
            scheduleTypeSection
            paymentSection
        }
        .sheet(item: $activeFieldSheet) { field in
            fieldSheetContent(for: field)
        }
    }

    // MARK: - Сумма и ставка

    private var amountAndRateSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            accountDetailsSectionCaption(L("accounts_core.loan_form.section.amount_rate"))
            AccountDetailsBoxCard {
                AccountDetailsFieldRow(
                    title: L("accounts_core.loan_form.principal"),
                    value: principalValueText
                ) { activeFieldSheet = .principal }
                AccountDetailsDivider()
                AccountDetailsFieldRow(
                    title: L("accounts_core.loan_form.rate"),
                    value: rateValueText
                ) { activeFieldSheet = .rate }
            }
            if let principalFootnote {
                Text(principalFootnote)
                    .font(.millioCaption2Regular)
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.s)
            }
        }
    }

    // MARK: - Срок

    private var termSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            accountDetailsSectionCaption(L("accounts_core.loan_form.section.term"))
            AccountDetailsBoxCard {
                AccountDetailsFieldRow(
                    title: L("accounts_core.loan_form.term"),
                    value: termValueText
                ) { activeFieldSheet = .term }
                AccountDetailsDivider()
                AccountDetailsFieldRow(
                    title: L("accounts_core.loan_form.first_payment_date"),
                    value: draft.firstPaymentDate.formatted(date: .long, time: .omitted)
                ) { activeFieldSheet = .firstPaymentDate }
            }
        }
    }

    // MARK: - Тип платежа

    private var scheduleTypeSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            accountDetailsSectionCaption(L("accounts_core.loan_form.section.schedule_type"))
            Picker("", selection: $draft.scheduleType) {
                Text(L("accounts_core.loan_form.schedule_type.annuity")).tag(LoanScheduleType.annuity)
                Text(L("accounts_core.loan_form.schedule_type.differentiated")).tag(LoanScheduleType.differentiated)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(L("accounts_core.loan_form.schedule_type.hint"))
                .font(.millioCaption2Regular)
                .foregroundStyle(AppColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppSpacing.s)
        }
    }

    // MARK: - Платёж

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            accountDetailsSectionCaption(L("accounts_core.loan_form.section.payment"))
            Text(L("accounts_core.loan_form.frequency_label"))
                .font(.millioCallout)
                .foregroundStyle(AppColors.textSecondary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.s), count: 2),
                spacing: AppSpacing.s
            ) {
                ForEach(LoanPaymentFrequency.allCases, id: \.rawValue) { option in
                    AccountSelectionChip(
                        title: frequencyTitle(option),
                        isSelected: draft.frequency == option
                    ) {
                        draft.frequency = option
                        // Срок хранится в месяцах: при смене шага он обязан остаться кратным,
                        // иначе `termPeriods` округлится вниз и график молча укоротится.
                        draft.alignTermToFrequency()
                    }
                }
            }
            AccountDetailsBoxCard {
                AccountDetailsToggleRow(
                    title: L("accounts_core.loan_form.manual_payment"),
                    isOn: manualPaymentBinding
                )
                if draft.isManualPayment {
                    AccountDetailsDivider()
                    AccountDetailsFieldRow(
                        title: L("accounts_core.loan_form.payment_amount"),
                        value: paymentValueText
                    ) { activeFieldSheet = .payment }
                }
            }
            if let hint = manualPaymentHint {
                Text(hint)
                    .font(.millioCaption2Regular)
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.s)
            }
        }
        .animation(AppAnimation.fast, value: draft.isManualPayment)
    }

    /// Включение тумблера подставляет расчётный платёж — иначе человек видит пустое поле и
    /// вынужден переписывать ту же сумму, которую форма только что показала в подсказке.
    private var manualPaymentBinding: Binding<Bool> {
        Binding(
            get: { draft.isManualPayment },
            set: { isOn in
                if isOn, draft.paymentText.isEmpty, let calculated = draft.calculatedPayment {
                    draft.paymentText = AmountTextField.canonical(
                        from: NSDecimalNumber(decimal: calculated).stringValue
                    )
                }
                draft.isManualPayment = isOn
            }
        )
    }

    // MARK: - Значения строк

    private var currencySymbol: String {
        MonetaCurrency(rawValue: currencyCode)?.symbol ?? currencyCode
    }

    private var principalValueText: String {
        moneyText(from: draft.principalText)
    }

    private var rateValueText: String {
        let display = AmountTextField.formatted(from: draft.ratePercentText)
        return display.isEmpty ? placeholderDash : display
    }

    private var paymentValueText: String {
        moneyText(from: draft.paymentText)
    }

    private var termValueText: String {
        draft.termMonths > 0
            ? L("accounts_core.loan_form.term_months \(draft.termMonths)")
            : placeholderDash
    }

    private var manualPaymentHint: String? {
        guard draft.isManualPayment, let calculated = draft.calculatedPayment else { return nil }
        let amount = AmountTextField.formatted(from: NSDecimalNumber(decimal: calculated).stringValue)
        return String(
            format: L("accounts_core.loan_form.manual_payment_hint_format"),
            "\(amount) \(currencySymbol)"
        )
    }

    private var placeholderDash: String { L("accounts_core.loan_form.value_empty") }

    private func moneyText(from raw: String) -> String {
        let display = AmountTextField.formatted(from: raw)
        return display.isEmpty ? placeholderDash : "\(display) \(currencySymbol)"
    }

    private func frequencyTitle(_ frequency: LoanPaymentFrequency) -> String {
        switch frequency {
        case .monthly: L("accounts_core.loan_form.frequency.monthly")
        case .every2Months: L("accounts_core.loan_form.frequency.every_2_months")
        case .quarterly: L("accounts_core.loan_form.frequency.quarterly")
        case .semiannual: L("accounts_core.loan_form.frequency.semiannual")
        case .annual: L("accounts_core.loan_form.frequency.annual")
        }
    }

    // MARK: - Пикеры листом снизу

    @ViewBuilder
    private func fieldSheetContent(for field: ActiveFieldSheet) -> some View {
        switch field {
        case .principal:
            AccountFieldAmountSheet(
                title: L("accounts_core.loan_form.principal"),
                value: $draft.principalText,
                suffix: currencySymbol
            ) {
                activeFieldSheet = nil
            }
        case .rate:
            AccountFieldAmountSheet(
                title: L("accounts_core.loan_form.rate"),
                value: $draft.ratePercentText,
                suffix: "%"
            ) {
                activeFieldSheet = nil
            }
        case .payment:
            AccountFieldAmountSheet(
                title: L("accounts_core.loan_form.payment_amount"),
                value: $draft.paymentText,
                suffix: currencySymbol
            ) {
                activeFieldSheet = nil
            }
        case .term:
            AccountFieldPickerSheet(title: L("accounts_core.loan_form.term")) {
                activeFieldSheet = nil
            } content: {
                Picker("", selection: $draft.termMonths) {
                    ForEach(draft.termMonthOptions, id: \.self) { months in
                        Text(L("accounts_core.loan_form.term_months \(months)")).tag(months)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            }
        case .firstPaymentDate:
            AccountFieldPickerSheet(title: L("accounts_core.loan_form.first_payment_date")) {
                activeFieldSheet = nil
            } content: {
                DatePicker("", selection: $draft.firstPaymentDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal, AppSpacing.l)
            }
        }
    }
}
