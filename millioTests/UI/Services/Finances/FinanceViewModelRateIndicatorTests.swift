//
//  FinanceViewModelRateIndicatorTests.swift
//  millioTests
//
//  Регрессия на баг с устройства (2026-08-24): на экране «Счета» при каждом холодном старте и при
//  каждом фоновом обновлении курсов вспыхивал ProgressView в шапке (`state.isLoadingRates`), и
//  экран дёргался. Индикатор допустим ТОЛЬКО когда показать нечего вообще — снимка курсов нет.
//

import Foundation
import Testing
import SwiftData
@testable import millio

/// Мок курсов с управляемым снимком: моделирует «кэш с диска есть / кэша нет».
@MainActor
final class SnapshotAwareMockRateService: CurrencyRateServiceProtocol {
    var snapshot: RateSnapshot?
    private(set) var forceRefreshCount = 0
    /// Наблюдение за индикатором ИЗНУТРИ сетевого вызова — иначе `defer` успевает погасить флаг.
    var onForceRefresh: (() -> Void)?

    init(snapshot: RateSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func currentRateSnapshot() -> RateSnapshot? { snapshot }

    func getRate(from: String, to: String) async -> Double? {
        from.uppercased() == to.uppercased() ? 1 : 1
    }

    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? {
        await getRate(from: from, to: to)
    }

    func convert(amount: Double, from: String, to: String) async -> Double? {
        guard let rate = await getRate(from: from, to: to) else { return nil }
        return amount * rate
    }

    func forceRefreshRates() async {
        forceRefreshCount += 1
        onForceRefresh?()
    }
}

@Suite("FinanceViewModel — индикатор загрузки курсов", .serialized)
struct FinanceViewModelRateIndicatorTests {

    @MainActor
    private func makeContext() throws -> ModelContext {
        try AppMigrationPlan.makeInMemoryContainer().mainContext
    }

    private func cachedSnapshot(fetchedAt: Double) -> RateSnapshot {
        RateSnapshot(source: .millio, rates: ["USD": 1, "RUB": 80], updatedAt: fetchedAt, fetchedAt: fetchedAt)
    }

    @Test("Есть кэш курсов — обновление идёт молча, индикатор не поднимается")
    @MainActor
    func testNoIndicatorWhenSnapshotCached() async throws {
        let context = try makeContext()
        let rateService = SnapshotAwareMockRateService(snapshot: cachedSnapshot(fetchedAt: 1_700_000_000))
        let viewModel = FinanceViewModel(modelContext: context, currencyService: rateService, skipInitialLoad: true)

        var indicatorSeen = false
        rateService.onForceRefresh = { indicatorSeen = indicatorSeen || viewModel.state.isLoadingRates }

        await viewModel.refreshAll()

        #expect(indicatorSeen == false)
        #expect(viewModel.state.isLoadingRates == false)
        #expect(rateService.forceRefreshCount == 1) // сеть всё равно обновляется — просто тихо
    }

    @Test("Кэша курсов нет (самый первый запуск) — индикатор показывается")
    @MainActor
    func testIndicatorShownWhenNothingCached() async throws {
        let context = try makeContext()
        let rateService = SnapshotAwareMockRateService(snapshot: nil)
        let viewModel = FinanceViewModel(modelContext: context, currencyService: rateService, skipInitialLoad: true)

        var indicatorSeen = false
        rateService.onForceRefresh = { indicatorSeen = indicatorSeen || viewModel.state.isLoadingRates }

        await viewModel.refreshAll()

        #expect(indicatorSeen == true)
        #expect(viewModel.state.isLoadingRates == false) // после завершения гасится
    }

    @Test("Холодный старт: lastRefreshedAt берётся из снимка на диске, а не считается nil")
    @MainActor
    func testLastRefreshedAtHydratedFromPersistedSnapshot() throws {
        let context = try makeContext()
        let fetchedAt = Date().timeIntervalSince1970 - 300
        let rateService = SnapshotAwareMockRateService(snapshot: cachedSnapshot(fetchedAt: fetchedAt))
        let viewModel = FinanceViewModel(modelContext: context, currencyService: rateService, skipInitialLoad: true)

        // Именно на этом значении стоит гейт scenePhase-обновления в FinancesView (15 мин).
        // Без гидрации оно было nil → .distantPast → принудительное обновление на каждом старте.
        let hydrated = try #require(viewModel.state.lastRefreshedAt)
        #expect(abs(hydrated.timeIntervalSince1970 - fetchedAt) < 1)
        #expect(Date().timeIntervalSince(hydrated) < 15 * 60)
    }

    @Test("Первый в жизни запуск: снимка нет — lastRefreshedAt остаётся nil, обновление нужно")
    @MainActor
    func testLastRefreshedAtNilWithoutSnapshot() throws {
        let context = try makeContext()
        let rateService = SnapshotAwareMockRateService(snapshot: nil)
        let viewModel = FinanceViewModel(modelContext: context, currencyService: rateService, skipInitialLoad: true)

        #expect(viewModel.state.lastRefreshedAt == nil)
    }

    @Test("Приход нового снимка курсов не запускает повторный принудительный запрос в сеть")
    @MainActor
    func testSnapshotNotificationDoesNotForceAnotherNetworkRefresh() async throws {
        let context = try makeContext()
        let rateService = SnapshotAwareMockRateService(snapshot: cachedSnapshot(fetchedAt: 1_700_000_000))
        let viewModel = FinanceViewModel(modelContext: context, currencyService: rateService, skipInitialLoad: true)

        NotificationCenter.default.post(name: .currencyRateSnapshotDidChange, object: nil)
        for _ in 0..<50 { await Task.yield() }

        #expect(rateService.forceRefreshCount == 0)
        #expect(viewModel.state.isLoadingRates == false)
    }
}
