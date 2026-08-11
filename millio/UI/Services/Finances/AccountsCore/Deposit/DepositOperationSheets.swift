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

struct DepositTermsEditSheet: View {
    let meta: DepositMeta
    let snapshot: DepositPresentationSnapshot
    let openingDate: Date
    let onSave: (DepositMeta) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rateText: String
    @State private var termEnd: Date
    @State private var capitalization: AccountDepositCapitalization
    @State private var payoutDay: Int
    @State private var allowsTopUp: Bool
    @State private var allowsEarlyClose: Bool
    @State private var penaltyText: String

    init(
        meta: DepositMeta,
        snapshot: DepositPresentationSnapshot,
        openingDate: Date,
        onSave: @escaping (DepositMeta) -> Void
    ) {
        self.meta = meta
        self.snapshot = snapshot
        self.openingDate = openingDate
        self.onSave = onSave
        _rateText = State(initialValue: NSDecimalNumber(decimal: meta.rate).stringValue)
        _termEnd = State(initialValue: meta.termEnd ?? Date())
        _capitalization = State(initialValue: meta.capitalization)
        _payoutDay = State(initialValue: meta.payoutDay ?? Calendar.current.component(.day, from: openingDate))
        _allowsTopUp = State(initialValue: meta.allowsTopUp)
        _allowsEarlyClose = State(initialValue: meta.allowsEarlyClose)
        _penaltyText = State(initialValue: NSDecimalNumber(decimal: (meta.earlyClosePenalty ?? 0) * 100).stringValue)
    }

    private var rate: Decimal? { Decimal(string: AmountInputFormatter.sanitize(rateText)) }
    private var penalty: Decimal? { Decimal(string: AmountInputFormatter.sanitize(penaltyText)) }
    private var candidate: DepositMeta? {
        guard let rate, rate > 0,
              !allowsEarlyClose || penalty.map({ $0 >= 0 && $0 <= 100 }) == true else { return nil }
        return DepositMeta(
            rate: rate, capitalization: capitalization, termEnd: meta.termEnd == nil ? nil : termEnd,
            payoutDay: capitalization == .none ? nil : payoutDay,
            allowsTopUp: allowsTopUp, allowsEarlyClose: allowsEarlyClose,
            earlyClosePenalty: allowsEarlyClose ? penalty.map { $0 / 100 } : nil,
            remindEnd: meta.remindEnd, autoRollover: meta.autoRollover
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("accounts_core.deposit.action.edit_terms")) {
                    AmountTextField(placeholder: L("accounts_core.deposit_form.rate_placeholder"), value: $rateText)
                    Picker(L("accounts_core.deposit_form.capitalization_label"), selection: $capitalization) {
                        Text(L("accounts_core.deposit_form.capitalization.none")).tag(AccountDepositCapitalization.none)
                        Text(L("accounts_core.deposit_form.capitalization.monthly")).tag(AccountDepositCapitalization.monthly)
                        Text(L("accounts_core.deposit_form.capitalization.quarterly")).tag(AccountDepositCapitalization.quarterly)
                    }
                    if capitalization != .none {
                        Picker(L("accounts_core.deposit_form.payout_day"), selection: $payoutDay) {
                            ForEach(1...31, id: \.self) { day in Text("\(day)").tag(day) }
                        }
                        Text(L("accounts_core.deposit_form.payout_day_hint"))
                            .font(.millioCaptionRegular)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    if meta.termEnd != nil {
                        DatePicker(L("accounts_core.deposit_form.term_end"), selection: $termEnd, in: Date()..., displayedComponents: .date)
                    }
                    Toggle(L("accounts_core.deposit_form.allows_top_up"), isOn: $allowsTopUp)
                    Toggle(L("accounts_core.deposit_form.allows_early_close"), isOn: $allowsEarlyClose)
                    if allowsEarlyClose {
                        AmountTextField(placeholder: L("accounts_core.deposit_form.early_close_penalty"), value: $penaltyText)
                    }
                }
                Section(L("accounts_core.deposit.edit.preview")) {
                    Text(L("accounts_core.deposit.edit.preview_note"))
                        .font(.millioCaptionRegular)
                        .foregroundStyle(AppColors.textSecondary)
                    if let estimate = editedMaturityAmount {
                        Text("\(NSDecimalNumber(decimal: estimate).stringValue) \(snapshot.currency)")
                            .font(.millioBodySemibold)
                    }
                }
            }
            .navigationTitle(L("accounts_core.deposit.action.edit_terms"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("accounts_core.detail.sheet.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("accounts_core.detail.sheet.save")) { if let candidate { onSave(candidate) } }
                        .disabled(candidate == nil)
                }
            }
        }
    }

    private var editedMaturityAmount: Decimal? {
        guard let candidate, let balance = snapshot.currentBalance.value, let termEnd = candidate.termEnd else {
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
