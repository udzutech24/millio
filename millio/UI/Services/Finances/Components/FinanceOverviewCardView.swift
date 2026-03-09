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

    @ObservedObject var financeViewModel: FinanceViewModel
    let chrome: FinanceOverviewCardChrome

    @State private var dynamicsViewModel: FinanceDynamicsViewModel?
    @State private var isLoading: Bool = false
    @State private var showExpandedChart: Bool = false
    @State private var ledgerPresentation: FinanceOverviewLedgerPresentation?
    @State private var expandedSheetSide: FinanceOverviewLedgerSide?

    init(
        financeViewModel: FinanceViewModel,
        chrome: FinanceOverviewCardChrome = .standalone
    ) {
        self.financeViewModel = financeViewModel
        self.chrome = chrome
    }

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
                compactLedgerOverview(presentation: ledgerPresentation)
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

    private var expandButton: some View {
        Button {
            openExpandedChart(side: nil)
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
                    )
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "finances.overview.chart.full"))
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
        guard EntitlementPolicy.canUseFinanceCharts(isPro: appState.isPro) else { return }

        isLoading = true
        dynamicsViewModel.handle(.loadData)
        ledgerPresentation = await buildLedgerPresentation(with: dynamicsViewModel)
        isLoading = false
    }

    private var reloadToken: String {
        let groupPart = financeViewModel.state.groups.map {
            let accountPart = ($0.accounts ?? []).map {
                "\($0.accountTypeRaw)_\($0.accountID)_\($0.updatedAt.timeIntervalSince1970)"
            }
            .sorted()
            .joined(separator: "|")
            return "\($0.groupUniqueID)_\($0.updatedAt.timeIntervalSince1970)_\(accountPart)"
        }
        .joined(separator: "#")

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
            groupPart,
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

        let groups = financeViewModel.state.groups.sorted {
            if $0.order != $1.order {
                return $0.order < $1.order
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        for group in groups {
            for account in sortedAccounts(group.accounts ?? [], using: dynamicsViewModel) {
                if let item = await makeLedgerItem(
                    account: account,
                    groupID: group.groupUniqueID,
                    groupName: group.name,
                    groupColorHex: group.colorHex,
                    dynamicsViewModel: dynamicsViewModel
                ) {
                    items.append(item)
                    attachedKeys.insert(accountKey(type: account.accountType, id: account.accountID))
                }
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
        _ accounts: [FinanceAccount],
        using dynamicsViewModel: FinanceDynamicsViewModel
    ) -> [FinanceAccount] {
        accounts.sorted { lhs, rhs in
            let lhsName = dynamicsViewModel.getAccountInfoForDynamics(account: lhs)?.name ?? lhs.accountID
            let rhsName = dynamicsViewModel.getAccountInfoForDynamics(account: rhs)?.name ?? rhs.accountID
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    private func makeLedgerItem(
        account: FinanceAccount,
        groupID: String,
        groupName: String,
        groupColorHex: String?,
        dynamicsViewModel: FinanceDynamicsViewModel
    ) async -> FinanceOverviewLedgerSourceItem? {
        guard let info = dynamicsViewModel.getAccountInfoForDynamics(account: account) else {
            return nil
        }

        let convertedAmount = await dynamicsViewModel.convertAmount(
            value: info.amount,
            from: info.currency,
            to: financeViewModel.state.displayCurrency
        )
        guard convertedAmount > 0.01 else { return nil }

        return FinanceOverviewLedgerSourceItem(
            groupID: groupID,
            groupName: groupName,
            groupColorHex: groupColorHex,
            accountID: account.accountID,
            accountName: info.name,
            accountIcon: info.icon,
            amount: convertedAmount,
            side: side(for: account, using: dynamicsViewModel)
        )
    }

    private func makeUnattachedCardItem(
        card: Card,
        dynamicsViewModel: FinanceDynamicsViewModel
    ) async -> FinanceOverviewLedgerSourceItem? {
        guard card.archivedAt == nil else { return nil }

        let rawAmount: Double
        let side: FinanceOverviewLedgerSide
        if card.cardType == .credit, let limit = card.creditLimit {
            rawAmount = max(0, limit - card.balance)
            side = .credit
        } else {
            rawAmount = card.balance
            side = .debit
        }
        guard rawAmount > 0.01 else { return nil }

        let convertedAmount = await dynamicsViewModel.convertAmount(
            value: rawAmount,
            from: card.currency,
            to: financeViewModel.state.displayCurrency
        )
        guard convertedAmount > 0.01 else { return nil }

        return FinanceOverviewLedgerSourceItem(
            groupID: "ungrouped-\(side.rawValue)",
            groupName: "Без группы",
            groupColorHex: nil,
            accountID: card.cardUniqueID,
            accountName: card.name,
            accountIcon: card.cardType.icon,
            amount: convertedAmount,
            side: side
        )
    }

    private func makeUnattachedCreditItem(
        credit: Credit,
        dynamicsViewModel: FinanceDynamicsViewModel
    ) async -> FinanceOverviewLedgerSourceItem? {
        guard credit.archivedAt == nil else { return nil }
        guard credit.remainingAmount > 0.01 else { return nil }

        let convertedAmount = await dynamicsViewModel.convertAmount(
            value: credit.remainingAmount,
            from: credit.currency,
            to: financeViewModel.state.displayCurrency
        )
        guard convertedAmount > 0.01 else { return nil }

        return FinanceOverviewLedgerSourceItem(
            groupID: "ungrouped-credit",
            groupName: "Без группы",
            groupColorHex: nil,
            accountID: credit.creditUniqueID,
            accountName: credit.name,
            accountIcon: credit.creditType.icon,
            amount: convertedAmount,
            side: .credit
        )
    }

    private func makeUnattachedInvestmentItem(
        investment: Investment,
        dynamicsViewModel: FinanceDynamicsViewModel
    ) async -> FinanceOverviewLedgerSourceItem? {
        guard investment.archivedAt == nil else { return nil }
        guard investment.amount > 0.01 else { return nil }

        let convertedAmount = await dynamicsViewModel.convertAmount(
            value: investment.amount,
            from: resolvedInvestmentCurrency(investment),
            to: financeViewModel.state.displayCurrency
        )
        guard convertedAmount > 0.01 else { return nil }

        return FinanceOverviewLedgerSourceItem(
            groupID: "ungrouped-debit",
            groupName: "Без группы",
            groupColorHex: nil,
            accountID: investment.investmentUniqueID,
            accountName: investment.name,
            accountIcon: investment.category.icon,
            amount: convertedAmount,
            side: .debit
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

    private func side(
        for account: FinanceAccount,
        using dynamicsViewModel: FinanceDynamicsViewModel
    ) -> FinanceOverviewLedgerSide {
        switch account.accountType {
        case .credit:
            return .credit
        case .investment:
            return .debit
        case .card:
            if dynamicsViewModel.cardsCache[account.accountID]?.cardType == .credit {
                return .credit
            }
            return .debit
        }
    }

    private func saldoHero(
        presentation: FinanceOverviewLedgerPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "finances.overview.chart.saldo"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .textCase(.uppercase)

                    Text(signedAmount(presentation.saldo))
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(saldoColor(for: presentation.saldo))
                        .minimumScaleFactor(0.78)
                        .lineLimit(1)

                    Text("Разница между активами и обязательствами в \(financeViewModel.state.displayCurrency.uppercased()).")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 10) {
                    sideMetricPill(title: "Debit", value: amountWithCurrency(presentation.debit.total), color: debitColor)
                    sideMetricPill(title: "Credit", value: amountWithCurrency(presentation.credit.total), color: creditColor)
                }
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

    private func compactLedgerOverview(
        presentation: FinanceOverviewLedgerPresentation
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            bridgeChart(presentation: presentation)

            expandButton
                .padding(.top, -8)
                .padding(.trailing, 2)
        }
    }

    private func bridgeChart(
        presentation: FinanceOverviewLedgerPresentation
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                openExpandedChart(side: .debit)
            } label: {
                mirroredSideCard(
                    side: presentation.debit,
                    isTrailing: true,
                    color: debitColor,
                    totalReference: presentation.maxSideTotal
                )
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
                .overlay {
                    Circle()
                        .fill(saldoColor(for: presentation.saldo).opacity(0.22))
                        .frame(width: 10, height: 10)
                }

            Button {
                openExpandedChart(side: .credit)
            } label: {
                mirroredSideCard(
                    side: presentation.credit,
                    isTrailing: false,
                    color: creditColor,
                    totalReference: presentation.maxSideTotal
                )
            }
            .buttonStyle(.plain)
        }
        .frame(height: 82)
        .padding(.horizontal, 1)
    }

    private func sideToggleRow(
        presentation: FinanceOverviewLedgerPresentation
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            sideToggleCard(
                side: presentation.debit,
                color: debitColor,
                totalReference: presentation.maxSideTotal
            )
            sideToggleCard(
                side: presentation.credit,
                color: creditColor,
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
                        Text(FinanceOverviewLedgerStyle.countsText(groups: side.groups.count, accounts: side.accountCount))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
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

                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(FinanceOverviewLedgerStyle.disclosureText(isExpanded: isExpanded))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color)
                    Spacer()
                }
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
                            .stroke(isExpanded ? color.opacity(0.34) : Color.white.opacity(0.08), lineWidth: 0.9)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func mirroredSideCard(
        side: FinanceOverviewLedgerSidePresentation,
        isTrailing: Bool,
        color: Color,
        totalReference: Double
    ) -> some View {
        VStack(alignment: isTrailing ? .trailing : .leading, spacing: 9) {
            HStack(spacing: 8) {
                if !isTrailing {
                    sideGlyph(color: color, icon: side.side == .debit ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                }

                VStack(alignment: isTrailing ? .trailing : .leading, spacing: 2) {
                    Text(side.side.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.92))
                    Text(FinanceOverviewLedgerStyle.compactCountsText(groups: side.groups.count, accounts: side.accountCount))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isTrailing {
                    sideGlyph(color: color, icon: side.side == .debit ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                }
            }

            Text(amountWithCurrency(side.total))
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            GeometryReader { proxy in
                let barWidth = FinanceOverviewLedgerStyle.barWidth(
                    total: side.total,
                    reference: totalReference,
                    availableWidth: proxy.size.width,
                    minimumWidth: 20
                )

                ZStack(alignment: isTrailing ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 10)
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.92), color.opacity(0.48)],
                                startPoint: isTrailing ? .trailing : .leading,
                                endPoint: isTrailing ? .leading : .trailing
                            )
                        )
                        .frame(width: barWidth, height: 10)
                }
            }
            .frame(height: 10)
        }
        .frame(maxWidth: .infinity, alignment: isTrailing ? .trailing : .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.075),
                            Color.white.opacity(0.028)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(color.opacity(0.2), lineWidth: 0.8)
                )
        )
    }

    private func sideColumns(
        presentation: FinanceOverviewLedgerPresentation,
        expandedGroupIDs: Binding<Set<String>>,
        groupLimit: Int?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            sideDisclosureSection(
                side: presentation.debit,
                expandedGroupIDs: expandedGroupIDs,
                groupLimit: groupLimit,
                color: debitColor
            )
            sideDisclosureSection(
                side: presentation.credit,
                expandedGroupIDs: expandedGroupIDs,
                groupLimit: groupLimit,
                color: creditColor
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
                Text("Нет счетов")
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
                    Text(FinanceOverviewLedgerStyle.hiddenGroupsText(hiddenCount))
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(side.side.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(amountWithCurrency(side.total))
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(FinanceOverviewLedgerStyle.countsText(groups: side.groups.count, accounts: side.accountCount))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()
            }

            if side.groups.isEmpty {
                Text("Нет счетов")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
            } else {
                VStack(spacing: 12) {
                    ForEach(side.groups) { group in
                        expandedGroupCard(group: group, color: color)
                    }
                }
            }
        }
    }

    private func expandedGroupCard(
        group: FinanceOverviewLedgerGroup,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(groupColor(for: group, fallback: color).opacity(0.18))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Circle()
                            .fill(groupColor(for: group, fallback: color))
                            .frame(width: 10, height: 10)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                    Text("\(group.accounts.count) счетов")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer(minLength: 8)
            }

            Text(amountWithCurrency(group.total))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            VStack(spacing: 10) {
                ForEach(group.accounts) { account in
                    accountRow(account, color: color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.07),
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

    private var expandedSideHint: some View {
        Text("Нажми на Debit или Credit выше, чтобы раскрыть только одну сторону и пролистывать группы по горизонтали.")
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
                Text("\(group.accounts.count) счетов")
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
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.16))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: account.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }

            Text(account.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 8)

            Text(amountWithCurrency(account.amount))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.48))

            Text("Дебит и кредит здесь показаны как левая и правая стороны раскладки. Кредитные карты и кредиты попадают справа как обязательства.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.035))
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
            .navigationTitle("Бухгалтерская раскладка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "cashflow.common.dismiss")) {
                        showExpandedChart = false
                    }
                    .foregroundStyle(AppColors.textPrimary)
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
            Text(String(localized: "finances.overview.chart.empty"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var blockedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            Text(String(localized: "finances.dynamics.pro.title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            Text(String(localized: "finances.dynamics.pro.subtitle"))
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
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

    private func badge(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func sideMetricPill(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func sideGlyph(color: Color, icon: String) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 24, height: 24)
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private func amountWithCurrency(_ value: Double) -> String {
        "\(formatAmount(value)) \(currencySymbol)"
    }

    private func signedAmount(_ value: Double) -> String {
        let amount = amountWithCurrency(abs(value))
        if value > 0.01 { return "+\(amount)" }
        if value < -0.01 { return "-\(amount)" }
        return amount
    }

    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
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
