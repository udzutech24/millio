import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class FinanceBalanceAuditViewModel: ObservableObject {
    @Published private(set) var selectedDate: Date
    @Published var searchText: String = ""
    @Published var isReviewMode: Bool = false
    @Published private(set) var focusedAccountKey: String?
    @Published private(set) var rows: [FinanceBalanceAuditRow] = []
    @Published private(set) var groupTotals: [FinanceBalanceAuditGroupTotal] = []
    @Published private(set) var currencyTotals: [FinanceBalanceAuditCurrencyTotal] = []

    let availableCurrencies: [String]

    private let modelContext: ModelContext
    private let financeViewModel: FinanceViewModel
    private let store: FinanceBalanceAuditStoreProtocol
    private let dynamicsViewModel: FinanceDynamicsViewModel
    private var reloadTask: Task<Void, Never>?

    init(
        modelContext: ModelContext,
        financeViewModel: FinanceViewModel,
        store: FinanceBalanceAuditStoreProtocol = FinanceBalanceAuditStore(),
        selectedDate: Date = Date()
    ) {
        self.modelContext = modelContext
        self.financeViewModel = financeViewModel
        self.store = store
        self.dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            currencyService: financeViewModel.currencyService
        )
        self.selectedDate = selectedDate
        self.availableCurrencies = CurrencySelectionSupport.allCurrencyCodesForPicker
        reload()
    }

    deinit {
        MainActor.assumeIsolated {
            reloadTask?.cancel()
        }
    }

    var filteredRows: [FinanceBalanceAuditRow] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rows }
        return rows.filter { row in
            row.title.localizedCaseInsensitiveContains(trimmed)
                || row.groupName.localizedCaseInsensitiveContains(trimmed)
                || row.currencyCode.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func setDate(_ date: Date) {
        selectedDate = date
        reload()
    }

    func setValue(_ value: Double, for row: FinanceBalanceAuditRow) {
        guard value.isFinite, !value.isNaN else { return }
        store.setValue(
            value,
            for: row.id,
            day: FinanceBalanceDayKey(date: selectedDate),
            defaultCurrency: row.currencyCode,
            defaultTitle: row.title,
            defaultGroupName: row.groupName,
            accountTypeRaw: row.accountTypeRaw,
            effectSign: row.effectSign,
            isUnknown: row.isUnknown
        )
        if let index = rows.firstIndex(where: { $0.id == row.id }) {
            let existing = rows[index]
            rows[index] = FinanceBalanceAuditRow(
                id: existing.id,
                accountTypeRaw: existing.accountTypeRaw,
                accountID: existing.accountID,
                title: existing.title,
                groupName: existing.groupName,
                currencyCode: existing.currencyCode,
                value: value,
                effectSign: existing.effectSign,
                hasDateSnapshot: true,
                isUnknown: existing.isUnknown,
                sourceOrder: existing.sourceOrder
            )
            recomputeAggregates()
        } else {
            reload()
        }
    }

    func setCurrency(_ currencyCode: String, for row: FinanceBalanceAuditRow) {
        let normalized = normalizedCurrency(currencyCode)
        guard !normalized.isEmpty else { return }
        store.setCurrency(normalized, for: row.id)
        reload()
    }

    func deleteValue(for row: FinanceBalanceAuditRow) {
        store.deleteValue(for: row.id, day: FinanceBalanceDayKey(date: selectedDate))
        reload()
    }

    func deleteAccountForever(_ row: FinanceBalanceAuditRow) {
        store.deleteAccountEverywhere(row.id)
        hardDeleteUnderlyingAccount(accountTypeRaw: row.accountTypeRaw, accountID: row.accountID)
        reload()
    }

    func beginReview() {
        isReviewMode = true
        focusedAccountKey = filteredRows.first?.id
    }

    func stopReview() {
        isReviewMode = false
        focusedAccountKey = nil
    }

    func focusNext() {
        let list = filteredRows
        guard !list.isEmpty else { return }
        guard let focusedAccountKey,
              let idx = list.firstIndex(where: { $0.id == focusedAccountKey }) else {
            self.focusedAccountKey = list.first?.id
            return
        }
        let next = min(idx + 1, list.count - 1)
        self.focusedAccountKey = list[next].id
    }

    func focusPrevious() {
        let list = filteredRows
        guard !list.isEmpty else { return }
        guard let focusedAccountKey,
              let idx = list.firstIndex(where: { $0.id == focusedAccountKey }) else {
            self.focusedAccountKey = list.first?.id
            return
        }
        let prev = max(idx - 1, 0)
        self.focusedAccountKey = list[prev].id
    }

    func isFocused(_ row: FinanceBalanceAuditRow) -> Bool {
        focusedAccountKey == row.id
    }

    func reload() {
        reloadTask?.cancel()
        let dateSnapshot = selectedDate
        reloadTask = Task { [weak self] in
            await self?.reloadAsync(for: dateSnapshot)
        }
    }

    private func reloadAsync(for date: Date) async {
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dayKey = FinanceBalanceDayKey(date: date)
        let daySnapshot = store.daySnapshot(for: dayKey)
        let liveAccounts = liveAccountsLookup()
        let historicalValues = await historicalValuesByAccountKey(
            liveAccounts: liveAccounts,
            on: date
        )

        if Task.isCancelled { return }
        guard date == selectedDate else { return }

        var composed: [FinanceBalanceAuditRow] = []

        let liveRows = liveAccounts.values.sorted { lhs, rhs in
            if lhs.title == rhs.title { return lhs.id < rhs.id }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        for live in liveRows {
            let snapshotValue = daySnapshot[live.id]
            let displayedValue = snapshotValue?.value ?? historicalValues[live.id] ?? live.value
            let row = FinanceBalanceAuditRow(
                id: live.id,
                accountTypeRaw: live.accountTypeRaw,
                accountID: live.accountID,
                title: resolvedTitle(snapshot: snapshotValue?.title ?? "", live: live),
                groupName: resolvedGroupName(snapshot: snapshotValue?.groupName ?? "", live: live),
                currencyCode: normalizedCurrency(store.currency(for: live.id) ?? live.currencyCode),
                value: displayedValue,
                effectSign: live.effectSign,
                hasDateSnapshot: snapshotValue != nil,
                isUnknown: false,
                sourceOrder: 0
            )
            composed.append(row)
        }

        // Исторические snapshot-строки для уже удаленных/неизвестных счетов.
        let unknownSnapshotKeys = daySnapshot.keys
            .filter { liveAccounts[$0] == nil }
            .sorted { lhs, rhs in
                let leftTitle = daySnapshot[lhs]?.title ?? ""
                let rightTitle = daySnapshot[rhs]?.title ?? ""
                if leftTitle == rightTitle { return lhs < rhs }
                return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
            }

        for key in unknownSnapshotKeys {
            guard let snapshotValue = daySnapshot[key] else { continue }

            let accountTypeRaw: String
            let accountID: String
            if let parts = key.split(separator: ":", maxSplits: 1).map(String.init) as [String]?, parts.count == 2 {
                accountTypeRaw = parts[0]
                accountID = parts[1]
            } else {
                accountTypeRaw = snapshotValue.accountTypeRaw
                accountID = key
            }

            let row = FinanceBalanceAuditRow(
                id: key,
                accountTypeRaw: accountTypeRaw,
                accountID: accountID,
                title: resolvedTitle(snapshot: snapshotValue.title, live: nil),
                groupName: resolvedGroupName(snapshot: snapshotValue.groupName, live: nil),
                currencyCode: normalizedCurrency(store.currency(for: key) ?? snapshotValue.currencyCode),
                value: snapshotValue.value,
                effectSign: snapshotValue.effectSign,
                hasDateSnapshot: true,
                isUnknown: true,
                sourceOrder: 1
            )
            composed.append(row)
        }

        rows = composed
        recomputeAggregates()

        if isReviewMode {
            if let focusedAccountKey, filteredRows.contains(where: { $0.id == focusedAccountKey }) {
                self.focusedAccountKey = focusedAccountKey
            } else {
                self.focusedAccountKey = filteredRows.first?.id
            }
        }
    }

    private func historicalValuesByAccountKey(
        liveAccounts: [String: FinanceBalanceLiveAccount],
        on date: Date
    ) async -> [String: Double] {
        guard !liveAccounts.isEmpty else { return [:] }

        dynamicsViewModel.handle(.loadData)

        let endOfDay = Calendar.current.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: date
        ) ?? date

        let accounts = (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []
        var values: [String: Double] = [:]

        for account in accounts {
            let key = makeAccountKey(typeRaw: account.accountTypeRaw, accountID: account.accountID)
            guard let live = liveAccounts[key] else { continue }

            dynamicsViewModel.state.displayCurrency = live.currencyCode
            let accountCardIDs = account.accountType == .card ? Set([account.accountID]) : Set<String>()
            let value = await dynamicsViewModel.calculateBalanceAtDate(
                accounts: [account],
                date: endOfDay,
                accountCardIDs: accountCardIDs,
                debtAsNegative: false,
                includeInitialBeforeCreation: false
            )
            values[key] = value
        }

        return values
    }

    private func recomputeAggregates() {
        let currentRows = filteredRows

        let grouped = Dictionary(grouping: currentRows, by: { $0.groupName })
        groupTotals = grouped
            .map { groupName, items in
                FinanceBalanceAuditGroupTotal(
                    id: groupName,
                    groupName: groupName,
                    total: items.reduce(0) { $0 + $1.normalizedValue }
                )
            }
            .sorted { $0.groupName.localizedCaseInsensitiveCompare($1.groupName) == .orderedAscending }

        let byCurrency = Dictionary(grouping: currentRows, by: { $0.currencyCode })
        currencyTotals = byCurrency
            .map { currencyCode, items in
                FinanceBalanceAuditCurrencyTotal(
                    id: currencyCode,
                    currencyCode: currencyCode,
                    total: items.reduce(0) { $0 + $1.normalizedValue }
                )
            }
            .sorted { $0.currencyCode.localizedCaseInsensitiveCompare($1.currencyCode) == .orderedAscending }
    }

    private func liveAccountsLookup() -> [String: FinanceBalanceLiveAccount] {
        var cardGroupByID: [String: String] = [:]
        var creditGroupByID: [String: String] = [:]
        var investmentGroupByID: [String: String] = [:]

        for group in financeViewModel.state.groups {
            guard let accounts = group.accounts else { continue }
            for account in accounts {
                switch account.accountType {
                case .card:
                    cardGroupByID[account.accountID] = nonEmptyText(group.name) ?? FinancesL10n.tr("finances.audit.fallback.ungrouped")
                case .credit:
                    creditGroupByID[account.accountID] = nonEmptyText(group.name) ?? FinancesL10n.tr("finances.audit.fallback.ungrouped")
                case .investment:
                    investmentGroupByID[account.accountID] = nonEmptyText(group.name) ?? FinancesL10n.tr("finances.audit.fallback.ungrouped")
                }
            }
        }

        var result: [String: FinanceBalanceLiveAccount] = [:]

        for card in financeViewModel.state.availableCards {
            let title = resolvedCardTitle(card)
            let key = makeAccountKey(typeRaw: FinanceAccountType.card.rawValue, accountID: card.cardUniqueID)
            let effectSign = card.cardType == .credit ? -1 : 1
            result[key] = FinanceBalanceLiveAccount(
                id: key,
                accountTypeRaw: FinanceAccountType.card.rawValue,
                accountID: card.cardUniqueID,
                title: title,
                bankName: card.bank.displayName,
                groupName: cardGroupByID[card.cardUniqueID] ?? FinancesL10n.tr("finances.audit.fallback.ungrouped"),
                currencyCode: normalizedCurrency(card.currency),
                value: card.balance,
                effectSign: effectSign
            )
        }

        for credit in financeViewModel.state.availableCredits {
            let key = makeAccountKey(typeRaw: FinanceAccountType.credit.rawValue, accountID: credit.creditUniqueID)
            result[key] = FinanceBalanceLiveAccount(
                id: key,
                accountTypeRaw: FinanceAccountType.credit.rawValue,
                accountID: credit.creditUniqueID,
                title: nonEmptyText(credit.name) ?? nonEmptyText(credit.bank.displayName) ?? FinancesL10n.tr("finances.audit.fallback.unknown_account"),
                bankName: credit.bank.displayName,
                groupName: creditGroupByID[credit.creditUniqueID] ?? FinancesL10n.tr("finances.audit.fallback.ungrouped"),
                currencyCode: normalizedCurrency(credit.currency),
                value: credit.remainingAmount,
                effectSign: -1
            )
        }

        for investment in financeViewModel.state.availableInvestments {
            let key = makeAccountKey(typeRaw: FinanceAccountType.investment.rawValue, accountID: investment.investmentUniqueID)
            result[key] = FinanceBalanceLiveAccount(
                id: key,
                accountTypeRaw: FinanceAccountType.investment.rawValue,
                accountID: investment.investmentUniqueID,
                title: nonEmptyText(investment.name) ?? FinancesL10n.tr("finances.audit.fallback.unknown_account"),
                bankName: "",
                groupName: investmentGroupByID[investment.investmentUniqueID] ?? FinancesL10n.tr("finances.audit.fallback.ungrouped"),
                currencyCode: normalizedCurrency(investment.currency),
                value: investment.amount,
                effectSign: investment.investmentType == .negative ? -1 : 1
            )
        }

        return result
    }

    private func hardDeleteUnderlyingAccount(accountTypeRaw: String, accountID: String) {
        let type = FinanceAccountType(rawValue: accountTypeRaw)
        let linkedAccounts = ((try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []).filter {
            $0.accountID == accountID && $0.accountTypeRaw == accountTypeRaw
        }
        for account in linkedAccounts {
            modelContext.delete(account)
        }

        switch type {
        case .card:
            let cards = ((try? modelContext.fetch(FetchDescriptor<Card>())) ?? []).filter { $0.cardUniqueID == accountID }
            for card in cards { modelContext.delete(card) }
        case .credit:
            let credits = ((try? modelContext.fetch(FetchDescriptor<Credit>())) ?? []).filter { $0.creditUniqueID == accountID }
            for credit in credits { modelContext.delete(credit) }
        case .investment:
            let investments = ((try? modelContext.fetch(FetchDescriptor<Investment>())) ?? []).filter { $0.investmentUniqueID == accountID }
            for investment in investments { modelContext.delete(investment) }
        case .none:
            break
        }

        do {
            try modelContext.save()
            financeViewModel.handle(.loadAccounts)
            financeViewModel.handle(.loadGroups)
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to hard delete account: \(error.localizedDescription)")
        }
    }

    private func makeAccountKey(typeRaw: String, accountID: String) -> String {
        "\(typeRaw):\(accountID)"
    }

    private func resolvedCardTitle(_ card: Card) -> String {
        if let title = nonEmptyText(card.name) {
            return title
        }
        if let bank = nonEmptyText(card.bank.displayName) {
            return bank
        }
        return FinancesL10n.tr("finances.audit.fallback.unknown_account")
    }

    private func resolvedTitle(snapshot: String, live: FinanceBalanceLiveAccount?) -> String {
        if let value = nonEmptyText(snapshot) {
            return value
        }
        if let live {
            if let value = nonEmptyText(live.title) {
                return value
            }
            if let bank = nonEmptyText(live.bankName) {
                return bank
            }
        }
        return FinancesL10n.tr("finances.audit.fallback.unknown_account")
    }

    private func resolvedGroupName(snapshot: String, live: FinanceBalanceLiveAccount?) -> String {
        if let value = nonEmptyText(snapshot) {
            return value
        }
        if let live, let value = nonEmptyText(live.groupName) {
            return value
        }
        return FinancesL10n.tr("finances.audit.fallback.ungrouped")
    }

    private func normalizedCurrency(_ code: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? "RUB" : normalized
    }

    private func nonEmptyText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
