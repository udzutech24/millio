import SwiftUI
import SwiftData

struct DepositTopUpSheet: View {
    let deposit: Account
    let modelContext: ModelContext
    let onSave: (Account, Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sourceID: UUID?
    @State private var amountText = ""

    private var sources: [Account] {
        let allowed: Set<AccountProductType> = [.cash, .debitCard, .bankAccount]
        return ((try? modelContext.fetch(FetchDescriptor<Account>())) ?? []).filter {
            $0.id != deposit.id && $0.currency == deposit.currency && $0.participates(on: Date())
                && allowed.contains($0.productType ?? .unknownLegacy)
        }
    }
    private var amount: Decimal? {
        let value = Decimal(string: AmountInputFormatter.sanitize(amountText))
        return value.map { $0 > 0 ? $0 : nil } ?? nil
    }
    private var source: Account? { sources.first { $0.id == sourceID } }

    var body: some View {
        NavigationStack {
            Form {
                if sources.isEmpty {
                    Text(L("accounts_core.detail.transfer.no_destinations"))
                } else {
                    Picker(L("accounts_core.deposit.top_up.source"), selection: $sourceID) {
                        ForEach(sources, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                    }
                    AmountTextField(placeholder: L("accounts_core.detail.sheet.amount_placeholder"), value: $amountText)
                }
            }
            .navigationTitle(L("accounts_core.deposit.action.top_up"))
            .onAppear { sourceID = sourceID ?? sources.first?.id }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("accounts_core.detail.sheet.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("accounts_core.detail.sheet.save")) {
                        guard let source, let amount else { return }
                        onSave(source, amount)
                    }.disabled(source == nil || amount == nil)
                }
            }
        }
    }
}

struct DepositCloseSheet: View {
    let source: Account
    let modelContext: ModelContext
    let preview: DepositEarlyClosePreview?
    let isMaturity: Bool
    let onSave: (Account) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var destinationID: UUID?

    private var destinations: [Account] {
        let allowed: Set<AccountProductType> = [.cash, .debitCard, .bankAccount]
        return ((try? modelContext.fetch(FetchDescriptor<Account>())) ?? []).filter {
            $0.id != source.id && $0.currency == source.currency && $0.participates(on: Date())
                && allowed.contains($0.productType ?? .unknownLegacy)
        }
    }
    private var destination: Account? { destinations.first { $0.id == destinationID } }

    var body: some View {
        NavigationStack {
            Form {
                if let preview, !isMaturity {
                    Section(L("accounts_core.deposit.close.preview")) {
                        row(L("accounts_core.deposit.close.lost_interest"), preview.lostInterest)
                        row(L("accounts_core.deposit.close.penalty"), preview.penalty)
                        row(L("accounts_core.deposit.close.net_proceeds"), preview.netProceeds)
                    }
                }
                Section(L("accounts_core.detail.sheet.transfer.destination")) {
                    if destinations.isEmpty { Text(L("accounts_core.detail.transfer.no_destinations")) }
                    else {
                        Picker(L("accounts_core.detail.sheet.transfer.destination"), selection: $destinationID) {
                            ForEach(destinations, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
            }
            .navigationTitle(isMaturity ? L("accounts_core.deposit.action.withdraw_maturity") : L("accounts_core.detail.deposit.action.early_close"))
            .onAppear { destinationID = destinationID ?? destinations.first?.id }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("accounts_core.detail.sheet.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("accounts_core.detail.sheet.save")) {
                        guard let destination else { return }
                        onSave(destination)
                    }.disabled(destination == nil)
                }
            }
        }
    }

    private func row(_ title: String, _ value: Decimal) -> some View {
        HStack { Text(title); Spacer(); Text("\(NSDecimalNumber(decimal: value).stringValue) \(source.currency)") }
    }
}

/// Sets the confirmed deposit balance on a chosen date. The caller owns the atomic writer so this
/// view cannot accidentally combine a balance correction with a terms edit.
struct DepositBalanceAdjustmentSheet: View {
    let currentBalance: Decimal
    let currency: String
    let onSave: (Decimal, Date, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var date = Date()
    @State private var note = ""

    init(
        currentBalance: Decimal,
        currency: String,
        onSave: @escaping (Decimal, Date, String?) -> Void
    ) {
        self.currentBalance = currentBalance
        self.currency = currency
        self.onSave = onSave
        _amountText = State(initialValue: NSDecimalNumber(decimal: currentBalance).stringValue)
    }

    private var amount: Decimal? {
        Decimal(string: AmountInputFormatter.sanitize(amountText))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("accounts_core.detail.action.adjust_balance")) {
                    AmountTextField(
                        placeholder: L("accounts_core.detail.sheet.adjust.new_balance"),
                        value: $amountText
                    )
                    Text(currency)
                        .font(.millioCaptionRegular)
                        .foregroundStyle(AppColors.textSecondary)
                    DatePicker(
                        L("accounts_core.detail.sheet.date_label"),
                        selection: $date,
                        displayedComponents: .date
                    )
                    TextField(L("accounts_core.detail.sheet.note_placeholder"), text: $note)
                }
            }
            .navigationTitle(L("accounts_core.detail.action.adjust_balance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("accounts_core.detail.sheet.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("accounts_core.detail.sheet.save")) {
                        guard let amount else { return }
                        onSave(amount, date, note.isEmpty ? nil : note)
                    }
                    .disabled(amount == nil || amount! < 0)
                }
            }
        }
    }
}

