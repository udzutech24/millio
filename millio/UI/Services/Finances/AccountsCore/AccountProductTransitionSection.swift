import SwiftUI
import SwiftData

struct AccountProductTransitionSection: View {
    let account: Account
    let modelContext: ModelContext
    let onCommitted: () -> Void
    @State private var target: AccountProductType
    @State private var errorReason: String?
    @State private var showConversionConfirmation = false
    @State private var operationID = UUID().uuidString
    @State private var targetID = UUID()
    @State private var depositRateText = ""
    @State private var depositCapitalization: AccountDepositCapitalization = .monthly
    @State private var depositHasTerm = true
    @State private var depositTermEnd = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var depositAllowsTopUp = false
    @State private var depositAllowsEarlyClose = true
    @State private var depositPenaltyText = "100"

    init(account: Account, modelContext: ModelContext, onCommitted: @escaping () -> Void) {
        self.account = account
        self.modelContext = modelContext
        self.onCommitted = onCommitted
        _target = State(initialValue: Self.availableTargets(current: account.productType).first ?? .cash)
    }

    static func availableTargets(current: AccountProductType?) -> [AccountProductType] {
        AccountProductType.allCases.filter {
            $0 != .unknownLegacy && $0 != (current ?? .unknownLegacy)
        }
    }

    private var depositMetadata: DepositMeta? {
        guard target == .deposit else { return nil }
        return AccountProductTransitionFormMapper.depositMetadata(
            rateText: depositRateText,
            capitalization: depositCapitalization,
            hasTerm: depositHasTerm,
            termEnd: depositTermEnd,
            allowsTopUp: depositAllowsTopUp,
            allowsEarlyClose: depositAllowsEarlyClose,
            penaltyPercentText: depositPenaltyText
        )
    }

    private var metadata: AccountProductMetadata {
        if target == .deposit { return .init(deposit: depositMetadata) }
        return Self.metadata(for: target, source: account)
    }
    private var decision: AccountProductTransitionKind {
        AccountProductTransitionPolicy.classify(
            source: account.productType ?? .unknownLegacy, sourceKind: account.kind,
            sourceMetadata: .init(account: account), target: target, targetMetadata: metadata,
            events: .make(events: account.events ?? [])
        )
    }

