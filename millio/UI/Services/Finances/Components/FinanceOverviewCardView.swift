//
//  FinanceOverviewCardView.swift
//  millio
//
//  Бухгалтерский обзор финансов на главном экране:
//  в компактном виде показывает структуру debit-credit без дубля общей суммы,
//  а в full screen сохраняет saldo и раскрытие по группам/счетам.
//

import SwiftUI
import SwiftData

enum FinanceOverviewCardChrome {
    case standalone
    case embedded
}

struct FinanceOverviewCardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    @ObservedObject var financeViewModel: FinanceViewModel
    let chrome: FinanceOverviewCardChrome
    let onLedgerPresentationChange: (FinanceOverviewLedgerPresentation?) -> Void

    @State private var dynamicsViewModel: FinanceDynamicsViewModel?
    @State private var isLoading: Bool = false
    @State private var showExpandedChart: Bool = false
    @State private var ledgerPresentation: FinanceOverviewLedgerPresentation?
    @State private var expandedSheetSide: FinanceOverviewLedgerSide?
    @State private var expandedDetailGroupIDs: Set<String> = []

    init(
        financeViewModel: FinanceViewModel,
        chrome: FinanceOverviewCardChrome = .standalone,
        onLedgerPresentationChange: @escaping (FinanceOverviewLedgerPresentation?) -> Void = { _ in }
    ) {
        self.financeViewModel = financeViewModel
        self.chrome = chrome
        self.onLedgerPresentationChange = onLedgerPresentationChange
    }

    private var localizationLocale: Locale { AppLocalization.currentAppLocale }

    var body: some View {
        content
        .onAppear {
            ensureViewModel()
            Task { await reload() }
        }
        .onChange(of: reloadToken) { _, _ in
            Task { await reload() }
        }
        .fullScreenCover(isPresented: $showExpandedChart) {
            expandedSheet
        }
    }

    @ViewBuilder
    private var content: some View {
        let section = VStack(alignment: .leading, spacing: 16) {
            if !EntitlementPolicy.canUseFinanceCharts(isPro: appState.isPro) {
                blockedState
            } else if isLoading {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let ledgerPresentation, ledgerPresentation.hasData {
                assetsLiabilitiesStackedBar(presentation: ledgerPresentation)
            } else {
                emptyState
            }
        }

        switch chrome {
        case .standalone:
            section
                .padding(16)
                .background(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        case .embedded:
            section
        }
    }

    private func openExpandedChart(side: FinanceOverviewLedgerSide?) {
        expandedSheetSide = side
        showExpandedChart = true
    }

    private func ensureViewModel() {
        guard dynamicsViewModel == nil else { return }
        dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel
        )
        dynamicsViewModel?.handle(.loadData)
    }

    private func reload() async {
        guard let dynamicsViewModel else { return }
        guard EntitlementPolicy.canUseFinanceCharts(isPro: appState.isPro) else {
            ledgerPresentation = nil
            onLedgerPresentationChange(nil)
            return
        }

        isLoading = true
        dynamicsViewModel.handle(.loadData)
        let presentation = await buildLedgerPresentation(with: dynamicsViewModel)
        ledgerPresentation = presentation
        // Передаём и пустую презентацию: hero покажет нейтральное кольцо вместо исчезающего
        // элемента, а `balanceComposition` гарантирует безопасные 0/0 без NaN.
        onLedgerPresentationChange(presentation)
        isLoading = false
    }

    private var reloadToken: String {
        // [Ф5c.7 contract] `state.accounts`/`state.groups` теперь ПЕРВИЧНЫЙ источник (было
        // отдельными coreAccounts/coreGroups рядом с легаси). Легаси availableCards/Credits/
        // Investments остаются в токене как fallback-хвост (invariant 9 §2.1).
        let accountsPart = financeViewModel.state.accounts.map {
            "\($0.id)_\($0.name)_\($0.events?.count ?? 0)_\($0.archivedAt?.timeIntervalSince1970 ?? 0)_\($0.group?.id.uuidString ?? "nil")"
        }.sorted().joined(separator: "|")
        let groupsPart = financeViewModel.state.groups.map {
            "\($0.id)_\($0.name)_\($0.order)"
        }.sorted().joined(separator: "|")

        let cards = financeViewModel.state.availableCards.map {
            "\($0.cardUniqueID)_\($0.balance)_\($0.updatedAt.timeIntervalSince1970)"
        }.joined(separator: "|")
        let credits = financeViewModel.state.availableCredits.map {
            "\($0.creditUniqueID)_\($0.remainingAmount)_\($0.updatedAt.timeIntervalSince1970)"
        }.joined(separator: "|")
        let investments = financeViewModel.state.availableInvestments.map {
            "\($0.investmentUniqueID)_\($0.amount)_\($0.updatedAt.timeIntervalSince1970)"
        }.joined(separator: "|")

        return [
            financeViewModel.state.displayCurrency,
            accountsPart,
            groupsPart,
            cards,
            credits,
            investments
        ].joined(separator: "~")
    }

    private func buildLedgerPresentation(
        with dynamicsViewModel: FinanceDynamicsViewModel
    ) async -> FinanceOverviewLedgerPresentation {
        var items: [FinanceOverviewLedgerSourceItem] = []
        var attachedKeys: Set<String> = []

        let cardsByID = Dictionary(uniqueKeysWithValues: financeViewModel.state.availableCards.map { ($0.cardUniqueID, $0) })
        let creditsByID = Dictionary(uniqueKeysWithValues: financeViewModel.state.availableCredits.map { ($0.creditUniqueID, $0) })
        let investmentsByID = Dictionary(uniqueKeysWithValues: financeViewModel.state.availableInvestments.map { ($0.investmentUniqueID, $0) })

        let groups = financeViewModel.state.groups.sorted {
            if $0.order != $1.order {
                return $0.order < $1.order
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        for group in groups {
            // Core-счета группы — ПЕРВИЧНЫЙ источник (было: легаси-junction + отдельный core-луп).
            for account in sortedCoreAccounts(group.accounts ?? []) {
                if let item = await makeCoreLedgerItem(
                    account: account,
                    groupID: group.groupUniqueID,
                    groupName: group.name,
                    groupColorHex: group.colorHex
                ) {
                    items.append(item)
                }
            }
            // Легаси-fallback: непроконвертированный хвост в одноимённой `FinanceGroup` (invariant 9).
            for account in sortedAccounts(financeViewModel.legacyAccountsMatchingGroupName(group.name)) {
                attachedKeys.insert(accountKey(type: account.accountType, id: account.accountID))
                if let item = await makeLedgerItem(
                    account: account,
                    groupID: group.groupUniqueID,
                    groupName: group.name,
                    groupColorHex: group.colorHex,
                    cardsByID: cardsByID,
                    creditsByID: creditsByID,
                    investmentsByID: investmentsByID,
                    dynamicsViewModel: dynamicsViewModel
                ) {
                    items.append(item)
                }
            }
        }

        // Ungrouped core-счета (канон `group == nil`, не сущность).
        for account in sortedCoreAccounts(financeViewModel.ungroupedAccounts()) {
            if let item = await makeCoreLedgerItem(
                account: account,
                groupID: FinanceSystemGroups.ungroupedName,
                groupName: FinanceSystemGroups.ungroupedName,
                groupColorHex: nil
            ) {
                items.append(item)
            }
        }

        for card in financeViewModel.state.availableCards where !attachedKeys.contains(accountKey(type: .card, id: card.cardUniqueID)) {
            if let item = await makeUnattachedCardItem(card: card, dynamicsViewModel: dynamicsViewModel) {
                items.append(item)
            }
        }

        for credit in financeViewModel.state.availableCredits where !attachedKeys.contains(accountKey(type: .credit, id: credit.creditUniqueID)) {
            if let item = await makeUnattachedCreditItem(credit: credit, dynamicsViewModel: dynamicsViewModel) {
                items.append(item)
            }
        }

        for investment in financeViewModel.state.availableInvestments where !attachedKeys.contains(accountKey(type: .investment, id: investment.investmentUniqueID)) {
            if let item = await makeUnattachedInvestmentItem(investment: investment, dynamicsViewModel: dynamicsViewModel) {
                items.append(item)
            }
        }

        return FinanceOverviewLedgerBuilder.makePresentation(items: items)
    }

    private func sortedAccounts(
        _ accounts: [FinanceAccount]
    ) -> [FinanceAccount] {
        accounts.sorted { lhs, rhs in
            let lhsName = financeViewModel.getAccountInfo(account: lhs)?.name ?? lhs.accountID
            let rhsName = financeViewModel.getAccountInfo(account: rhs)?.name ?? rhs.accountID
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    private func sortedCoreAccounts(_ accounts: [Account]) -> [Account] {
        accounts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func makeLedgerItem(
        account: FinanceAccount,
        groupID: String,
        groupName: String,
        groupColorHex: String?,
        cardsByID: [String: Card],
        creditsByID: [String: Credit],
        investmentsByID: [String: Investment],
        dynamicsViewModel: FinanceDynamicsViewModel
    ) async -> FinanceOverviewLedgerSourceItem? {
        guard let info = financeViewModel.getAccountInfo(account: account) else { return nil }
        guard let signedValue = FinanceNetWorthSignedAmount.signedValue(
            for: account,
            cardsByID: cardsByID,
            creditsByID: creditsByID,
            investmentsByID: investmentsByID
        ) else { return nil }

        let convertedAmount = await dynamicsViewModel.convertAmount(
            value: signedValue,
            from: info.currency,
            to: financeViewModel.state.displayCurrency
        )
        guard let normalized = FinanceOverviewLedgerStyle.normalizeAmount(
            convertedAmount,
            defaultSide: .debit
        ) else { return nil }

        let customIconName: String?
        let customIconColor: String?
        switch account.accountType {
        case .card:
            let card = cardsByID[account.accountID]
            customIconName = card?.customIconName
            customIconColor = card?.customIconColor
        case .credit:
            let credit = creditsByID[account.accountID]
            customIconName = credit?.customIconName
            customIconColor = credit?.customIconColor
        case .investment:
            let investment = investmentsByID[account.accountID]
            customIconName = investment?.customIconName
            customIconColor = investment?.customIconColor
        }

        return FinanceOverviewLedgerSourceItem(
            groupID: groupID,
            groupName: groupName,
            groupColorHex: groupColorHex,
            accountID: account.accountID,
            accountName: info.name,
            accountIcon: info.icon,
            customIconName: customIconName,
            customIconColor: customIconColor,
            amount: normalized.amount,
            side: normalized.side
        )
    }

    /// Ledger-строка для счёта нового ядра. Signed-сумма — тем же `accountsTotalsService`, что и
    /// per-group суммы Динамики (единый источник, Фаза 1.5): >0 → debit (актив), <0 → credit (пассив).
    private func makeCoreLedgerItem(
        account: Account,
        groupID: String,
        groupName: String,
        groupColorHex: String?
    ) async -> FinanceOverviewLedgerSourceItem? {
        let signedConverted = NSDecimalNumber(
            decimal: await financeViewModel.accountsTotalsService.total(
                for: [account],
                on: Date(),
                in: financeViewModel.state.displayCurrency
            )
        ).doubleValue
        guard let normalized = FinanceOverviewLedgerStyle.normalizeAmount(
            signedConverted,
            defaultSide: .debit
        ) else { return nil }

        return FinanceOverviewLedgerSourceItem(
            groupID: groupID,
            groupName: groupName,
            groupColorHex: groupColorHex,
            accountID: account.id.uuidString,
            accountName: account.name,
            accountIcon: account.kind.fallbackIconName,
            customIconName: nil,
            customIconColor: nil,
            amount: normalized.amount,
            side: normalized.side
        )
    }

    private func makeUnattachedCardItem(
        card: Card,
        dynamicsViewModel: FinanceDynamicsViewModel
    ) async -> FinanceOverviewLedgerSourceItem? {
        guard let rawAmount = FinanceNetWorthSignedAmount.signedValue(for: card) else { return nil }

        let convertedAmount = await dynamicsViewModel.convertAmount(
            value: rawAmount,
            from: card.currency,
            to: financeViewModel.state.displayCurrency
        )
        guard let normalized = FinanceOverviewLedgerStyle.normalizeAmount(
            convertedAmount,
            defaultSide: .debit
        ) else { return nil }

        return FinanceOverviewLedgerSourceItem(
            groupID: "ungrouped-\(normalized.side.rawValue)",
            groupName: FinancesL10n.tr("finances.overview.ungrouped", locale: localizationLocale),
            groupColorHex: nil,
            accountID: card.cardUniqueID,
            accountName: card.name,
            accountIcon: card.resolvedIconName,
            customIconName: card.customIconName,
            customIconColor: card.customIconColor,
            amount: normalized.amount,
            side: normalized.side
        )
    }

    private func makeUnattachedCreditItem(
        credit: Credit,
        dynamicsViewModel: FinanceDynamicsViewModel
    ) async -> FinanceOverviewLedgerSourceItem? {
        guard let rawAmount = FinanceNetWorthSignedAmount.signedValue(for: credit) else { return nil }

        let convertedAmount = await dynamicsViewModel.convertAmount(
            value: rawAmount,
            from: credit.currency,
            to: financeViewModel.state.displayCurrency
        )
        guard let normalized = FinanceOverviewLedgerStyle.normalizeAmount(
            convertedAmount,
            defaultSide: .debit
        ) else { return nil }

        return FinanceOverviewLedgerSourceItem(
            groupID: "ungrouped-\(normalized.side.rawValue)",
            groupName: FinancesL10n.tr("finances.overview.ungrouped", locale: localizationLocale),
            groupColorHex: nil,
            accountID: credit.creditUniqueID,
            accountName: credit.name,
            accountIcon: credit.resolvedIconName,
            customIconName: credit.customIconName,
            customIconColor: credit.customIconColor,
            amount: normalized.amount,
            side: normalized.side
        )
    }

    private func makeUnattachedInvestmentItem(
        investment: Investment,
        dynamicsViewModel: FinanceDynamicsViewModel
    ) async -> FinanceOverviewLedgerSourceItem? {
        guard let rawAmount = FinanceNetWorthSignedAmount.signedValue(for: investment) else { return nil }

        let convertedAmount = await dynamicsViewModel.convertAmount(
            value: rawAmount,
            from: resolvedInvestmentCurrency(investment),
            to: financeViewModel.state.displayCurrency
        )
        guard let normalized = FinanceOverviewLedgerStyle.normalizeAmount(
            convertedAmount,
            defaultSide: .debit
        ) else { return nil }

        return FinanceOverviewLedgerSourceItem(
            groupID: "ungrouped-\(normalized.side.rawValue)",
            groupName: FinancesL10n.tr("finances.overview.ungrouped", locale: localizationLocale),
            groupColorHex: nil,
            accountID: investment.investmentUniqueID,
            accountName: financeViewModel.investmentDisplayName(investment),
            accountIcon: investment.resolvedIconName,
            customIconName: investment.customIconName,
            customIconColor: investment.customIconColor,
            amount: normalized.amount,
            side: normalized.side
        )
    }

    private func resolvedInvestmentCurrency(_ investment: Investment) -> String {
        let normalizedCurrency = investment.currency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !normalizedCurrency.isEmpty {
            return normalizedCurrency
        }

        let marketCurrency = investment.marketCurrency?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return (marketCurrency?.isEmpty == false ? marketCurrency : nil) ?? "USD"
    }

    private func accountKey(type: FinanceAccountType, id: String) -> String {
        "\(type.rawValue):\(id)"
    }

    private func saldoHero(
        presentation: FinanceOverviewLedgerPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(L("finances.overview.chart.saldo"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .textCase(.uppercase)

                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary.opacity(0.9))
                            .accessibilityLabel(
                                FinancesL10n.format(
                                    "finances.overview.saldo.accessibility_format",
                                    locale: localizationLocale,
                                    financeViewModel.state.displayCurrency.uppercased()
                                )
                            )
                    }

                    Text(signedAmount(presentation.saldo))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(saldoColor(for: presentation.saldo))
                        .minimumScaleFactor(0.78)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.05),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
        )
    }

    /// [Гейт 5c.7.6.1] Заменяет две независимые карточки Credit/Debit (`compactSideCard`, снесена —
    /// каждая со своей шкалой до `maxSideTotal`, что искажало пропорцию между сторонами) на ОДНУ
    /// полосу: сегменты «активы vs обязательства» суммируются в реальную ширину (пропорция = данным
    /// тотала, AC). Net не повторяем: общий баланс уже показан в hero сверху. Данные ТОЛЬКО из
    /// уже посчитанного `ledgerPresentation`
    /// (тот же единственный источник, что раньше питал две карточки, никакого второго расчёта).
    private func assetsLiabilitiesStackedBar(
        presentation: FinanceOverviewLedgerPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(alignment: .top, spacing: AppSpacing.l) {
                stackedBarLegend(title: presentation.debit.side.title, amount: presentation.debit.total, color: debitColor) {
                    openExpandedChart(side: .debit)
                }
                stackedBarLegend(title: presentation.credit.side.title, amount: presentation.credit.total, color: creditColor) {
                    openExpandedChart(side: .credit)
                }

                Spacer(minLength: 0)
            }

            GeometryReader { proxy in
                let widths = FinanceOverviewLedgerStyle.stackedSegmentWidths(
                    debitTotal: presentation.debit.total,
                    creditTotal: presentation.credit.total,
                    availableWidth: proxy.size.width,
                    minimumSegmentWidth: AppSpacing.s
                )
                HStack(spacing: 0) {
                    if widths.debit > 0 {
                        Rectangle().fill(debitColor.opacity(0.85)).frame(width: widths.debit)
                    }
                    if widths.credit > 0 {
                        Rectangle().fill(creditColor.opacity(0.85)).frame(width: widths.credit)
                    }
                }
                .frame(height: AppSpacing.s)
                .clipShape(Capsule(style: .continuous))
                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.05)))
            }
            .frame(height: AppSpacing.s)
        }
        .frame(maxWidth: .infinity)
    }

    private func stackedBarLegend(
        title: String,
        amount: Double,
        color: Color,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Circle().fill(color).frame(width: AppSpacing.xs, height: AppSpacing.xs)
                    Text(title)
                        .font(.millioCallout)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Text(amountWithCurrency(amount))
                    .font(.millioHeadline)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private func sideToggleRow(
        presentation: FinanceOverviewLedgerPresentation
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            sideToggleCard(
                side: presentation.credit,
                color: creditColor,
                totalReference: presentation.maxSideTotal
            )
            sideToggleCard(
                side: presentation.debit,
                color: debitColor,
                totalReference: presentation.maxSideTotal
            )
        }
    }

    private func sideToggleCard(
        side: FinanceOverviewLedgerSidePresentation,
        color: Color,
        totalReference: Double
    ) -> some View {
        let isExpanded = expandedSheetSide == side.side

        return Button {
            expandedSheetSide = FinanceOverviewLedgerInteraction.toggledExpandedSide(
                current: expandedSheetSide,
                tapped: side.side
            )
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(side.side.title)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)

                        Text(amountWithCurrency(side.total))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }

                GeometryReader { proxy in
                    let barWidth = FinanceOverviewLedgerStyle.barWidth(
                        total: side.total,
                        reference: totalReference,
                        availableWidth: proxy.size.width,
                        minimumWidth: 28
                    )

                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 12)
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [color.opacity(0.95), color.opacity(0.52)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: barWidth, height: 12)
                    }
                }
                .frame(height: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isExpanded ? 0.09 : 0.06),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func sideColumns(
        presentation: FinanceOverviewLedgerPresentation,
        expandedGroupIDs: Binding<Set<String>>,
        groupLimit: Int?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            sideDisclosureSection(
                side: presentation.credit,
                expandedGroupIDs: expandedGroupIDs,
                groupLimit: groupLimit,
                color: creditColor
            )
            sideDisclosureSection(
                side: presentation.debit,
                expandedGroupIDs: expandedGroupIDs,
                groupLimit: groupLimit,
                color: debitColor
            )
        }
    }

    private func sideDisclosureSection(
        side: FinanceOverviewLedgerSidePresentation,
        expandedGroupIDs: Binding<Set<String>>,
        groupLimit: Int?,
        color: Color
    ) -> some View {
        let displayedGroups = Array(groupLimit.map { side.groups.prefix($0) } ?? side.groups[...])
        let hiddenCount = max(side.groups.count - displayedGroups.count, 0)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(side.side.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                    Text(amountWithCurrency(side.total))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
            }

            if displayedGroups.isEmpty {
                Text(FinancesL10n.tr("finances.overview.no_accounts", locale: localizationLocale))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                ForEach(displayedGroups) { group in
                    DisclosureGroup(
                        isExpanded: binding(for: group.id, expandedGroupIDs: expandedGroupIDs)
                    ) {
                        VStack(spacing: 8) {
                            ForEach(group.accounts) { account in
                                accountRow(account, color: color)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        groupRow(group, color: color)
                    }
                    .tint(AppColors.textPrimary)
                }

                if hiddenCount > 0 {
                    Text(hiddenGroupsText(hiddenCount))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
        )
    }

    private func expandedSideContent(
        side: FinanceOverviewLedgerSidePresentation,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if side.groups.isEmpty {
                Text(FinancesL10n.tr("finances.overview.no_accounts", locale: localizationLocale))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
            } else {
                VStack(spacing: 10) {
                    ForEach(side.groups) { group in
                        DisclosureGroup(
                            isExpanded: binding(for: group.id, expandedGroupIDs: $expandedDetailGroupIDs)
                        ) {
                            VStack(spacing: 8) {
                                ForEach(group.accounts) { account in
                                    compactAccountRow(account, color: color)
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            expandedGroupHeaderRow(group: group, color: color)
                        }
                        .tint(AppColors.textPrimary)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                                )
                        )
                    }
                }
            }
        }
    }

    private func expandedGroupHeaderRow(
        group: FinanceOverviewLedgerGroup,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(groupColor(for: group, fallback: color))
                .frame(width: 10, height: 10)

            Text(group.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(amountWithCurrency(group.total))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private func compactAccountRow(
        _ account: FinanceOverviewLedgerAccount,
        color: Color
    ) -> some View {
        HStack(spacing: 10) {
            AccountIconBadgeView(
                iconName: account.customIconName,
                iconColor: account.customIconColor,
                fallback: account.icon,
                size: 28
            )

            Text(account.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(amountWithCurrency(account.amount))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private var expandedSideHint: some View {
        Text(FinancesL10n.tr("finances.overview.expanded_hint", locale: localizationLocale))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
    }

    private func groupRow(_ group: FinanceOverviewLedgerGroup, color: Color) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(groupColor(for: group, fallback: color))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(group.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                Text(groupAccountsText(group.accounts.count))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: 8)

            Text(amountWithCurrency(group.total))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private func accountRow(_ account: FinanceOverviewLedgerAccount, color: Color) -> some View {
        HStack(spacing: 10) {
            AccountIconBadgeView(
                iconName: account.customIconName,
                iconColor: account.customIconColor,
                fallback: account.icon,
                size: 32
            )

            Text(account.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(amountWithCurrency(account.amount))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var helperNote: some View {
        FinancesHintsPanel(
            title: FinancesL10n.tr("finances.overview.hints.title", locale: localizationLocale),
            prefsKey: "finances.overview.ledger",
            items: [
                .init(
                    id: "ledger-sides",
                    kind: .info,
                    text: FinancesL10n.tr("finances.overview.hints.ledger_sides", locale: localizationLocale)
                )
            ],
            accentColor: Color.white.opacity(0.18)
        )
    }

    private var expandedSheet: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        if let ledgerPresentation {
                            saldoHero(presentation: ledgerPresentation)
                            sideToggleRow(presentation: ledgerPresentation)
                            if let expandedSheetSide {
                                expandedSideContent(
                                    side: ledgerPresentation.sidePresentation(for: expandedSheetSide),
                                    color: color(for: expandedSheetSide)
                                )
                            } else {
                                expandedSideHint
                            }
                            helperNote
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(FinancesL10n.tr("finances.overview.nav.title", locale: localizationLocale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showExpandedChart = false
                    }
                    label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.10))
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("cashflow.common.dismiss"))
                }
            }
        }
    }

    private func color(for side: FinanceOverviewLedgerSide) -> Color {
        switch side {
        case .debit:
            return debitColor
        case .credit:
            return creditColor
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            Text(L("finances.overview.chart.empty"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var blockedState: some View {
        ProChartUpsellView(
            titleKey: "finances.dynamics.pro.title",
            subtitleKey: nil,
            ctaKey: "finances.dynamics.pro.cta",
            size: .compact,
            onTapCTA: { router.push(.subscription) }
        )
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.04),
                        Color.white.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func binding(
        for groupID: String,
        expandedGroupIDs: Binding<Set<String>>
    ) -> Binding<Bool> {
        Binding(
            get: { expandedGroupIDs.wrappedValue.contains(groupID) },
            set: { isExpanded in
                if isExpanded {
                    expandedGroupIDs.wrappedValue.insert(groupID)
                } else {
                    expandedGroupIDs.wrappedValue.remove(groupID)
                }
            }
        )
    }

    private func amountWithCurrency(_ value: Double) -> String {
        FinanceAmountText.withCurrency(
            value: value,
            currencySymbol: currencySymbol,
            isHidden: financeViewModel.state.isAmountHidden
        )
    }

    private func signedAmount(_ value: Double) -> String {
        let amount = amountWithCurrency(abs(value))
        if financeViewModel.state.isAmountHidden {
            return amount
        }
        if value > 0.01 { return "+\(amount)" }
        if value < -0.01 { return "-\(amount)" }
        return amount
    }

    private var currencySymbol: String {
        switch financeViewModel.state.displayCurrency.uppercased() {
        case "RUB": return "₽"
        case "USD": return "$"
        case "EUR": return "€"
        default: return financeViewModel.state.displayCurrency.uppercased()
        }
    }

    private func saldoColor(for value: Double) -> Color {
        if value > 0.01 {
            return debitColor
        }
        if value < -0.01 {
            return creditColor
        }
        return AppColors.textSecondary
    }

    private func groupAccountsText(_ count: Int) -> String {
        let key = count == 1
            ? "finances.overview.group_accounts.one"
            : "finances.overview.group_accounts.other"
        return FinancesL10n.format(key, locale: localizationLocale, count)
    }

    private func hiddenGroupsText(_ count: Int) -> String {
        let key = count == 1
            ? "finances.overview.hidden_groups.one"
            : "finances.overview.hidden_groups.other"
        return FinancesL10n.format(key, locale: localizationLocale, count)
    }

    private func groupColor(for group: FinanceOverviewLedgerGroup, fallback: Color) -> Color {
        guard let colorHex = group.colorHex else { return fallback }
        return Color(hex: colorHex)
    }

    private var debitColor: Color {
        Color(red: 0.38, green: 0.86, blue: 0.69)
    }

    private var creditColor: Color {
        AppColors.error
    }
}

/// Компактная диаграмма состава общего баланса. Это только presentation consumer: финансовые
/// суммы приходят из того же `FinanceOverviewLedgerPresentation`, который питает legends и bar.
struct FinanceBalanceCompositionDonut: View {
    let presentation: FinanceOverviewLedgerPresentation

    private let lineWidth: CGFloat = 10
    private let debitColor = AppColors.incomeGradient.first ?? .green
    private let creditColor = AppColors.expenseGradient.first ?? .red

    private var composition: FinanceOverviewLedgerStyle.BalanceComposition {
        FinanceOverviewLedgerStyle.balanceComposition(
            debitTotal: presentation.debit.total,
            creditTotal: presentation.credit.total
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: lineWidth)

            if composition.hasData {
                Circle()
                    .trim(from: 0, to: composition.debitFraction)
                    .stroke(
                        debitColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                if composition.creditFraction > 0.000_001 {
                    Circle()
                        .trim(from: composition.debitFraction, to: 1)
                        .stroke(
                            creditColor,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                }
            }

            Circle()
                .fill(Color.black.opacity(0.22))
                .padding(lineWidth + 2)
        }
        .rotationEffect(.degrees(-90))
        .shadow(color: debitColor.opacity(0.18), radius: 5, x: -1, y: 2)
        .frame(width: 58, height: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard composition.hasData else {
            return "\(presentation.debit.side.title): 0%. \(presentation.credit.side.title): 0%."
        }
        let debitPercent = Int((composition.debitFraction * 100).rounded())
        let creditPercent = max(0, 100 - debitPercent)
        return "\(presentation.debit.side.title): \(debitPercent)%. \(presentation.credit.side.title): \(creditPercent)%."
    }
}
