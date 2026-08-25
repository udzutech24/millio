import SwiftUI

/// Форма создания «Вклад»/«Накопительный счёт» на новом ядре event-sourcing (Фаза 3).
/// Накопительный счёт — тот же движок B, просто выключатель «без срока» (`hasTerm = false` →
/// `DepositMeta.termEnd == nil`) — НЕ отдельный пресет-экран (план §2.8).
struct InlineDepositCreateForm<GroupSection: View>: View {
    @Binding var name: String
    let onDepositDataChanged: (DepositFormData?) -> Void
    let groupSection: GroupSection

    @State private var amountText: String = ""
    @State private var selectedCurrency: String = SettingsManager.shared.primaryCurrencyCode
    @State private var rateText: String = ""
    @State private var capitalization: AccountDepositCapitalization = .monthly
    @State private var hasTerm: Bool = true
    @State private var termEnd: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var allowsTopUp: Bool = false
    @State private var allowsEarlyClose: Bool = true
    @State private var earlyClosePenaltyPercentText: String = "0"
    @State private var remindEnd: Bool = true
    @State private var autoRollover: Bool = false
    @State private var comment: String = ""
    @FocusState private var inputFocused: Bool

    init(
        name: Binding<String>,
        onDepositDataChanged: @escaping (DepositFormData?) -> Void,
        @ViewBuilder groupSection: () -> GroupSection
    ) {
        self._name = name
        self.onDepositDataChanged = onDepositDataChanged
        self.groupSection = groupSection()
    }

    private var parsedAmount: Double? {
        parseNumber(amountText)
    }

    private var parsedRate: Double? {
        parseNumber(rateText)
    }

    private func parseNumber(_ text: String) -> Double? {
        AmountInputFormatter.parse(text)
    }

