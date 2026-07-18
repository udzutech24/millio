//
//  FinanceDynamicsSeriesInvariantTests.swift
//  millioTests
//
//  Ф4 dynamics-single-source-of-truth (specs/2026-07-18-dynamics-single-series-producer.md, AC1/AC2).
//
//  AC1 — главный инвариант: заголовок-дельта, концы серии (aggregatedDynamicsSeries → state.chartData)
//  и карточка «Общая сумма» обязаны совпадать для КАЖДОГО периода в unscoped-режиме. Заголовок в Ф3
//  НЕ читает массив серии — он считает те же концы напрямую (resolvedPeriodDates + calculateBalanceAtDate
//  + accountsTotalsService.totalAt). Равенство с серией «по построению» — этот файл замыкает инвариант
//  реальной численной проверкой на непустых данных, чтобы любой будущий дрейф двух путей ловился тестом.
//
//  AC2 — ось графика не содержит двух точек одного календарного дня (кроме документированного
//  исключения №4: два конца однодневного периода могут лежать в одном дне — Charts не рисует линию
//  из одной точки).

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Dynamics single-source producer: AC1 invariant + AC2 axis dedup (Ф4)")
@MainActor
struct FinanceDynamicsSeriesInvariantTests {

    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        intervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            await Task.yield()
            if condition() { return }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }

    private static let periods: [DynamicsPeriod] = [.day, .week, .month, .year, .all]

    /// Прогоняет инвариант AC1 для всех периодов на уже настроенном VM (счета загружены).
    private func assertInvariantHoldsForAllPeriods(
        _ vm: FinanceDynamicsViewModel,
        sourceLabel: String
    ) async {
        for period in Self.periods {
            vm.state.period = period
            vm.state.customPeriod = nil
            await vm.updateCurrentBalanceAndDelta()
            await vm.updateChartDataAsync()

            let points = vm.state.chartData.sorted { $0.date < $1.date }
            #expect(points.count >= 2, "[\(sourceLabel)/\(period.rawValue)] серия должна содержать ≥2 точки")
            guard points.count >= 2 else { continue }

            let seriesDelta = points[points.count - 1].value - points[0].value
            let headerDelta = vm.state.periodDelta.absolute

            #expect(
                abs(headerDelta - seriesDelta) < 0.01,
                "[\(sourceLabel)/\(period.rawValue)] заголовок-дельта \(headerDelta) должна совпасть с (последняя−первая) точки серии \(seriesDelta)"
            )

            if let card = vm.aggregateTotalRow() {
                let cardDelta = card.endValue - card.startValue
                #expect(
                    abs(cardDelta - seriesDelta) < 0.01,
                    "[\(sourceLabel)/\(period.rawValue)] карточка delta=\(cardDelta) должна совпасть с серией \(seriesDelta)"
                )
                #expect(
                    abs(card.delta - headerDelta) < 0.01,
                    "[\(sourceLabel)/\(period.rawValue)] карточка.delta=\(card.delta) должна совпасть с заголовком \(headerDelta)"
                )
            }
        }
    }

    /// AC2: нет двух точек одного календарного дня, кроме допустимой пары концов однодневного периода.
    private func assertNoDuplicateCalendarDays(_ points: [ChartDataPoint], label: String) {
        let calendar = Calendar.current
        let sorted = points.sorted { $0.date < $1.date }
        var seenDays: [Date: Int] = [:]
        for point in sorted {
            let day = calendar.startOfDay(for: point.date)
            seenDays[day, default: 0] += 1
        }
        let duplicates = seenDays.filter { $0.value > 1 }
        // Исключение №4: ровно один день может иметь 2 точки — это старт/конец однодневного периода.
        if duplicates.count == 1, let only = duplicates.first {
            #expect(only.value == 2, "[\(label)] день с дублем должен иметь ровно 2 точки (концы 1D-периода), получено \(only.value)")
        } else {
            #expect(duplicates.isEmpty, "[\(label)] найдены дублирующиеся календарные дни на оси: \(duplicates.keys)")
        }
    }

    // MARK: - Q4/сценарий «смешанный»: легаси + core, оба созданы задолго до всех периодов

    @Test("AC1: заголовок == серия == карточка на всех периодах (смешанный легаси+core портфель)")
    func invariantHolds_mixedLegacyAndCorePortfolio() async throws {
        let ctx = try makeContext()
        let now = Date()
        let createdAt = now.addingTimeInterval(-400 * 86_400) // старше 1Y, покрывает все периоды

        let financeGroup = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(financeGroup)
        let coreGroup = AccountGroup(name: "Основная")
        ctx.insert(coreGroup)

        let card = Card(name: "Карта", cardNumber: "1111", cardType: .debit, currency: "RUB", balance: 100_000)
        card.createdAt = createdAt
        card.updatedAt = now
        card.initialBalance = 100_000
        card.hasInitialBalance = true
        ctx.insert(card)
        let legacyAccount = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        legacyAccount.group = financeGroup
        financeGroup.accounts = [legacyAccount]
        ctx.insert(legacyAccount)

        let accountsService = AccountsCoreService(modelContext: ctx)
        _ = try accountsService.createAccount(
            name: "Наличные", kind: .cash, currency: "RUB", openingBalance: 50_000, group: coreGroup, date: createdAt
        )
        try ctx.save()

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        dynamicsViewModel.state.dynamicsMode = .aggregated

        await assertInvariantHoldsForAllPeriods(dynamicsViewModel, sourceLabel: "mixed")
    }

    // MARK: - Q2: счёт создан внутри периода — база=0, без клэмпа

    @Test("AC1+AC3(Q2): счёт создан внутри периода — база=0 без клэмпа, инвариант держится")
    func invariantHolds_accountCreatedInsidePeriod() async throws {
        let ctx = try makeContext()
        let now = Date()
        let createdAt = now.addingTimeInterval(-10 * 86_400) // внутри 1M/1Y/All, ПОСЛЕ старта 1M

        let financeGroup = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(financeGroup)
        let card = Card(name: "Новая карта", cardNumber: "2222", cardType: .debit, currency: "RUB", balance: 75_000)
        card.createdAt = createdAt
        card.updatedAt = now
        card.initialBalance = 75_000
        card.hasInitialBalance = true
        ctx.insert(card)
        let legacyAccount = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        legacyAccount.group = financeGroup
        financeGroup.accounts = [legacyAccount]
        ctx.insert(legacyAccount)
        try ctx.save()

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        dynamicsViewModel.state.dynamicsMode = .aggregated
        dynamicsViewModel.state.period = .month
        await dynamicsViewModel.updateCurrentBalanceAndDelta()
        await dynamicsViewModel.updateChartDataAsync()

        let points = dynamicsViewModel.state.chartData.sorted { $0.date < $1.date }
        #expect(abs(points.first?.value ?? -1) < 0.01, "Q2: база периода = 0 (счёт создан после periodStart), без клэмпа диапазона")
        #expect(abs((points.last?.value ?? 0) - 75_000) < 0.01, "Конец периода = живой баланс 75 000")

        await assertInvariantHoldsForAllPeriods(dynamicsViewModel, sourceLabel: "created-inside-period")
    }

    // MARK: - Q3: архивный счёт в истории — база+история его учитывают

    @Test("AC1+AC4(Q3): архивный счёт остаётся в базе периода и истории, инвариант держится")
    func invariantHolds_archivedAccountInHistory() async throws {
        let ctx = try makeContext()
        let now = Date()
        let createdAt = now.addingTimeInterval(-100 * 86_400)
        let archivedAt = now.addingTimeInterval(-20 * 86_400) // архивация внутри 1M/1Y периода

        let financeGroup = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(financeGroup)
        let card = Card(name: "Архивная карта", cardNumber: "3333", cardType: .debit, currency: "RUB", balance: 60_000)
        card.createdAt = createdAt
        card.updatedAt = archivedAt
        card.initialBalance = 60_000
        card.hasInitialBalance = true
        card.archivedAt = archivedAt
        ctx.insert(card)
        let legacyAccount = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        legacyAccount.group = financeGroup
        financeGroup.accounts = [legacyAccount]
        ctx.insert(legacyAccount)

        // Живой счёт рядом, чтобы период/серия не были вырожденными (архивный счёт один не даёт "current").
        let liveCard = Card(name: "Живая карта", cardNumber: "4444", cardType: .debit, currency: "RUB", balance: 30_000)
        liveCard.createdAt = createdAt
        liveCard.updatedAt = now
        liveCard.initialBalance = 30_000
        liveCard.hasInitialBalance = true
        ctx.insert(liveCard)
        let liveAccount = FinanceAccount(accountType: .card, accountID: liveCard.cardUniqueID)
        liveAccount.group = financeGroup
        financeGroup.accounts?.append(liveAccount)
        ctx.insert(liveAccount)
        try ctx.save()

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        dynamicsViewModel.state.dynamicsMode = .aggregated

        await assertInvariantHoldsForAllPeriods(dynamicsViewModel, sourceLabel: "archived-in-history")
    }

    // MARK: - Только core

    @Test("AC1+AC5: только core-портфель — инвариант держится на всех периодах")
    func invariantHolds_coreOnlyPortfolio() async throws {
        let ctx = try makeContext()
        let createdAt = Date().addingTimeInterval(-400 * 86_400)

        let coreGroup = AccountGroup(name: "Основная")
        ctx.insert(coreGroup)
        let accountsService = AccountsCoreService(modelContext: ctx)
        _ = try accountsService.createAccount(
            name: "Наличные", kind: .cash, currency: "RUB", openingBalance: 120_000, group: coreGroup, date: createdAt
        )
        try ctx.save()

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        dynamicsViewModel.state.dynamicsMode = .aggregated

        // "All" без легаси-групп/транзакций падает на earliestDate=now (вырожденный период) — это
        // допустимо и покрыто guard'ом points.count>=2 внутри aggregatedDynamicsSeries (синтетические
        // start/end). Инвариант всё равно обязан держаться.
        await assertInvariantHoldsForAllPeriods(dynamicsViewModel, sourceLabel: "core-only")
    }

    // MARK: - Только легаси

    @Test("AC1+AC5: только легаси-портфель — инвариант держится на всех периодах (нет регрессии)")
    func invariantHolds_legacyOnlyPortfolio() async throws {
        let ctx = try makeContext()
        let now = Date()
        let createdAt = now.addingTimeInterval(-400 * 86_400)

        let financeGroup = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(financeGroup)
        let card = Card(name: "Обычная карта", cardNumber: "5555", cardType: .debit, currency: "RUB", balance: 80_000)
        card.createdAt = createdAt
        card.updatedAt = now
        card.initialBalance = 80_000
        card.hasInitialBalance = true
        ctx.insert(card)
        let legacyAccount = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        legacyAccount.group = financeGroup
        financeGroup.accounts = [legacyAccount]
        ctx.insert(legacyAccount)
        try ctx.save()

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        dynamicsViewModel.state.dynamicsMode = .aggregated

        await assertInvariantHoldsForAllPeriods(dynamicsViewModel, sourceLabel: "legacy-only")
    }

    // MARK: - AC2: дедуп оси по календарному дню

    @Test("AC2: ось графика не содержит двух точек одного календарного дня (кроме концов 1D-периода)")
    func axisHasNoDuplicateCalendarDays() async throws {
        let ctx = try makeContext()
        let now = Date()
        let createdAt = now.addingTimeInterval(-400 * 86_400)

        let financeGroup = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(financeGroup)
        let coreGroup = AccountGroup(name: "Основная")
        ctx.insert(coreGroup)

        let card = Card(name: "Карта", cardNumber: "6666", cardType: .debit, currency: "RUB", balance: 100_000)
        card.createdAt = createdAt
        card.updatedAt = now
        card.initialBalance = 100_000
        card.hasInitialBalance = true
        ctx.insert(card)
        let legacyAccount = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        legacyAccount.group = financeGroup
        financeGroup.accounts = [legacyAccount]
        ctx.insert(legacyAccount)

        let accountsService = AccountsCoreService(modelContext: ctx)
        _ = try accountsService.createAccount(
            name: "Наличные", kind: .cash, currency: "RUB", openingBalance: 50_000, group: coreGroup, date: createdAt
        )
        try ctx.save()

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        dynamicsViewModel.state.dynamicsMode = .aggregated

        for period in Self.periods {
            dynamicsViewModel.state.period = period
            dynamicsViewModel.state.customPeriod = nil
            await dynamicsViewModel.updateChartDataAsync()
            assertNoDuplicateCalendarDays(dynamicsViewModel.state.chartData, label: period.rawValue)
        }
    }
}
