import SwiftUI
import SwiftData

/// Keeps risky product conversion separate from ordinary profile edits.
struct AccountProductTransitionSection: View {
    let account: Account
    let modelContext: ModelContext
    let onCommitted: () -> Void

    var body: some View {
        Section(L("accounts_core.transition.title")) {
            NavigationLink {
                AccountProductTransitionEditorView(
                    account: account, modelContext: modelContext, onCommitted: onCommitted
                )
            } label: {
                LabeledContent(L("accounts_core.transition.current")) {
                    Text(AccountProductTransitionPresentation.title(
                        for: account.productType ?? .unknownLegacy,
                        locale: AppLocalization.currentAppLocale
                    ))
                    .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }
}

/// Dedicated transition screen: all choices remain visible and never obscure the form in a menu.
struct AccountProductTransitionEditorView: View {
    let account: Account
    let modelContext: ModelContext
    let onCommitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var target: AccountProductType
    @State private var errorReason: String?
    @State private var showConversionConfirmation = false
    @State private var operationID = UUID().uuidString
    @State private var targetID = UUID()
    @State private var depositRateText = ""
    @State private var depositCapitalization: AccountDepositCapitalization = .monthly
    @State private var depositPayoutDay = Calendar.current.component(.day, from: Date())
    @State private var depositHasTerm = true
    @State private var depositTermEnd = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var depositAllowsTopUp = false
    @State private var depositAllowsEarlyClose = true
    @State private var depositPenaltyText = "0"

    init(account: Account, modelContext: ModelContext, onCommitted: @escaping () -> Void) {
        self.account = account
        self.modelContext = modelContext
        self.onCommitted = onCommitted
        _target = State(initialValue: AccountProductTransitionPresentation.availableTargets(
            current: account.productType
        ).first ?? .cash)
    }

    private var targets: [AccountProductType] {
        AccountProductTransitionPresentation.availableTargets(current: account.productType)
    }

    private var depositMetadata: DepositMeta? {
        guard target == .deposit else { return nil }
        return AccountProductTransitionFormMapper.depositMetadata(
            rateText: depositRateText,
            capitalization: depositCapitalization,
            payoutDay: depositPayoutDay,
            hasTerm: depositHasTerm,
            termEnd: depositTermEnd,
            allowsTopUp: depositAllowsTopUp,
            allowsEarlyClose: depositAllowsEarlyClose,
            penaltyPercentText: depositPenaltyText
        )
    }

    private var metadata: AccountProductMetadata {
        target == .deposit ? .init(deposit: depositMetadata) : Self.metadata(for: target, source: account)
    }

    private var decision: AccountProductTransitionKind {
        AccountProductTransitionPolicy.classify(
            source: account.productType ?? .unknownLegacy, sourceKind: account.kind,
            sourceMetadata: .init(account: account), target: target, targetMetadata: metadata,
            events: .make(events: account.events ?? [])
        )
    }

    private var canSubmit: Bool {
        if target == .deposit && depositMetadata == nil { return false }
        if case .blocked = decision { return false }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                sectionTitle(L("accounts_core.transition.current"))
                currentTypeCard
                sectionTitle(L("accounts_core.transition.target"))
                targetPicker
                if target == .deposit { depositTerms }
                decisionNotice
                if let errorReason {
                    Text(errorReason).font(.millioCalloutRegular).foregroundStyle(AppColors.error)
                }
            }
            .padding(AppSpacing.l)
        }
        .background(GradientBackground())
        .navigationTitle(L("accounts_core.transition.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(L("accounts_core.detail.sheet.cancel"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(actionTitle, action: submit)
                .font(.millioBodySemibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(
                    canSubmit ? AppColors.accentDarkBlue : AppColors.textTertiary
                ))
                .disabled(!canSubmit)
                .padding(.horizontal, AppSpacing.l)
                .padding(.vertical, AppSpacing.s)
                .background(.ultraThinMaterial)
        }
        .confirmationDialog(
            L("accounts_core.transition.conversion_warning"),
            isPresented: $showConversionConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("accounts_core.transition.convert"), role: .destructive) { convert() }
            Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) {}
        }
    }

