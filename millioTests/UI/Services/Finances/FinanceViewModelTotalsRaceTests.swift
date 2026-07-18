//
//  FinanceViewModelTotalsRaceTests.swift
//  millioTests
//
//  Регрессия на гонку пересчёта тоталов в FinanceViewModel (2026-07-18):
//  scheduleBackgroundTask кидал Task без generation-stamp — более старый пересчёт (застрявший
//  на "сети" за котировкой холодного тикера) мог финишировать позже более нового и перезаписать
//  state.totalAmount устаревшим значением. Фикс — generation + published-watermark в
//  calculateTotalAmountAsync/refreshGroupTotalsAndAmounts.
//
//  Гонка воспроизведена ДЕТЕРМИНИРОВАННО через continuation-гейт (не Task.sleep) — реальная
//  задержка по времени раздувает нагрузку на MainActor-шедулер и может дестабилизировать другие
//  @Suite, выполняющиеся параллельно в том же процессе (Swift Testing по умолчанию не сериализует
//  разные @Suite между собой).
//

import Foundation
import Testing
import SwiftData
@testable import millio

/// Мок курса валют, где ПЕРВЫЙ вызов `getRate` подвешивается на управляемом continuation —
/// снимается явно тестом, только после того как второй (более новый) вызов уже завершился.
/// Так гонка «стартовал раньше, финишировал позже» воспроизводится без реального Task.sleep.
@MainActor
final class GatedMockRateService: CurrencyRateServiceProtocol {
    private var pendingContinuation: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0
    var rates: [Double] = []

    func getRate(from: String, to: String) async -> Double? {
        if from.uppercased() == to.uppercased() { return 1 }
        let index = callCount
        callCount += 1
        if index == 0 {
            await withCheckedContinuation { pendingContinuation = $0 }
        }
        return index < rates.count ? rates[index] : (rates.last ?? 1)
    }

    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? {
        await getRate(from: from, to: to)
    }

    func convert(amount: Double, from: String, to: String) async -> Double? {
        guard let rate = await getRate(from: from, to: to) else { return nil }
        return amount * rate
    }

    func forceRefreshRates() async {}

    /// Отпускает первый (застрявший) вызов `getRate`.
    func releaseFirstCall() {
        pendingContinuation?.resume()
        pendingContinuation = nil
    }
}

@Suite("FinanceViewModel — гонка пересчёта тоталов", .serialized)
struct FinanceViewModelTotalsRaceTests {

    private func makeContainer() throws -> ModelContainer {
        try AppMigrationPlan.makeInMemoryContainer()
    }

    @Test("Позже стартовавший пересчёт побеждает, даже если финиширует раньше более старого")
    @MainActor
    func testLatestStartedRecalcWinsOverSlowerOlderOne() async throws {
        // Отключаем побочный конвертёр savings goal — иначе фоновая задача из init() может
        // случайно дёрнуть getRate раньше наших тестовых вызовов и сбить нумерацию моков.
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "finance_savings_goal_enabled")
        defaults.set(0, forKey: "finance_savings_goal_amount")
        defaults.removeObject(forKey: "finance_savings_goal_currency")

        let container = try makeContainer()
        let context = container.mainContext
        let coreService = AccountsCoreService(modelContext: context)
        _ = try coreService.createAccount(name: "Счёт USD", kind: .bankAccount, currency: "USD", openingBalance: 100)

        let rateService = GatedMockRateService()
        // Вызов №0 (из "старого" пересчёта, стартует первым) — подвисает на continuation, курс 90.
        // Вызов №1 (из "нового" пересчёта) — мгновенный, курс 80.
        rateService.rates = [90, 80]

        let viewModel = FinanceViewModel(modelContext: context, currencyService: rateService, skipInitialLoad: true)
        viewModel.state.displayCurrency = "RUB"
        viewModel.state.secondaryDisplayCurrency = nil

        let olderTask = Task { await viewModel.calculateTotalAmountAsync() }
        // Даём старому вызову синхронно застолбить своё поколение и дойти до гейта в getRate —
        // без реального времени: несколько Task.yield() вместо Task.sleep.
        for _ in 0..<20 { await Task.yield() }

        let newerTask = Task { await viewModel.calculateTotalAmountAsync() }
        _ = await newerTask.value

        // Новый пересчёт уже опубликовал результат, пока старый всё ещё висит на гейте.
        #expect(viewModel.state.totalAmount == 100 * 80)

        rateService.releaseFirstCall()
        _ = await olderTask.value