/// Результат правки вклада: три независимых изменения, у каждого СВОЙ писатель на стороне
/// вызывающего экрана. Форма не пишет ничего сама — иначе коррекция суммы и правка условий
/// слились бы в одну операцию, а в ленте вклада это принципиально разные события.
struct DepositTermsEditResult {
    let meta: DepositMeta
    /// Новый подтверждённый баланс; `nil` — сумму не трогали, писать нечего.
    /// Пишется ТЕМ ЖЕ `DepositOperationCoordinator.adjustBalance`, что и отдельный
    /// `DepositBalanceAdjustmentSheet`: только он умеет посчитать дельту и перестроить прогноз.
    let newBalance: Decimal?
    /// Заметка счёта после правки (обрезанная; пустая → `nil`).
    let note: String?
}

/// Правка существующего вклада. Набор полей намеренно совпадает с формой создания
/// (`InlineDepositCreateForm`): общий блок `DepositTermsInputCard` не даёт им снова разъехаться —
/// раньше в правке не было ни суммы, ни валюты, ни заметки, зато жил свой пикер периодичности.
struct DepositTermsEditSheet: View {
    let meta: DepositMeta
    let snapshot: DepositPresentationSnapshot
    let openingDate: Date
    let currentNote: String?
    let onSave: (DepositTermsEditResult) -> Void

    /// Высота нижней кнопки сохранения — визуальный контракт экрана, унаследованный от прежней формы.
    private enum Layout {
        static let saveButtonHeight: CGFloat = 52
    }

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String
    @State private var currency: String
    @State private var rateText: String
    @State private var termEnd: Date
    @State private var capitalization: AccountDepositCapitalization
    @State private var payoutDay: Int
    @State private var allowsTopUp: Bool
    @State private var allowsEarlyClose: Bool
    @State private var penaltyText: String
    @State private var isTaxable: Bool
    @State private var note: String
    @FocusState private var inputFocused: Bool

    init(
        meta: DepositMeta,
        snapshot: DepositPresentationSnapshot,
        openingDate: Date,
        currentNote: String? = nil,
        onSave: @escaping (DepositTermsEditResult) -> Void
    ) {
        self.meta = meta
        self.snapshot = snapshot
        self.openingDate = openingDate
        self.currentNote = currentNote
        self.onSave = onSave
        _amountText = State(
            initialValue: snapshot.currentBalance.value
                .map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        )
        _currency = State(initialValue: snapshot.currency)
        _rateText = State(initialValue: NSDecimalNumber(decimal: meta.rate).stringValue)
        _termEnd = State(initialValue: meta.termEnd ?? Date())
        _capitalization = State(initialValue: meta.capitalization)
        _payoutDay = State(initialValue: meta.payoutDay ?? Calendar.current.component(.day, from: openingDate))
        _allowsTopUp = State(initialValue: meta.allowsTopUp)
        _allowsEarlyClose = State(initialValue: meta.allowsEarlyClose)
        _penaltyText = State(initialValue: NSDecimalNumber(decimal: (meta.earlyClosePenalty ?? 0) * 100).stringValue)
        _isTaxable = State(initialValue: meta.isTaxable ?? false)
        _note = State(initialValue: currentNote ?? "")
    }

    private var amount: Decimal? { Decimal(string: AmountInputFormatter.sanitize(amountText)) }
    private var rate: Decimal? { Decimal(string: AmountInputFormatter.sanitize(rateText)) }
    private var penalty: Decimal? { Decimal(string: AmountInputFormatter.sanitize(penaltyText)) }