    private func currentData() -> DepositFormData? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              creationPreview.isValid,
              let amount = parsedAmount,
              let rate = parsedRate else { return nil }
        return DepositFormData(
            amount: amount,
            currency: selectedCurrency,
            rate: rate,
            capitalization: capitalization,
            termEnd: hasTerm ? termEnd : nil,
            allowsTopUp: allowsTopUp,
            allowsEarlyClose: allowsEarlyClose,
            earlyClosePenaltyPercent: allowsEarlyClose ? (parseNumber(earlyClosePenaltyPercentText) ?? 0) : 0,
            remindEnd: remindEnd && hasTerm,
            autoRollover: autoRollover && hasTerm,
            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            amountSection
            rateSection
            termSection
            optionsSection
            previewSection
            groupSection
            commentSection
        }
        .onChange(of: name) { _, _ in emitChange() }
        .onChange(of: amountText) { _, _ in emitChange() }
        .onChange(of: selectedCurrency) { _, _ in emitChange() }
        .onChange(of: rateText) { _, _ in emitChange() }
        .onChange(of: capitalization) { _, _ in emitChange() }
        .onChange(of: hasTerm) { _, _ in emitChange() }
        .onChange(of: termEnd) { _, _ in emitChange() }
        .onChange(of: allowsTopUp) { _, _ in emitChange() }
        .onChange(of: allowsEarlyClose) { _, _ in emitChange() }
        .onChange(of: earlyClosePenaltyPercentText) { _, _ in emitChange() }
        .onChange(of: remindEnd) { _, _ in emitChange() }
        .onChange(of: autoRollover) { _, _ in emitChange() }
        .onChange(of: comment) { _, _ in emitChange() }
        .onAppear { emitChange() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("common.done")) { inputFocused = false }
            }
        }
    }

    private var creationPreview: DepositCreationPreview {
        DepositCreationPreview.make(
            amount: parsedAmount.map { Decimal($0) },
            rate: parsedRate.map { Decimal($0) },
            openingDate: Date(),
            termEnd: hasTerm ? termEnd : nil,
            hasTerm: hasTerm,
            earlyClosePenaltyPercent: parseNumber(earlyClosePenaltyPercentText).map { Decimal($0) },
            allowsEarlyClose: allowsEarlyClose,
            remindEnd: remindEnd && hasTerm,
            autoRollover: autoRollover && hasTerm
        )
    }

    private func emitChange() {
        onDepositDataChanged(currentData())
    }

    // MARK: - Секции

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            FinancesSectionHeader(title: L("accounts_core.deposit_form.section.amount"))
            FinancesGlassCard(contentPadding: EdgeInsets(top: AppSpacing.s, leading: AppSpacing.m, bottom: AppSpacing.s, trailing: AppSpacing.m)) {
                HStack {
                    AmountTextField(
                        placeholder: L("accounts_core.detail.sheet.amount_placeholder"),
                        value: $amountText
                    )
                    .focused($inputFocused)
                    .font(.millioBody)
                    Picker("", selection: $selectedCurrency) {
                        ForEach(["RUB", "USD", "EUR"], id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var rateSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            FinancesSectionHeader(title: L("accounts_core.deposit_form.section.rate"))
            FinancesGlassCard(contentPadding: EdgeInsets(top: AppSpacing.s, leading: AppSpacing.m, bottom: AppSpacing.s, trailing: AppSpacing.m)) {
                VStack(spacing: AppSpacing.s) {
                    AmountTextField(
                        placeholder: L("accounts_core.deposit_form.rate_placeholder"),
                        value: $rateText
                    )
                    .focused($inputFocused)
                    .font(.millioBody)
                    Picker(L("accounts_core.deposit_form.capitalization_label"), selection: $capitalization) {
                        Text(L("accounts_core.deposit_form.capitalization.none")).tag(AccountDepositCapitalization.none)
                        Text(L("accounts_core.deposit_form.capitalization.monthly")).tag(AccountDepositCapitalization.monthly)
                        Text(L("accounts_core.deposit_form.capitalization.quarterly")).tag(AccountDepositCapitalization.quarterly)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var termSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            FinancesSectionHeader(title: L("accounts_core.deposit_form.section.term"))
            FinancesGlassCard(contentPadding: EdgeInsets(top: AppSpacing.s, leading: AppSpacing.m, bottom: AppSpacing.s, trailing: AppSpacing.m)) {
                VStack(spacing: AppSpacing.s) {
                    Toggle(L("accounts_core.deposit_form.has_term"), isOn: $hasTerm)
                    if hasTerm {
                        DatePicker(L("accounts_core.deposit_form.term_end"), selection: $termEnd, displayedComponents: .date)
                        Toggle(L("accounts_core.deposit_form.remind_end"), isOn: $remindEnd)
                        // Auto-rollover remains a persisted compatibility field, but there is no
                        // background execution engine. Do not present a decorative promise.
                    } else {
                        Text(L("accounts_core.deposit_form.savings_hint"))
                            .font(.millioCaptionRegular)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
        }
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            FinancesSectionHeader(title: L("accounts_core.deposit_form.section.options"))
            FinancesGlassCard(contentPadding: EdgeInsets(top: AppSpacing.s, leading: AppSpacing.m, bottom: AppSpacing.s, trailing: AppSpacing.m)) {
                VStack(spacing: AppSpacing.s) {
                    Toggle(L("accounts_core.deposit_form.allows_top_up"), isOn: $allowsTopUp)
                    Toggle(L("accounts_core.deposit_form.allows_early_close"), isOn: $allowsEarlyClose)
                    if allowsEarlyClose {
                        HStack {
                            Text(L("accounts_core.deposit_form.early_close_penalty"))
                                .font(.millioCalloutRegular)
                                .foregroundStyle(AppColors.textSecondary)
                            Spacer()
                            AmountTextField(
                                placeholder: "%",
                                value: $earlyClosePenaltyPercentText
                            )
                            .focused($inputFocused)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        }
                    }
                }
            }
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            FinancesSectionHeader(title: L("accounts_core.deposit_form.section.comment"))
            FinancesGlassCard(contentPadding: EdgeInsets(top: AppSpacing.s, leading: AppSpacing.m, bottom: AppSpacing.s, trailing: AppSpacing.m)) {
                TextField(L("accounts_core.deposit_form.comment_placeholder"), text: $comment)
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            FinancesSectionHeader(title: L("accounts_core.deposit.creation.preview"))
            FinancesGlassCard(contentPadding: EdgeInsets(top: AppSpacing.m, leading: AppSpacing.m, bottom: AppSpacing.m, trailing: AppSpacing.m)) {
                if !creationPreview.errors.isEmpty {
                    Label(L("accounts_core.deposit.creation.invalid"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.warning)
                } else if let interest = creationPreview.interest, let maturity = creationPreview.maturityAmount {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(String(format: L("accounts_core.deposit.creation.interest_format"), NSDecimalNumber(decimal: interest).stringValue, selectedCurrency))
                        Text(String(format: L("accounts_core.deposit.creation.maturity_format"), NSDecimalNumber(decimal: maturity).stringValue, selectedCurrency))
                            .font(.millioBodySemibold)
                    }
                } else {
                    Text(L("accounts_core.deposit.creation.savings_preview"))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }
}

/// Собранные данные формы «Вклад»/«Накопительный счёт» — сырые проценты (не доли), конвертация
/// в `DepositMeta` (доля 0…1 для `earlyClosePenalty`) — в `AccountsCoreAdditionBridge.depositMeta`.
struct DepositFormData: Equatable {
    let amount: Double
    let currency: String
    let rate: Double
    let capitalization: AccountDepositCapitalization
    let termEnd: Date?
    let allowsTopUp: Bool
    let allowsEarlyClose: Bool
    /// Ввод пользователя В ПРОЦЕНТАХ (0…100) — бридж делит на 100 при сборке `DepositMeta`.
    let earlyClosePenaltyPercent: Double
    let remindEnd: Bool
    let autoRollover: Bool
    let comment: String
}