        // Старый (стартовавший раньше) финишировал последним, но его результат устарел —
        // он не должен откатить уже опубликованное новое значение.
        #expect(viewModel.state.totalAmount == 100 * 80)
    }

    /// Регрессия на реальный баг с устройства (2026-07-18): сохранение нового продукта («Новый
    /// продукт» → core CREATE) не публикует `investmentsUpdated`, а `.hideAddAccountSheet` раньше
    /// вызывал только `loadCoreEntities()` (списки), но не пересчёт тоталов — шапка «Счета»
    /// оставалась старой до ручного pull-to-refresh.
    @Test("hideAddAccountSheet пересчитывает totalAmount после CREATE на новом ядре")
    @MainActor
    func testHideAddAccountSheetRefreshesTotalAfterCreate() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let viewModel = FinanceViewModel(modelContext: context, currencyService: GatedMockRateService(), skipInitialLoad: true)
        viewModel.state.displayCurrency = "USD"
        viewModel.state.secondaryDisplayCurrency = nil

        #expect(viewModel.state.totalAmount == 0)

        // Имитируем CREATE, как его делает `FinanceAddAccountView.createAssetAccountOnNewCore` —
        // напрямую через `AccountsCoreService`, EventBus не публикуется (см. комментарий в фиксе).
        let coreService = AccountsCoreService(modelContext: context)
        _ = try coreService.createAccount(name: "Новая акция", kind: .bankAccount, currency: "USD", openingBalance: 250)

        // Форма вызывает `dismiss()`, что переводит `isPresented` в false → `.hideAddAccountSheet`.
        viewModel.handle(.hideAddAccountSheet)
        for _ in 0..<20 { await Task.yield() }

        #expect(viewModel.state.totalAmount == 250)
    }

    /// Регрессия на остаточное окно гонки (найдено Fable-ревью), закрытое тем же generation-guard'ом:
    /// один `.updateAccountAmount` синхронно заводит ДВА независимых пересчёта суммы группы —
    /// точечный `scheduleGroupTotalRefresh` (стартует первым, генерация меньше) и полный
    /// `refreshGroupTotalsAndAmounts` через каскад `investmentsUpdated` (стартует вторым, генерация
    /// больше). Раньше точечный путь писал `groupTotals[id]` мимо watermark — мог откатить уже
    /// опубликованный более новый результат.
    @Test("scheduleGroupTotalRefresh не откатывает groupTotals более новым generation")
    @MainActor
    func testGroupTotalRefreshDoesNotRollBackToStaleGeneration() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let group = AccountGroup(name: "Портфель", displayCurrency: "EUR")
        context.insert(group)
        let coreService = AccountsCoreService(modelContext: context)
        let account = try coreService.createAccount(name: "Счёт USD", kind: .bankAccount, currency: "USD", openingBalance: 100, group: group)

        let rateService = GatedMockRateService()
        let viewModel = FinanceViewModel(modelContext: context, currencyService: rateService, skipInitialLoad: true)
        // displayCurrency совпадает с валютой счёта — полный пересчёт totalAmount не трогает мок
        // (rate() короткое замыкание на одинаковых валютах), вся гонка изолирована на паре USD→EUR
        // (валюта группы), которую пересчитывают ОБА пути.
        viewModel.state.displayCurrency = "USD"
        viewModel.state.secondaryDisplayCurrency = nil

        viewModel.handle(.loadGroups)
        for _ in 0..<20 { await Task.yield() }

        // Вызов №0 — из `scheduleGroupTotalRefresh` (стартует первым в теле `updateAccountAmount`,
        // генерация меньше) — подвисает на continuation, курс 90. Вызов №1 — из каскадного
        // `refreshGroupTotalsAndAmounts` (EventBus `investmentsUpdated`, генерация больше) — мгновенный, курс 80.
        rateService.rates = [90, 80]

        viewModel.handle(.updateAccountAmount(account, 250))
        // [Фикс флака, 2026-07-18] Фиксированный счётчик Task.yield() не гарантирует, что
        // ungated-путь (`refreshGroupTotalsAndAmounts`) успеет дойти до публикации под нагрузкой
        // (параллельные симуляторные клоны в общем прогоне xcodebuild test) — доказано воспроизведением
        // провала именно в комбинированном прогоне при стабильном "TEST SUCCEEDED" в изоляции.
        // Ждём условие по факту (тот же `waitUntil`-паттерн, что и в других тестах с фоновыми
        // пересчётами VM, см. FinanceDynamicsCoreContributionTests), а не по числу тиков.
        await waitUntil { viewModel.state.groupTotals[group.groupUniqueID] == 250 * 80 }

        // [Root cause найден расследованием] `#expect(optionalDouble == literal)` в этой версии
        // Swift Testing даёт ложный "Failed" с ОДИНАКОВЫМИ значениями по обе стороны "→" в диагностике
        // (проверено: `try #require`-unwrap в non-optional Double убирает эффект полностью, а
        // соседний тест `testLatestStartedRecalcWinsOverSlowerOlderOne`, сравнивающий НЕ-Optional
        // `state.totalAmount`, никогда не флакует тем же способом) — сравниваем Optional только
        // через явный unwrap, не напрямую.
        let totalAfterFirstWait = try #require(viewModel.state.groupTotals[group.groupUniqueID])
        // Новый (больший generation) пересчёт уже опубликовал 250 * 80, пока старый висит на гейте.
        #expect(totalAfterFirstWait == 250 * 80)

        rateService.releaseFirstCall()
        // Детерминированного "события" дождаться нечего (мы проверяем ОТСУТСТВИЕ отката) — даём
        // освобождённому старому Task'у реальное время (не только тики) пройти getRate → watermark-
        // guard → no-op, вместо фиксированного числа yield'ов.
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        // Старый (меньший generation) финишировал последним, но его результат устарел — не должен
        // откатить уже опубликованное значение нового пересчёта.
        let totalAfterRelease = try #require(viewModel.state.groupTotals[group.groupUniqueID])
        #expect(totalAfterRelease == 250 * 80)
    }

    /// Тот же bounded-poll паттерн, что и в остальных тестах VM с фоновыми пересчётами
    /// (см. `FinanceDynamicsCoreContributionTests.waitUntil`) — ждёт условие по факту вместо
    /// фиксированного числа `Task.yield()`, которое не масштабируется под нагрузку параллельных
    /// тестовых клонов симулятора.
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        intervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            await Task.yield()
            if await condition() { return }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }
}
