//
//  AccountBalanceSnapshotService.swift
//  millio
//
//  Фоновый сервис: один раз в сутки сохраняет снапшоты баланса
//  по каждому счёту в AccountBalanceHistoryStore.
//  Вызывается из FinanceViewModel.computeDashboardSparkline() через Task {}.
//

import Foundation
import SwiftData

@MainActor
final class AccountBalanceSnapshotService {

    private let modelContext: ModelContext
    private let totalsService: FinanceTotalsService
    private let currencyService: CurrencyRateServiceProtocol
    private let baseCurrencyProvider: () -> String

    init(
        modelContext: ModelContext,
        totalsService: FinanceTotalsService,
        currencyService: CurrencyRateServiceProtocol,
        baseCurrencyProvider: @escaping () -> String
    ) {
        self.modelContext = modelContext
        self.totalsService = totalsService
        self.currencyService = currencyService
        self.baseCurrencyProvider = baseCurrencyProvider
    }

    // MARK: - Public

    /// Закрывает прошедшие дни в SwiftData daily snapshots.
    /// Старый JSON-store больше не пишет историю: он остаётся только источником миграции.
    func snapshotIfNeeded() async {
        let service = DailySnapshotClosingService(
            modelContext: modelContext,
            totalsService: totalsService,
            currencyService: currencyService,
            baseCurrencyProvider: baseCurrencyProvider
        )
        await service.closeAllPendingDays()
    }
}
