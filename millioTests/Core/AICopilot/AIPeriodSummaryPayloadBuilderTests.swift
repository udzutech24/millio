import Foundation
import XCTest
@testable import millio

final class AIPeriodSummaryPayloadBuilderTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func entry(_ year: Int, _ month: Int, _ day: Int, income: Double = 0, expense: Double = 0) -> CashflowConvertedTransaction {
        CashflowConvertedTransaction(
            id: "\(year)-\(month)-\(day)-\(income)-\(expense)",
            date: date(year, month, day),
            income: income,
            expense: expense
        )
    }

    private var sampleEntries: [CashflowConvertedTransaction] {
        [
            entry(2026, 8, 21, income: 1_000),     // до предыдущего окна
            entry(2026, 8, 22, expense: 400),      // предыдущее окно 22–31.08
            entry(2026, 8, 25, income: 7_000),
            entry(2026, 8, 31, expense: 600),
            entry(2026, 9, 1, income: 12_000),     // текущее окно 01–10.09
            entry(2026, 9, 5, expense: 3_500),
            entry(2026, 9, 10, expense: 1_500),
            entry(2026, 9, 25, income: 999_999)    // будущее — за пределами окна
        ]
    }

    // MARK: - Совпадение с движком графиков кэшфлоу

    func testCurrentAndPreviousTotalsMatchCashflowInsightsChartBuilder() {
        let now = date(2026, 9, 10)
        let period = AIPeriodSummaryPeriod(kind: .month, anchor: now)
        let range = period.effectiveRange(now: now, calendar: calendar)

        let presentation = CashflowInsightsChartBuilder.makePresentation(
            entries: sampleEntries,
            dateRange: range,
            granularity: .week,
            calendar: calendar,
            locale: Locale(identifier: "ru_RU")
        )

        let figures = AIPeriodSummaryPayloadBuilder.figures(
            entries: sampleEntries,
            period: period,
            now: now,
            balanceEnd: 0,
            calendar: calendar
        )

        XCTAssertEqual(figures.income, presentation.incomeCard.amount, accuracy: 0.001)
        XCTAssertEqual(figures.expense, presentation.expenseCard.amount, accuracy: 0.001)
        // delta карточки = текущее − предыдущее, значит предыдущее = amount − delta.
        XCTAssertEqual(
            figures.previousIncome,
            presentation.incomeCard.amount - presentation.incomeCard.delta,
            accuracy: 0.001
        )
        XCTAssertEqual(
            figures.previousExpense,
            presentation.expenseCard.amount - presentation.expenseCard.delta,
            accuracy: 0.001
        )
    }

    func testFiguresIgnoreEntriesOutsideWindow() {
        let now = date(2026, 9, 10)
        let figures = AIPeriodSummaryPayloadBuilder.figures(
            entries: sampleEntries,
            period: AIPeriodSummaryPeriod(kind: .month, anchor: now),
            now: now,
            balanceEnd: 555,
            calendar: calendar
        )
        XCTAssertEqual(figures.income, 12_000, accuracy: 0.001)
        XCTAssertEqual(figures.expense, 5_000, accuracy: 0.001)
        XCTAssertEqual(figures.previousIncome, 7_000, accuracy: 0.001)
        XCTAssertEqual(figures.previousExpense, 1_000, accuracy: 0.001)
        XCTAssertEqual(figures.net, 7_000, accuracy: 0.001)
        XCTAssertEqual(figures.balanceEnd, 555, accuracy: 0.001)
    }

    func testEmptyEntriesProduceZeroFiguresInsteadOfCrash() {
        let now = date(2026, 9, 10)
        let figures = AIPeriodSummaryPayloadBuilder.figures(
            entries: [],
            period: AIPeriodSummaryPeriod(kind: .quarter, anchor: now),
            now: now,
            balanceEnd: 0,
            calendar: calendar
        )
        XCTAssertEqual(figures, .zero)
    }

    // MARK: - Контракт запроса

    /// На бэкенде `forbidNonWhitelisted`: любое лишнее поле — 400. Набор ключей фиксируем тестом.
    func testRequestEncodesExactlyTheWhitelistedKeys() throws {
        let request = makeSampleRequest()
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(
            Set(json.keys),
            ["schemaVersion", "locale", "period", "currency", "totals", "byCategory", "previousPeriod"]
        )
        let period = try XCTUnwrap(json["period"] as? [String: Any])
        XCTAssertEqual(Set(period.keys), ["kind", "start", "end"])

        let totals = try XCTUnwrap(json["totals"] as? [String: Any])
        XCTAssertEqual(Set(totals.keys), ["income", "expense", "net", "balanceEnd"])

        let previous = try XCTUnwrap(json["previousPeriod"] as? [String: Any])
        XCTAssertEqual(Set(previous.keys), ["income", "expense", "net"])
        let categories = try XCTUnwrap(json["byCategory"] as? [[String: Any]])
        XCTAssertEqual(Set(categories[0].keys), ["categoryId", "amount"])
    }

    func testRequestUsesIsoDayBoundsAndPeriodKind() {
        let request = makeSampleRequest()
        XCTAssertEqual(request.period.kind, "month")
        XCTAssertEqual(request.period.start, "2026-09-01")
        XCTAssertEqual(request.period.end, "2026-09-10")
        XCTAssertEqual(request.schemaVersion, "1")
    }

    func testCategoriesAreSortedByAmountAndCapped() {
        var totals: [String: Double] = [:]
        for index in 0..<20 { totals["cat-\(index)"] = Double(index) * 100 }
        totals["zero"] = 0
        let request = AIPeriodSummaryPayloadBuilder.makeRequest(
            period: AIPeriodSummaryPeriod(kind: .month, anchor: date(2026, 9, 10)),
            now: date(2026, 9, 10),
            figures: .zero,
            categoryTotals: totals,
            currency: "RUB",
            locale: Locale(identifier: "ru_RU"),
            calendar: calendar
        )
        XCTAssertEqual(request.byCategory.count, AIPeriodSummaryPayloadBuilder.maxCategories)
        XCTAssertEqual(request.byCategory.first?.categoryId, "cat-19")
        XCTAssertFalse(request.byCategory.contains { $0.categoryId == "zero" })
        XCTAssertEqual(
            request.byCategory.map(\.amount),
            request.byCategory.map(\.amount).sorted(by: >)
        )
    }

    // MARK: - Локаль

    func testBackendLocaleIsNarrowedToSupportedThree() {
        XCTAssertEqual(AIPeriodSummaryPayloadBuilder.backendLocale(from: Locale(identifier: "ru_RU")), "ru")
        XCTAssertEqual(AIPeriodSummaryPayloadBuilder.backendLocale(from: Locale(identifier: "zh-Hans")), "zh-Hans")
        XCTAssertEqual(AIPeriodSummaryPayloadBuilder.backendLocale(from: Locale(identifier: "zh_Hans_CN")), "zh-Hans")
        XCTAssertEqual(AIPeriodSummaryPayloadBuilder.backendLocale(from: Locale(identifier: "en_US")), "en")
        // Языки без поддержки на бэкенде сводим к en, иначе строгий DTO вернёт 400.
        XCTAssertEqual(AIPeriodSummaryPayloadBuilder.backendLocale(from: Locale(identifier: "de_DE")), "en")
        XCTAssertEqual(AIPeriodSummaryPayloadBuilder.backendLocale(from: Locale(identifier: "tr_TR")), "en")
    }

    // MARK: - Ключ кэша

    func testCacheKeyChangesWithFiguresAndPeriod() {
        let now = date(2026, 9, 10)
        let period = AIPeriodSummaryPeriod(kind: .month, anchor: now)
        let base = AIPeriodFigures(income: 100, expense: 50, previousIncome: 10, previousExpense: 5, balanceEnd: 900)

        let key = AIPeriodSummaryPayloadBuilder.cacheKey(
            period: period, now: now, figures: base, currency: "RUB",
            locale: Locale(identifier: "ru_RU"), calendar: calendar
        )
        let sameKey = AIPeriodSummaryPayloadBuilder.cacheKey(
            period: period, now: now, figures: base, currency: "RUB",
            locale: Locale(identifier: "ru_RU"), calendar: calendar
        )
        XCTAssertEqual(key, sameKey)

        let changedFigures = AIPeriodFigures(income: 101, expense: 50, previousIncome: 10, previousExpense: 5, balanceEnd: 900)
        XCTAssertNotEqual(key, AIPeriodSummaryPayloadBuilder.cacheKey(
            period: period, now: now, figures: changedFigures, currency: "RUB",
            locale: Locale(identifier: "ru_RU"), calendar: calendar
        ))

        XCTAssertNotEqual(key, AIPeriodSummaryPayloadBuilder.cacheKey(
            period: AIPeriodSummaryPeriod(kind: .quarter, anchor: now), now: now, figures: base,
            currency: "RUB", locale: Locale(identifier: "ru_RU"), calendar: calendar
        ))

        XCTAssertNotEqual(key, AIPeriodSummaryPayloadBuilder.cacheKey(
            period: period, now: now, figures: base, currency: "USD",
            locale: Locale(identifier: "ru_RU"), calendar: calendar
        ))

        XCTAssertNotEqual(key, AIPeriodSummaryPayloadBuilder.cacheKey(
            period: period, now: now, figures: base, currency: "RUB",
            locale: Locale(identifier: "en_US"), calendar: calendar
        ))
    }

    // MARK: - Ответ

    func testResponseWithNullHeadlineDecodesIntoNumbersOnlyText() throws {
        let json = Data(#"{"period":{"kind":"month","start":"2026-09-01","end":"2026-09-10"},"currency":"RUB","totals":{"income":1,"expense":2,"net":-1,"balanceEnd":3},"headline":null,"observations":[]}"#.utf8)
        let text = try JSONDecoder().decode(AIPeriodSummaryText.self, from: json)
        XCTAssertNil(text.headline)
        XCTAssertTrue(text.observations.isEmpty)
        XCTAssertTrue(text.isEmpty)
    }

    func testUnknownObservationKindDegradesToSteadyInsteadOfFailing() throws {
        let json = Data(#"{"headline":"Итоги","observations":[{"text":"Расходы выросли","kind":"spike"}]}"#.utf8)
        let text = try JSONDecoder().decode(AIPeriodSummaryText.self, from: json)
        XCTAssertEqual(text.headline, "Итоги")
        XCTAssertEqual(text.observations.first?.kind, .steady)
        XCTAssertFalse(text.isEmpty)
    }

    func testBlankHeadlineIsTreatedAsAbsent() throws {
        let json = Data(#"{"headline":"   ","observations":[]}"#.utf8)
        let text = try JSONDecoder().decode(AIPeriodSummaryText.self, from: json)
        XCTAssertNil(text.headline)
        XCTAssertTrue(text.isEmpty)
    }

    // MARK: - Helpers

    private func makeSampleRequest() -> AIPeriodSummaryRequest {
        AIPeriodSummaryPayloadBuilder.makeRequest(
            period: AIPeriodSummaryPeriod(kind: .month, anchor: date(2026, 9, 10)),
            now: date(2026, 9, 10),
            figures: AIPeriodFigures(income: 12_000, expense: 5_000, previousIncome: 7_000, previousExpense: 1_000, balanceEnd: 250_000),
            categoryTotals: ["Продукты": 3_500, "Транспорт": 1_500],
            currency: "RUB",
            locale: Locale(identifier: "ru_RU"),
            calendar: calendar
        )
    }
}