    private var currentTypeCard: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(AppColors.brandPrimary)
            Text(productTitle(account.productType ?? .unknownLegacy)).font(.millioBodySemibold)
            Spacer()
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
    }

    private var targetPicker: some View {
        VStack(spacing: 0) {
            ForEach(targets, id: \.self) { value in
                Button {
                    target = value
                    errorReason = nil
                } label: {
                    HStack(spacing: AppSpacing.s) {
                        Text(productTitle(value)).font(.millioBody).foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        if target == value {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.brandPrimary)
                        }
                    }
                    .padding(AppSpacing.m)
                }
                .buttonStyle(.plain)
                if value != targets.last { Divider().overlay(AppColors.textTertiary.opacity(0.25)) }
            }
        }
        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
    }

    private var depositTerms: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            sectionTitle(L("accounts_core.deposit.action.edit_terms"))
            rateCard
            capitalizationCard
            lifecycleCard
        }
    }

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(L("accounts_core.deposit_form.rate_placeholder"))
                .font(.millioCaptionRegular).foregroundStyle(AppColors.textSecondary)
            AmountTextField(placeholder: "0", value: $depositRateText).font(.millioTitle)
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
    }

    private var capitalizationCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(L("accounts_core.deposit_form.capitalization_label"))
                .font(.millioCaptionRegular).foregroundStyle(AppColors.textSecondary)
            Picker(L("accounts_core.deposit_form.capitalization_label"), selection: $depositCapitalization) {
                Text(L("accounts_core.deposit_form.capitalization.none")).tag(AccountDepositCapitalization.none)
                Text(L("accounts_core.deposit_form.capitalization.monthly")).tag(AccountDepositCapitalization.monthly)
                Text(L("accounts_core.deposit_form.capitalization.quarterly")).tag(AccountDepositCapitalization.quarterly)
            }
            .pickerStyle(.segmented)
            if depositCapitalization.usesMonthlyPayoutDay {
                Stepper(value: $depositPayoutDay, in: 1...31) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("accounts_core.deposit_form.payout_day"))
                        Text("\(depositPayoutDay)").font(.millioHeadline).foregroundStyle(AppColors.brandPrimary)
                    }
                }
                Text(L("accounts_core.deposit_form.payout_day_hint"))
                    .font(.millioCaptionRegular).foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
    }

    private var lifecycleCard: some View {
        VStack(spacing: 0) {
            Toggle(L("accounts_core.deposit_form.has_term"), isOn: $depositHasTerm)
                .tint(AppColors.toggleOnGreen).padding(AppSpacing.m)
            if depositHasTerm {
                Divider().overlay(AppColors.textTertiary.opacity(0.25))
                DatePicker(L("accounts_core.deposit_form.term_end"), selection: $depositTermEnd, in: Date()..., displayedComponents: .date)
                    .padding(AppSpacing.m)
            }
            Divider().overlay(AppColors.textTertiary.opacity(0.25))
            Toggle(L("accounts_core.deposit_form.allows_top_up"), isOn: $depositAllowsTopUp)
                .tint(AppColors.toggleOnGreen).padding(AppSpacing.m)
            Divider().overlay(AppColors.textTertiary.opacity(0.25))
            Toggle(L("accounts_core.deposit_form.allows_early_close"), isOn: $depositAllowsEarlyClose)
                .tint(AppColors.toggleOnGreen).padding(AppSpacing.m)
            if depositAllowsEarlyClose {
                Divider().overlay(AppColors.textTertiary.opacity(0.25))
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(L("accounts_core.deposit_form.early_close_penalty")).font(.millioCalloutRegular)
                    HStack {
                        AmountTextField(placeholder: "0", value: $depositPenaltyText).font(.millioTitle)
                        Text("%").font(.millioTitle).foregroundStyle(AppColors.textSecondary)
                    }
                    Text(L("accounts_core.deposit.edit.preview_note"))
                        .font(.millioCaptionRegular).foregroundStyle(AppColors.textSecondary)
                }
                .padding(AppSpacing.m)
            }
        }
        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
    }

    @ViewBuilder private var decisionNotice: some View {
        if case .replacementConversion = decision {
            Label(L("accounts_core.transition.conversion_warning"), systemImage: "exclamationmark.triangle.fill")
                .font(.millioCalloutRegular).foregroundStyle(AppColors.warning)
        } else if case let .blocked(reason) = decision {
            Label(reasonTitle(reason), systemImage: "exclamationmark.shield.fill")
                .font(.millioCalloutRegular).foregroundStyle(AppColors.error)
        }
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value).font(.millioCaption).foregroundStyle(AppColors.textTertiary).textCase(.uppercase)
    }

    private var actionTitle: String {
        switch decision {
        case .inPlaceCorrection: L("accounts_core.transition.correct")
        case .replacementConversion: L("accounts_core.transition.convert")
        case .blocked: L("accounts_core.transition.unavailable")
        }
    }

    private func submit() {
        switch decision {
        case .inPlaceCorrection: correct()
        case .replacementConversion: showConversionConfirmation = true
        case .blocked: break
        }
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
        AccountProductTransitionPresentation.title(for: value, locale: AppLocalization.currentAppLocale)
    }

    private func reasonTitle(_: AccountProductTransitionBlockedReason) -> String {
        L("accounts_core.transition.unavailable")
    }

    private static func metadata(for target: AccountProductType, source: Account) -> AccountProductMetadata {
        switch target {
        case .debitCard, .bankAccount: .init(card: CardMeta())
        case .marketStock, .marketCrypto, .marketBond, .marketMetal, .genericMarketInvestment:
            .init(market: source.marketMeta)
        case .realEstate, .business, .vehicle, .otherManualAsset:
            .init(manualAsset: source.manualAssetMeta)
        default: .init()
        }
    }
}

enum AccountProductTransitionFormMapper {
    static func depositMetadata(
        rateText: String,
        capitalization: AccountDepositCapitalization,
        payoutDay: Int? = nil,
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
            rate: rate, capitalization: capitalization, termEnd: hasTerm ? termEnd : nil,
            payoutDay: capitalization.usesMonthlyPayoutDay ? payoutDay : nil,
            allowsTopUp: allowsTopUp, allowsEarlyClose: allowsEarlyClose,
            earlyClosePenalty: allowsEarlyClose
                ? penaltyValue.flatMap { Decimal(string: String($0 / 100)) }
                : nil,
            remindEnd: hasTerm, autoRollover: false
        )
    }
}
