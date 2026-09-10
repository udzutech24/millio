import Foundation
import XCTest
@testable import millio

/// Контракт `POST /ai/chat`: бэкенд с `forbidNonWhitelisted` отвечает 400 на любое лишнее поле,
/// а цифры обязаны уходить ровно такими, какими их посчитало приложение.
final class AIChatPayloadBuilderTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))! }

    private func snapshot(
        income: Double = 120_000.456,
        expense: Double = 80_000.004,
        categories: [String: Double] = ["Продукты": 30_000, "Кафе": 12_000, "Пусто": 0.2]
    ) -> AIChatContextSnapshot {
        AIChatContextSnapshot(
            period: AIPeriodSummaryPeriod(kind: .month, anchor: now),
            figures: AIPeriodFigures(
                income: income,
                expense: expense,
                previousIncome: 1,
                previousExpense: 2,
                balanceEnd: 500_000
            ),
            currency: "RUB",
            categoryTotals: categories
        )
    }

    private func json(_ request: AIChatRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Белый список полей

    func testEncodedKeysMatchBackendWhitelistExactly() throws {
        let history = [
            AIChatMessage(role: .user, text: "Привет"),
            AIChatMessage(role: .assistant, text: "Здравствуйте", contextSignature: "sig")
        ]
        let request = AIChatPayloadBuilder.makeRequest(
            question: "На что ушло больше всего?",
            history: history,
            snapshot: snapshot(),
            locale: Locale(identifier: "ru_RU"),
            now: now,
            calendar: calendar
        )
        let root = try json(request)

        XCTAssertEqual(Set(root.keys), ["schemaVersion", "locale", "question", "history", "context"])

        let context = try XCTUnwrap(root["context"] as? [String: Any])
        // `accounts` не шлём намеренно — ни пустым массивом, ни null.
        XCTAssertEqual(Set(context.keys), ["period", "currency", "totals", "byCategory"])

        let period = try XCTUnwrap(context["period"] as? [String: Any])
        XCTAssertEqual(Set(period.keys), ["kind", "start", "end"])

        let totals = try XCTUnwrap(context["totals"] as? [String: Any])
        XCTAssertEqual(Set(totals.keys), ["income", "expense", "net", "balanceEnd"])

        let category = try XCTUnwrap((context["byCategory"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(category.keys), ["categoryId", "amount"])

        let turn = try XCTUnwrap((root["history"] as? [[String: Any]])?.first)
        // Подпись контекста — локальная память устройства, на сервер она уходить не должна.
        XCTAssertEqual(Set(turn.keys), ["role", "text"])
    }

    func testEmptyHistoryIsOmittedInsteadOfNull() throws {
        let request = AIChatPayloadBuilder.makeRequest(
            question: "Вопрос",
            history: [],
            snapshot: snapshot(),
            locale: Locale(identifier: "ru_RU"),
            now: now,
            calendar: calendar
        )
        XCTAssertNil(try json(request)["history"])
    }

    // MARK: - Цифры не пересчитываются

    func testContextCarriesLocalNumbersRoundedToCents() {
        let request = AIChatPayloadBuilder.makeRequest(
            question: "Вопрос",
            history: [],
            snapshot: snapshot(),
            locale: Locale(identifier: "ru_RU"),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(request.context.totals.income, 120_000.46)
        XCTAssertEqual(request.context.totals.expense, 80_000)
        XCTAssertEqual(request.context.totals.net, 40_000.45)
        XCTAssertEqual(request.context.totals.balanceEnd, 500_000)
        XCTAssertEqual(request.context.currency, "RUB")
        XCTAssertEqual(request.context.period.kind, "month")
        XCTAssertEqual(request.context.period.start, "2026-09-01")
        XCTAssertEqual(request.context.period.end, "2026-09-10")
    }

    func testCategoriesAreSortedAndZeroTailDropped() {
        let request = AIChatPayloadBuilder.makeRequest(
            question: "Вопрос",
            history: [],
            snapshot: snapshot(),
            locale: Locale(identifier: "ru_RU"),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(request.context.byCategory.map(\.categoryId), ["Продукты", "Кафе"])
    }

    // MARK: - Границы DTO

    func testQuestionIsTrimmedAndCappedAt1000Characters() {
        XCTAssertEqual(AIChatPayloadBuilder.normalizedQuestion("  Вопрос \n"), "Вопрос")
        let long = String(repeating: "я", count: 1_500)
        XCTAssertEqual(AIChatPayloadBuilder.normalizedQuestion(long).count, 1_000)
    }

    func testHistoryKeepsLast20TurnsAndCapsTurnText() {
        var messages: [AIChatMessage] = []
        for index in 0..<30 {
            messages.append(AIChatMessage(role: index.isMultiple(of: 2) ? .user : .assistant, text: "m\(index)"))
        }
        messages.append(AIChatMessage(role: .user, text: String(repeating: "x", count: 5_000)))

        let trimmed = AIChatPayloadBuilder.trimmedHistory(messages)

        XCTAssertEqual(trimmed.count, 20)
        XCTAssertEqual(trimmed.first?.text, "m11")
        XCTAssertEqual(trimmed.last?.text.count, 4_000)
    }

    func testUnsupportedAppLanguageFallsBackToEnglish() {
        let request = AIChatPayloadBuilder.makeRequest(
            question: "Frage",
            history: [],
            snapshot: snapshot(),
            locale: Locale(identifier: "de_DE"),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(request.locale, "en")
    }

    // MARK: - Повтор вопроса

    func testQuestionKeyIgnoresCaseAndExtraSpaces() {
        XCTAssertEqual(
            AIChatPayloadBuilder.questionKey("  На что  ушло\nбольше всего? "),
            AIChatPayloadBuilder.questionKey("на что ушло больше всего?")
        )
    }

    func testContextSignatureChangesWhenNumbersChange() {
        let locale = Locale(identifier: "ru_RU")
        let base = AIChatPayloadBuilder.contextSignature(snapshot: snapshot(), locale: locale, now: now, calendar: calendar)
        let same = AIChatPayloadBuilder.contextSignature(snapshot: snapshot(), locale: locale, now: now, calendar: calendar)
        let changed = AIChatPayloadBuilder.contextSignature(
            snapshot: snapshot(expense: 90_000),
            locale: locale,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(base, same)
        XCTAssertNotEqual(base, changed)
    }
}