    var body: some View {
        Section(L("accounts_core.transition.title")) {
            Picker(L("accounts_core.transition.target"), selection: $target) {
                ForEach(Self.availableTargets(current: account.productType), id: \.self) {
                    Text(productTitle($0)).tag($0)
                }
            }
            .pickerStyle(.menu)
            if target == .deposit {
                depositTerms
            }
            if target != .deposit || depositMetadata != nil {
                switch decision {
                case .inPlaceCorrection:
                    transitionButton(L("accounts_core.transition.correct"), destructive: false) { correct() }
                case .replacementConversion:
                    Text(L("accounts_core.transition.conversion_warning"))
                        .font(.millioCaptionRegular).foregroundStyle(AppColors.warning)
                    transitionButton(L("accounts_core.transition.convert"), destructive: true) {
                        showConversionConfirmation = true
                    }
                case let .blocked(reason):
                    Label(reasonTitle(reason), systemImage: "exclamationmark.shield.fill")
                        .font(.millioCaptionRegular).foregroundStyle(AppColors.textSecondary)
                }
            }
            if let errorReason { Text(errorReason).font(.millioCaptionRegular).foregroundStyle(AppColors.error) }
        }
        .accessibilityElement(children: .contain)
        .confirmationDialog(
            L("accounts_core.transition.conversion_warning"),
            isPresented: $showConversionConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("accounts_core.transition.convert"), role: .destructive) { convert() }
            Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var depositTerms: some View {
        AmountTextField(
            placeholder: L("accounts_core.deposit_form.rate_placeholder"),
            value: $depositRateText
        )
        Picker(L("accounts_core.deposit_form.capitalization_label"), selection: $depositCapitalization) {
            Text(L("accounts_core.deposit_form.capitalization.none")).tag(AccountDepositCapitalization.none)
            Text(L("accounts_core.deposit_form.capitalization.monthly")).tag(AccountDepositCapitalization.monthly)
            Text(L("accounts_core.deposit_form.capitalization.quarterly")).tag(AccountDepositCapitalization.quarterly)
        }
        Toggle(L("accounts_core.deposit_form.has_term"), isOn: $depositHasTerm)
        if depositHasTerm {
            DatePicker(
                L("accounts_core.deposit_form.term_end"),
                selection: $depositTermEnd,
                in: Date()...,
                displayedComponents: .date
            )
        }
        Toggle(L("accounts_core.deposit_form.allows_top_up"), isOn: $depositAllowsTopUp)
        Toggle(L("accounts_core.deposit_form.allows_early_close"), isOn: $depositAllowsEarlyClose)
        if depositAllowsEarlyClose {
            AmountTextField(
                placeholder: L("accounts_core.deposit_form.early_close_penalty"),
                value: $depositPenaltyText
            )
        }
        if depositMetadata == nil {
            Label(L("accounts_core.transition.deposit_terms_required"), systemImage: "info.circle")
                .font(.millioCaptionRegular)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func transitionButton(_ title: String, destructive: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(destructive ? AppColors.error : AppColors.accentDarkBlue)
            .accessibilityHint(destructive ? L("accounts_core.transition.conversion_warning") : "")
    }

    private func correct() {
        do {
            try AccountProductTransitionCoordinator(modelContext: modelContext).correct(.init(
                operationID: operationID, sourceID: account.id, target: target,
                targetMetadata: metadata, effectiveDate: Date()
            ))
            onCommitted()
        } catch { errorReason = L("accounts_core.transition.failed") }
    }

    private func convert() {
        do {
            try AccountProductTransitionCoordinator(modelContext: modelContext).convert(.init(
                operationID: operationID, sourceID: account.id, targetID: targetID, target: target,
                targetMetadata: metadata, effectiveDate: Date()
            ))
            onCommitted()
        } catch { errorReason = L("accounts_core.transition.failed") }
    }

    private func productTitle(_ value: AccountProductType) -> String {
        FinancesL10n.tr(value.localizationKey, locale: AppLocalization.currentAppLocale)
    }

    private func reasonTitle(_: AccountProductTransitionBlockedReason) -> String {
        L("accounts_core.transition.unavailable")
    }

    private static func metadata(for target: AccountProductType, source: Account) -> AccountProductMetadata {
        switch target {
        case .debitCard, .bankAccount: return .init(card: CardMeta())
        case .marketStock, .marketCrypto, .marketBond, .marketMetal, .genericMarketInvestment:
            return .init(market: source.marketMeta)
        case .realEstate, .business, .vehicle, .otherManualAsset: return .init(manualAsset: source.manualAssetMeta)
        default: return .init()
        }
    }
}

enum AccountProductTransitionFormMapper {
    static func depositMetadata(
        rateText: String,
        capitalization: AccountDepositCapitalization,
        hasTerm: Bool,
        termEnd: Date,
        allowsTopUp: Bool,
        allowsEarlyClose: Bool,
        penaltyPercentText: String
    ) -> DepositMeta? {
        guard let rateValue = AmountInputFormatter.parse(rateText), rateValue > 0,
              let rate = Decimal(string: String(rateValue)) else { return nil }
        let penaltyValue = AmountInputFormatter.parse(penaltyPercentText)
        guard !allowsEarlyClose || penaltyValue.map({ (0...100).contains($0) }) == true else { return nil }
        return DepositMeta(
            rate: rate,
            capitalization: capitalization,
            termEnd: hasTerm ? termEnd : nil,
            payoutDay: nil,
            allowsTopUp: allowsTopUp,
            allowsEarlyClose: allowsEarlyClose,
            earlyClosePenalty: allowsEarlyClose
                ? penaltyValue.flatMap { Decimal(string: String($0 / 100)) }
                : nil,
            remindEnd: hasTerm,
            autoRollover: false
        )
    }
}

private extension AccountProductType {
    var localizationKey: String {
        switch self {
        case .cash: "accounts_core.kind.cash"
        case .debitCard: "finances.add_account.product.card.title"
        case .creditCard, .loan: "finances.add_account.product.credit.title"
        case .bankAccount: "finances.add_account.product.account.title"
        case .deposit: "finances.add_account.product.deposit.title"
        case .receivable, .payable: "finances.add_account.product.debt.title"
        case .marketStock: "finances.add_account.product.stocks.title"
        case .marketCrypto: "finances.add_account.product.crypto.title"
        case .marketBond, .marketMetal, .genericMarketInvestment:
            "finances.add_account.product.investment.title"
        case .realEstate: "finances.add_account.product.house.title"
        case .business: "finances.add_account.product.business.title"
        case .vehicle, .otherManualAsset, .unknownLegacy: "finances.add_account.product.other.title"
        }
    }
}
