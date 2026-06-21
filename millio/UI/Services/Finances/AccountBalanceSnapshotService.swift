//
//  AccountBalanceSnapshotService.swift
//  millio
//
//  Фоновый сервис: один раз в сутки сохраняет снапшоты баланса
//  по каждому счёту в AccountBalanceHistoryStore.
//  Вызывается из FinanceViewModel.computeDashboardSparkline() через Task {}.
//

import Foundation

@MainActor
final class AccountBalanceSnapshotService {

    private let totalsService: FinanceTotalsService
    private let groupsProvider: () -> [FinanceGroup]

    init(totalsService: FinanceTotalsService, groupsProvider: @escaping () -> [FinanceGroup]) {
        self.totalsService = totalsService
        self.groupsProvider = groupsProvider
    }

    // MARK: - Public

    /// Делает снапшоты всех счетов, если сегодня ещё не делали.
    /// Также запускает cleanup осиротевших UUID.
    func snapshotIfNeeded() async {
        let today = AccountBalanceHistoryStore.dayKey(for: Date())
        guard lastSnapshotDay != today else { return }

        let balances = await totalsService.calculateAllAccountBalances()
        for (accountID, balance) in balances {
            AccountBalanceHistoryStore.save(
                accountID: accountID,
                amount: balance.value,
                currency: balance.currency
            )
        }

        lastSnapshotDay = today

        // Удаляем историю удалённых счетов
        let activeIDs = Set(balances.keys)
        AccountBalanceHistoryStore.cleanup(keepingIDs: activeIDs)
    }

    // MARK: - Private

    private var lastSnapshotDay: String {
        get { UserDefaults.standard.string(forKey: "account_snapshot_last_day") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "account_snapshot_last_day") }
    }
}
