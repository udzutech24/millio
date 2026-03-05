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

    init(
        modelContext: ModelContext,
        financeViewModel: FinanceViewModel,
        store: FinanceBalanceAuditStoreProtocol = FinanceBalanceAuditStore(),
        selectedDate: Date = Date()
    ) {
        self.modelContext = modelContext
        self.financeViewModel = financeViewModel
        self.store = store
        self.selectedDate = selectedDate
        self.availableCurrencies = CurrencySelectionSupport.allCurrencyCodesForPicker
        reload()
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
        reload()
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
        let dayKey = FinanceBalanceDayKey(date: selectedDate)
        let daySnapshot = store.daySnapshot(for: dayKey)
        let liveAccounts = liveAccountsLookup()

        var composed: [FinanceBalanceAuditRow] = []

        let sortedSnapshot = daySnapshot.keys.sorted { lhs, rhs in
            let leftTitle = daySnapshot[lhs]?.title ?? ""
            let rightTitle = daySnapshot[rhs]?.title ?? ""
            if leftTitle == rightTitle { return lhs < rhs }
            return leftTitle.localizedCaseInsensitiveCompare(rightTitle) == .orderedAscending
        }

        for key in sortedSnapshot {
            guard let snapshotValue = daySnapshot[key] else { continue }
            let live = liveAccounts[key]
            let accountTypeRaw: String
            let accountID: String
            if let parts = key.split(separator: ":", maxSplits: 1).map(String.init) as [String]?, parts.count == 2 {
                accountTypeRaw = parts[0]
                accountID = parts[1]
            } else {
                accountTypeRaw = snapshotValue.accountTypeRaw
                accountID = key
            }

            let title = resolvedTitle(snapshot: snapshotValue.title, live: live)
            let groupName = resolvedGroupName(snapshot: snapshotValue.groupName, live: live)
            let currency = normalizedCurrency(
                store.currency(for: key)
                    ?? live?.currencyCode
                    ?? snapshotValue.currencyCode
            )

            let row = FinanceBalanceAuditRow(
                id: key,
                accountTypeRaw: accountTypeRaw,
                accountID: accountID,
                title: title,
                groupName: groupName,
                currencyCode: currency,
                value: snapshotValue.value,
                effectSign: live?.effectSign ?? snapshotValue.effectSign,
                hasDateSnapshot: true,
                isUnknown: live == nil,
                sourceOrder: 0
            )
            composed.append(row)
        }

        let knownKeys = Set(composed.map(\.id))
        let liveCardsMissingFromSnapshot = liveAccounts.values
            .filter { $0.accountTypeRaw == FinanceAccountType.card.rawValue && !knownKeys.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.title == rhs.title { return lhs.id < rhs.id }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        for card in liveCardsMissingFromSnapshot {
            let row = FinanceBalanceAuditRow(
                id: card.id,
                accountTypeRaw: card.accountTypeRaw,
                accountID: card.accountID,
                title: resolvedTitle(snapshot: "", live: card),
                groupName: resolvedGroupName(snapshot: "", live: card),
                currencyCode: normalizedCurrency(store.currency(for: card.id) ?? card.currencyCode),
                value: card.value,
                effectSign: card.effectSign,
                hasDateSnapshot: false,
                isUnknown: false,
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
                    cardGroupByID[account.accountID] = nonEmptyText(group.name) ?? "Без группы"
                case .credit:
                    creditGroupByID[account.accountID] = nonEmptyText(group.name) ?? "Без группы"
                case .investment:
                    investmentGroupByID[account.accountID] = nonEmptyText(group.name) ?? "Без группы"
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
                groupName: cardGroupByID[card.cardUniqueID] ?? "Без группы",
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
                title: nonEmptyText(credit.name) ?? nonEmptyText(credit.bank.displayName) ?? "Неизвестный счёт",
                bankName: credit.bank.displayName,
                groupName: creditGroupByID[credit.creditUniqueID] ?? "Без группы",
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
                title: nonEmptyText(investment.name) ?? "Неизвестный счёт",
                bankName: "",
                groupName: investmentGroupByID[investment.investmentUniqueID] ?? "Без группы",
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
        return "Неизвестный счёт"
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
        return "Неизвестный счёт"
    }

    private func resolvedGroupName(snapshot: String, live: FinanceBalanceLiveAccount?) -> String {
        if let value = nonEmptyText(snapshot) {
            return value
        }
        if let live, let value = nonEmptyText(live.groupName) {
            return value
        }
        return "Без группы"
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
