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
    /// Вклад открывается сегодняшним днём, поэтому и выплата по умолчанию — сегодняшнее число:
    /// тот же дефолт, что и в правке условий (`meta.payoutDay ?? день открытия`).
    @State private var payoutDay: Int = Calendar.current.component(.day, from: Date())
    @State private var hasTerm: Bool = true
    @State private var termEnd: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var allowsTopUp: Bool = false
    @State private var allowsEarlyClose: Bool = true
    @State private var earlyClosePenaltyPercentText: String = "0"
    @State private var remindEnd: Bool = true
    @State private var autoRollover: Bool = false
    @State private var comment: String = ""
    @State private var isTaxable: Bool = false
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
            payoutDay: payoutDay,
            allowsTopUp: allowsTopUp,
            allowsEarlyClose: allowsEarlyClose,
            earlyClosePenaltyPercent: allowsEarlyClose ? (parseNumber(earlyClosePenaltyPercentText) ?? 0) : 0,
            remindEnd: remindEnd && hasTerm,
            autoRollover: autoRollover && hasTerm,
            comment: comment.trimmingCharacters(in: .whitespacesAndNewlines),
            isTaxable: isTaxable
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            DepositTermsInputCard(
                amountText: $amountText,
                currency: $selectedCurrency,
                rateText: $rateText,
                capitalization: $capitalization,
                payoutDay: $payoutDay,
                isTaxable: $isTaxable,
                isFocused: $inputFocused
            )
            termSection
            optionsSection
            previewSection
            groupSection
            commentSection
        }
        // Наблюдаем СОБРАННЫЙ результат, а не каждое поле по отдельности: полтора десятка
        // `.onChange` дублировали друг друга и роняли type-checker этого `body`
        // («unable to type-check this expression in reasonable time») на 15-м поле.
        .onChange(of: currentData()) { _, newValue in onDepositDataChanged(newValue) }
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
                } else if let interest = creationPreview.interest {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(String(
                            format: L("accounts_core.deposit.creation.interest_format"),
                            AmountTextField.formatted(from: NSDecimalNumber(decimal: interest).stringValue),
                            selectedCurrency
                        ))
                        // Бессрочный вклад доходность имеет, а «суммы к концу срока» — нет.
                        if let maturity = creationPreview.maturityAmount {
                            Text(String(
                                format: L("accounts_core.deposit.creation.maturity_format"),
                                AmountTextField.formatted(from: NSDecimalNumber(decimal: maturity).stringValue),
                                selectedCurrency
                            ))
                            .font(.millioBodySemibold)
                        } else {
                            Text(L("accounts_core.deposit.creation.savings_preview"))
                                .font(.millioCaptionRegular)
                                .foregroundStyle(AppColors.textSecondary)
                        }
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
    /// Число месяца выплаты процентов как его выбрал пользователь. Отбрасывать его для шаговых
    /// периодичностей — работа бриджа (`AccountsCoreAdditionBridge.depositMeta`), один нормализатор.
    let payoutDay: Int
    let allowsTopUp: Bool
    let allowsEarlyClose: Bool
    /// Ввод пользователя В ПРОЦЕНТАХ (0…100) — бридж делит на 100 при сборке `DepositMeta`.
    let earlyClosePenaltyPercent: Double
    let remindEnd: Bool
    let autoRollover: Bool
    let comment: String
    /// Тег «доход облагается налогом» — маркировка пользователя, в расчёты не входит.
    let isTaxable: Bool
}
