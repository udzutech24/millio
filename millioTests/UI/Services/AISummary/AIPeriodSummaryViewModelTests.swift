import Foundation
import XCTest
@testable import millio

/// Экран итогов обязан быть непустым в любом состоянии: цифры локальные, текст модели —
/// необязательная надстройка. Эндпоинт на момент фазы ещё не задеплоен.
@MainActor
final class AIPeriodSummaryViewModelTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Опорная дата всех проверок — 10 сентября 2026: текущий месяц незакрыт, квартал захватывает
    /// три месяца, предыдущее окно попадает на конец августа.
    private var now: Date { date(2026, 9, 10) }

    /// Счётчик вызовов ссылочным типом: замыкание источника данных нельзя мутировать напрямую.
    private final class CallCounter {
        private(set) var count = 0
        func increment() { count += 1 }
    }

    // MARK: - Стабы

    private final class SpyClient: AIPeriodSummaryClient, @unchecked Sendable {
        var isAvailable: Bool
        var result: Result<AIPeriodSummaryText, Error>
        private(set) var callCount = 0
        private(set) var lastRequest: AIPeriodSummaryRequest?

        init(isAvailable: Bool = true, result: Result<AIPeriodSummaryText, Error>) {
            self.isAvailable = isAvailable
            self.result = result
        }

        func summarize(_ request: AIPeriodSummaryRequest) async throws -> AIPeriodSummaryText {
            callCount += 1
            lastRequest = request
            return try result.get()
        }
    }

    private func makeCache() -> AIPeriodSummaryCache {
        AIPeriodSummaryCache(
            defaults: UserDefaults(suiteName: "ai.summary.tests.\(UUID().uuidString)")!,
            storageKey: "test.cache"
        )
    }

    private var entries: [CashflowConvertedTransaction] {
        [
            CashflowConvertedTransaction(id: "a", date: date(2026, 8, 25), income: 7_000, expense: 0),
            CashflowConvertedTransaction(id: "b", date: date(2026, 9, 1), income: 12_000, expense: 0),
            CashflowConvertedTransaction(id: "c", date: date(2026, 9, 5), income: 0, expense: 5_000)
        ]
    }

    private func makeDataSource(categoryCounter: CallCounter? = nil) -> AIPeriodSummaryDataSource {
        let entries = entries
        return AIPeriodSummaryDataSource(
            entries: { entries },
            currency: { "RUB" },
            balance: { 250_000 },
            expenseCategoryTotals: { _ in
                categoryCounter?.increment()
                return ["Продукты": 5_000]
            }
        )
    }

    private func makeViewModel(
        client: any AIPeriodSummaryClient,
        cache: AIPeriodSummaryCache,
        dataSource: AIPeriodSummaryDataSource? = nil
    ) -> AIPeriodSummaryViewModel {
        AIPeriodSummaryViewModel(
            dataSource: dataSource ?? makeDataSource(),
            client: client,
            cache: cache,
            now: { [now] in now },
            calendar: calendar,
            locale: { Locale(identifier: "ru_RU") }
        )
    }

    // MARK: - Цифры всегда есть

    func testFiguresAreComputedLocallyBeforeAnyNetworkCall() {
        let client = SpyClient(result: .failure(AIPeriodSummaryClientError.transport))
        let viewModel = makeViewModel(client: client, cache: makeCache())

        viewModel.refresh()

        XCTAssertEqual(viewModel.figures.income, 12_000, accuracy: 0.001)
        XCTAssertEqual(viewModel.figures.expense, 5_000, accuracy: 0.001)
        XCTAssertEqual(viewModel.figures.previousIncome, 7_000, accuracy: 0.001)
        XCTAssertEqual(viewModel.figures.balanceEnd, 250_000, accuracy: 0.001)
        XCTAssertEqual(viewModel.currency, "RUB")
    }

    func testOfflineKeepsFiguresAndReportsTextUnavailable() async {
        let client = SpyClient(result: .failure(AIPeriodSummaryClientError.transport))
        let viewModel = makeViewModel(client: client, cache: makeCache())

        viewModel.refresh()
        await waitUntil { !viewModel.isLoadingText && viewModel.isTextUnavailable }

        XCTAssertNil(viewModel.text)
        XCTAssertTrue(viewModel.isTextUnavailable)
        XCTAssertFalse(viewModel.isLoadingText, "Спиннер не должен зависать после ошибки сети")
        XCTAssertEqual(viewModel.figures.income, 12_000, accuracy: 0.001)
    }

    func testUnavailableClientDoesNotSpin() async {
        let client = SpyClient(isAvailable: false, result: .failure(AIPeriodSummaryClientError.unavailable))
        let viewModel = makeViewModel(client: client, cache: makeCache())

        viewModel.refresh()
        await waitUntil { viewModel.isTextUnavailable }

        XCTAssertEqual(client.callCount, 0)
        XCTAssertFalse(viewModel.isLoadingText)
        XCTAssertEqual(viewModel.figures.expense, 5_000, accuracy: 0.001)
    }

    func testEmptyServerTextFallsBackToNumbersOnly() async {
        let client = SpyClient(result: .success(AIPeriodSummaryText(headline: nil, observations: [])))
        let viewModel = makeViewModel(client: client, cache: makeCache())

        viewModel.refresh()
        await waitUntil { viewModel.isTextUnavailable }

        XCTAssertNil(viewModel.text)
        XCTAssertEqual(client.callCount, 1)
    }

    // MARK: - Кэш

    func testCacheHitShowsTextWithoutTouchingNetwork() async {
        let cache = makeCache()
        let text = AIPeriodSummaryText(
            headline: "Расходы ниже дохода",
            observations: [AIPeriodObservation(text: "Доходы выросли", kind: .growth)]
        )
        let first = SpyClient(result: .success(text))
        let warmUp = makeViewModel(client: first, cache: cache)
        warmUp.refresh()
        await waitUntil { warmUp.text != nil }
        XCTAssertEqual(first.callCount, 1)

        let categoryCounter = CallCounter()
        let second = SpyClient(result: .success(text))
        let viewModel = makeViewModel(
            client: second,
            cache: cache,
            dataSource: makeDataSource(categoryCounter: categoryCounter)
        )
        viewModel.refresh()

        XCTAssertEqual(viewModel.text?.headline, "Расходы ниже дохода")
        XCTAssertEqual(second.callCount, 0, "Попадание в кэш не должно ходить в сеть")
        XCTAssertEqual(categoryCounter.count, 0, "И не должно пересчитывать категории")
        XCTAssertFalse(viewModel.isTextUnavailable)
    }

    func testFailedKeyIsNotRetriedInTheSameSession() async {
        let client = SpyClient(result: .failure(AIPeriodSummaryClientError.transport))
        let viewModel = makeViewModel(client: client, cache: makeCache())

        viewModel.refresh()
        await waitUntil { viewModel.isTextUnavailable }
        viewModel.refresh()
        await waitUntil { viewModel.isTextUnavailable }

        XCTAssertEqual(client.callCount, 1, "Лимит эндпоинта 5/мин — повторно долбить нельзя")
    }

    // MARK: - Переключение периода

    func testSwitchingToQuarterRecomputesFiguresOverThreeMonths() {
        let client = SpyClient(result: .failure(AIPeriodSummaryClientError.transport))
        let viewModel = makeViewModel(client: client, cache: makeCache())

        viewModel.refresh()
        let monthIncome = viewModel.figures.income

        viewModel.select(.quarter)

        XCTAssertEqual(viewModel.kind, .quarter)
        XCTAssertEqual(viewModel.period.start(calendar: calendar), date(2026, 7, 1))
        // Квартал захватывает и августовский доход, месяц — нет.
        XCTAssertEqual(monthIncome, 12_000, accuracy: 0.001)
        XCTAssertEqual(viewModel.figures.income, 19_000, accuracy: 0.001)
    }

    func testSelectingSameKindDoesNotResetState() async {
        let text = AIPeriodSummaryText(headline: "Итоги", observations: [])
        let client = SpyClient(result: .success(text))
        let viewModel = makeViewModel(client: client, cache: makeCache())

        viewModel.refresh()
        await waitUntil { viewModel.text != nil }
        viewModel.select(.month)

        XCTAssertEqual(viewModel.text?.headline, "Итоги")
        XCTAssertEqual(client.callCount, 1)
    }

    func testRequestCarriesLocalFiguresAndCategories() async {
        let client = SpyClient(result: .success(AIPeriodSummaryText(headline: "Итоги", observations: [])))
        let viewModel = makeViewModel(client: client, cache: makeCache())

        viewModel.refresh()
        await waitUntil { client.lastRequest != nil }

        let request = client.lastRequest
        XCTAssertEqual(request?.locale, "ru")
        XCTAssertEqual(request?.currency, "RUB")
        XCTAssertEqual(request?.period.kind, "month")
        XCTAssertEqual(request?.totals.income, 12_000)
        XCTAssertEqual(request?.totals.expense, 5_000)
        XCTAssertEqual(request?.totals.net, 7_000)
        XCTAssertEqual(request?.totals.balanceEnd, 250_000)
        XCTAssertEqual(request?.previousPeriod.income, 7_000)
        XCTAssertEqual(request?.byCategory.first?.categoryId, "Продукты")
    }

    // MARK: - Helpers

    private func waitUntil(
        timeout: TimeInterval = 3,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "Условие не выполнилось за \(timeout) с")
    }
}
