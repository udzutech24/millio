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
    @State private var earlyClosePenaltyPercentText: String = "100"
    @State private var remindEnd: Bool = true
    @State private var autoRollover: Bool = false
    @State private var comment: String = ""

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
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private func currentData() -> DepositFormData? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let amount = parsedAmount, amount > 0,
              let rate = parsedRate, rate >= 0 else { return nil }
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
                    TextField(L("accounts_core.detail.sheet.amount_placeholder"), text: $amountText)
                        .keyboardType(.decimalPad)
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
                    TextField(L("accounts_core.deposit_form.rate_placeholder"), text: $rateText)
                        .keyboardType(.decimalPad)
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
                        Toggle(L("accounts_core.deposit_form.auto_rollover"), isOn: $autoRollover)
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
                            TextField("%", text: $earlyClosePenaltyPercentText)
                                .keyboardType(.decimalPad)
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