    private var candidate: DepositMeta? {
        guard let rate, rate > 0,
              !allowsEarlyClose || penalty.map({ $0 >= 0 && $0 <= 100 }) == true else { return nil }
        return DepositMeta(
            rate: rate, capitalization: capitalization, termEnd: meta.termEnd == nil ? nil : termEnd,
            payoutDay: capitalization.usesMonthlyPayoutDay ? payoutDay : nil,
            allowsTopUp: allowsTopUp, allowsEarlyClose: allowsEarlyClose,
            earlyClosePenalty: allowsEarlyClose ? penalty.map { $0 / 100 } : nil,
            remindEnd: meta.remindEnd, autoRollover: meta.autoRollover,
            isTaxable: isTaxable
        )
    }

    /// Единственная точка сборки результата: и кнопка «Сохранить», и её `disabled` смотрят сюда,
    /// поэтому «кнопка активна, а сохранять нечего» невозможно по построению.
    private var result: DepositTermsEditResult? {
        guard let candidate, let amount, amount >= 0 else { return nil }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return DepositTermsEditResult(
            meta: candidate,
            newBalance: amount == snapshot.currentBalance.value ? nil : amount,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    DepositTermsInputCard(
                        amountText: $amountText,
                        currency: $currency,
                        rateText: $rateText,
                        capitalization: $capitalization,
                        payoutDay: $payoutDay,
                        isTaxable: $isTaxable,
                        isFocused: $inputFocused,
                        isCurrencyEditable: false
                    )
                    optionsSection
                    previewSection
                    commentSection
                }
                .padding(AppSpacing.l)
            }
            .navigationTitle(L("accounts_core.deposit.action.edit_terms"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(L("accounts_core.detail.sheet.cancel"))
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("common.done")) { inputFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) { saveBar }
        }
    }

    // MARK: - Секции

    private var optionsSection: some View {
        termsCard {
            if meta.termEnd != nil {
                DatePicker(
                    L("accounts_core.deposit_form.term_end"),
                    selection: $termEnd, in: Date()..., displayedComponents: .date
                )
            }
            Toggle(L("accounts_core.deposit_form.allows_top_up"), isOn: $allowsTopUp)
                .tint(AppColors.toggleOnGreen)
            Toggle(L("accounts_core.deposit_form.allows_early_close"), isOn: $allowsEarlyClose)
                .tint(AppColors.toggleOnGreen)
            if allowsEarlyClose {
                HStack {
                    Text(L("accounts_core.deposit_form.early_close_penalty"))
                        .font(.millioCalloutRegular)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    AmountTextField(placeholder: "%", value: $penaltyText)
                        .focused($inputFocused)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            sectionTitle(L("accounts_core.deposit.edit.preview"))
            termsCard {
                Text(L("accounts_core.deposit.edit.preview_note"))
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.textSecondary)
                if let estimate = editedMaturityAmount {
                    Text(
                        DepositAmountTextFormatter.string(
                            estimate,
                            currency: snapshot.currency,
                            locale: AppLocalization.currentAppLocale
                        )
                    )
                        .font(.millioBodySemibold)
                }
            }
        }
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            sectionTitle(L("accounts_core.deposit_form.section.comment"))
            termsCard {
                TextField(L("accounts_core.deposit_form.comment_placeholder"), text: $note)
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
    }

    private var saveBar: some View {
        Button(L("accounts_core.detail.sheet.save")) {
            if let result { onSave(result) }
        }
        .font(.millioBodySemibold)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: Layout.saveButtonHeight)
        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(
            result == nil ? AppColors.textTertiary : AppColors.accentDarkBlue
        ))
        .disabled(result == nil)
        .padding(.horizontal, AppSpacing.l)
        .padding(.vertical, AppSpacing.s)
        .background(.ultraThinMaterial)
    }

    private func termsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m, content: content)
            .padding(AppSpacing.m)
            .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.millioCaption)
            .foregroundStyle(AppColors.textTertiary)
            .textCase(.uppercase)
    }

    /// Прогноз считается от ОТРЕДАКТИРОВАННОЙ суммы, а не от текущего баланса: пользователь правит
    /// сумму и ставку в одной форме и должен видеть результат обеих правок сразу.
    private var editedMaturityAmount: Decimal? {
        guard let candidate,
              let balance = amount ?? snapshot.currentBalance.value,
              let termEnd = candidate.termEnd else {
            return snapshot.maturityAmount.value
        }
        return DepositCreationPreview.make(
            amount: balance, rate: candidate.rate, openingDate: Date(), termEnd: termEnd,
            hasTerm: true,
            earlyClosePenaltyPercent: candidate.earlyClosePenalty.map { $0 * 100 },
            allowsEarlyClose: candidate.allowsEarlyClose,
            remindEnd: candidate.remindEnd, autoRollover: candidate.autoRollover
        ).maturityAmount
    }
}
