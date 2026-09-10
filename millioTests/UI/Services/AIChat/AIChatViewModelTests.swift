import Foundation
import XCTest
@testable import millio

/// Поведение экрана чата без сервера и на обрывах: эндпоинт на момент фазы не задеплоен,
/// поэтому «сейчас недоступно» и отсутствие «призраков» важнее счастливого пути.
@MainActor
final class AIChatViewModelTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))! }

    // MARK: - Стабы

    /// Сценарий потока, отданный заранее: удобно для финальных состояний.
    private final class ScriptedClient: AIChatClient, @unchecked Sendable {
        enum Step {
            case delta(String)
            case done(AIChatReply)
            case fail(Error)
        }

        var isAvailable: Bool
        var script: [Step]
        private(set) var requests: [AIChatRequest] = []

        init(isAvailable: Bool = true, script: [Step]) {
            self.isAvailable = isAvailable
            self.script = script
        }

        func stream(_ request: AIChatRequest) -> AsyncThrowingStream<AIChatEvent, Error> {
            requests.append(request)
            let steps = script
            return AsyncThrowingStream { continuation in
                for step in steps {
                    switch step {
                    case .delta(let text): continuation.yield(.delta(text))
                    case .done(let reply): continuation.yield(.done(reply))
                    case .fail(let error):
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Поток под ручным управлением: проверяем, что текст виден ДО финала.
    private final class ControlledClient: AIChatClient, @unchecked Sendable {
        var isAvailable: Bool { true }
        private(set) var continuation: AsyncThrowingStream<AIChatEvent, Error>.Continuation?

        func stream(_ request: AIChatRequest) -> AsyncThrowingStream<AIChatEvent, Error> {
            AsyncThrowingStream { continuation in self.continuation = continuation }
        }
    }

    private final class FiguresBox {
        var figures = AIPeriodFigures(income: 100_000, expense: 60_000, previousIncome: 0, previousExpense: 0, balanceEnd: 300_000)
    }

    private func makeStore(_ defaults: UserDefaults? = nil) -> AIChatHistoryStore {
        AIChatHistoryStore(
            defaults: defaults ?? UserDefaults(suiteName: "ai.chat.vm.tests.\(UUID().uuidString)")!,
            storageKey: "test.history"
        )
    }

    private func makeViewModel(
        client: any AIChatClient,
        store: AIChatHistoryStore? = nil,
        box: FiguresBox = FiguresBox()
    ) -> AIChatViewModel {
        let period = AIPeriodSummaryPeriod(kind: .month, anchor: now)
        return AIChatViewModel(
            contextProvider: {
                AIChatContextSnapshot(period: period, figures: box.figures, currency: "RUB", categoryTotals: ["Продукты": 20_000])
            },
            client: client,
            store: store ?? makeStore(),
            now: { [now] in now },
            calendar: calendar,
            locale: { Locale(identifier: "ru_RU") }
        )
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private let okReply = AIChatReply(reply: "Больше всего — продукты.", status: .ok)

    // MARK: - Печать по мере генерации

    func testStreamedTextIsVisibleBeforeDoneAndCommittedOnlyAfter() async {
        let client = ControlledClient()
        let store = makeStore()
        let vm = makeViewModel(client: client, store: store)

        vm.send("На что ушло больше всего?")
        await waitUntil { client.continuation != nil }

        client.continuation?.yield(.delta("Больше всего"))
        await waitUntil { vm.pendingAnswer == "Больше всего" }

        XCTAssertEqual(vm.pendingAnswer, "Больше всего")
        XCTAssertTrue(vm.isSending)
        XCTAssertEqual(vm.messages.map(\.role), [.user], "Частичный текст не должен попадать в историю")

        client.continuation?.yield(.delta(" — продукты."))
        client.continuation?.yield(.done(okReply))
        client.continuation?.finish()
        await waitUntil { vm.messages.count == 2 }

        XCTAssertNil(vm.pendingAnswer)
        XCTAssertFalse(vm.isSending)
        XCTAssertEqual(vm.messages.last?.text, "Больше всего — продукты.")
        XCTAssertEqual(store.load().count, 2, "Готовый ответ сохраняется на устройстве")
    }

    // MARK: - Мгновенный повтор

    func testRepeatedQuestionOnSameNumbersIsAnsweredFromHistoryWithoutNetwork() async {
        let client = ScriptedClient(script: [.done(okReply)])
        let vm = makeViewModel(client: client)

        vm.send("На что ушло больше всего?")
        await waitUntil { vm.messages.count == 2 }

        vm.send("  на что ушло   больше всего? ")
        await waitUntil { vm.messages.count == 4 }

        XCTAssertEqual(client.requests.count, 1, "Повтор не должен ходить в сеть")
        XCTAssertEqual(vm.messages.last?.text, okReply.reply)
        XCTAssertNil(vm.pendingAnswer, "Готовый ответ показывается сразу, без печати")
    }

    func testRepeatedQuestionAfterNumbersChangedGoesToNetworkAgain() async {
        let client = ScriptedClient(script: [.done(okReply)])
        let box = FiguresBox()
        let vm = makeViewModel(client: client, box: box)

        vm.send("На что ушло больше всего?")
        await waitUntil { vm.messages.count == 2 }

        box.figures = AIPeriodFigures(income: 100_000, expense: 75_000, previousIncome: 0, previousExpense: 0, balanceEnd: 285_000)
        vm.send("На что ушло больше всего?")
        await waitUntil { vm.messages.count == 4 }

        XCTAssertEqual(client.requests.count, 2, "Прошлый ответ на старые цифры переиспользовать нельзя")
    }

    func testHistorySurvivesRelaunch() async {
        let defaults = UserDefaults(suiteName: "ai.chat.vm.relaunch.\(UUID().uuidString)")!
        let client = ScriptedClient(script: [.done(okReply)])
        let first = makeViewModel(client: client, store: makeStore(defaults))

        first.send("На что ушло больше всего?")
        await waitUntil { first.messages.count == 2 }

        let second = makeViewModel(client: client, store: makeStore(defaults))
        XCTAssertEqual(second.messages.count, 2)

        second.send("На что ушло больше всего?")
        await waitUntil { second.messages.count == 4 }
        XCTAssertEqual(client.requests.count, 1, "После перезапуска повтор тоже берётся из истории")
    }

    // MARK: - Обрывы: без «призраков»

    func testConnectionDropMidAnswerLeavesNoGhostMessage() async {
        let client = ScriptedClient(script: [.delta("Больше в"), .fail(AIChatClientError.transport)])
        let store = makeStore()
        let vm = makeViewModel(client: client, store: store)

        vm.send("На что ушло больше всего?")
        await waitUntil { vm.failure != nil }

        XCTAssertEqual(vm.failure, .network)
        XCTAssertNil(vm.pendingAnswer)
        XCTAssertFalse(vm.isSending)
        XCTAssertEqual(vm.messages.map(\.role), [.user])
        XCTAssertEqual(store.load().map(\.role), [.user], "Недописанный ответ не сохраняется")
        XCTAssertTrue(vm.canRetry)
    }

    func testStreamEndingWithoutDoneIsTreatedAsDrop() async {
        let client = ScriptedClient(script: [.delta("Больше")])
        let vm = makeViewModel(client: client)

        vm.send("Вопрос")
        await waitUntil { vm.failure != nil }

        XCTAssertEqual(vm.failure, .network)
        XCTAssertEqual(vm.messages.map(\.role), [.user])
    }

    func testRetryDoesNotDuplicateQuestion() async {
        let client = ScriptedClient(script: [.fail(AIChatClientError.transport)])
        let vm = makeViewModel(client: client)

        vm.send("Вопрос")
        await waitUntil { vm.failure != nil }

        client.script = [.done(okReply)]
        vm.retry()
        await waitUntil { vm.messages.count == 2 }

        XCTAssertEqual(vm.messages.map(\.role), [.user, .assistant])
        XCTAssertNil(vm.failure)
        XCTAssertFalse(vm.canRetry)
    }

    func testStopDiscardsPartialAnswer() async {
        let client = ControlledClient()
        let vm = makeViewModel(client: client)

        vm.send("Вопрос")
        await waitUntil { client.continuation != nil }
        client.continuation?.yield(.delta("Част"))
        await waitUntil { vm.pendingAnswer == "Част" }

        vm.stopGenerating()

        XCTAssertNil(vm.pendingAnswer)
        XCTAssertFalse(vm.isSending)
        XCTAssertEqual(vm.messages.map(\.role), [.user])
    }

    // MARK: - Сервер недоступен

    func testUnavailableClientExplainsWithoutSpinnerOrNetwork() async {
        let client = ScriptedClient(isAvailable: false, script: [])
        let vm = makeViewModel(client: client)

        vm.send("Вопрос")
        await waitUntil { vm.failure != nil }

        XCTAssertEqual(vm.failure, .unavailable)
        XCTAssertFalse(vm.isSending)
        XCTAssertNil(vm.pendingAnswer)
        XCTAssertFalse(vm.canRetry, "Повтор без подключённой модели ничего не изменит")
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testServerReportingUnavailableIsNotRetryable() async {
        let client = ScriptedClient(script: [.done(AIChatReply(reply: nil, status: .unavailable))])
        let vm = makeViewModel(client: client)

        vm.send("Вопрос")
        await waitUntil { vm.failure != nil }

        XCTAssertEqual(vm.failure, .unavailable)
        XCTAssertFalse(vm.canRetry)
        XCTAssertEqual(vm.messages.map(\.role), [.user])
    }

    func testServerFailedStatusOffersRetry() async {
        let client = ScriptedClient(script: [.delta("x"), .done(AIChatReply(reply: nil, status: .failed))])
        let vm = makeViewModel(client: client)

        vm.send("Вопрос")
        await waitUntil { vm.failure != nil }

        XCTAssertEqual(vm.failure, .network)
        XCTAssertTrue(vm.canRetry)
        XCTAssertEqual(vm.messages.map(\.role), [.user])
    }

    func testRateLimitIsRetryable() async {
        let client = ScriptedClient(script: [.fail(AIChatClientError.rateLimited)])
        let vm = makeViewModel(client: client)

        vm.send("Вопрос")
        await waitUntil { vm.failure != nil }

        XCTAssertEqual(vm.failure, .rateLimited)
        XCTAssertTrue(vm.canRetry)
    }

    // MARK: - Запрос

    func testRequestUsesLocalNumbersAndExcludesCurrentQuestionFromHistory() async {
        let client = ScriptedClient(script: [.done(okReply)])
        let vm = makeViewModel(client: client)

        vm.send("Первый")
        await waitUntil { vm.messages.count == 2 }
        vm.send("Второй")
        await waitUntil { vm.messages.count == 4 }

        let request = try? XCTUnwrap(client.requests.last)
        XCTAssertEqual(request?.question, "Второй")
        XCTAssertEqual(request?.history?.map(\.text), ["Первый", "Больше всего — продукты."])
        XCTAssertEqual(request?.context.totals.income, 100_000)
        XCTAssertEqual(request?.context.totals.expense, 60_000)
        XCTAssertEqual(request?.context.totals.net, 40_000)
    }

    func testHistorySentNeverExceeds20Turns() async {
        let store = makeStore()
        store.save((0..<20).map { AIChatMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, text: "m\($0)") })
        let client = ScriptedClient(script: [.done(okReply)])
        let vm = makeViewModel(client: client, store: store)

        vm.send("Новый")
        await waitUntil { !client.requests.isEmpty && !vm.isSending }

        let history = client.requests.first?.history ?? []
        XCTAssertLessThanOrEqual(history.count, 20)
        XCTAssertFalse(history.contains { $0.text == "Новый" })
    }

    func testBlankQuestionIsIgnored() async {
        let client = ScriptedClient(script: [.done(okReply)])
        let vm = makeViewModel(client: client)

        vm.draft = "   \n"
        XCTAssertFalse(vm.canSend)
        vm.send(vm.draft)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testClearHistoryWipesDeviceStore() async {
        let store = makeStore()
        let client = ScriptedClient(script: [.done(okReply)])
        let vm = makeViewModel(client: client, store: store)

        vm.send("Вопрос")
        await waitUntil { vm.messages.count == 2 }
        vm.clearHistory()

        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testPrepareShowsNumbersBeforeAnyQuestion() async {
        let vm = makeViewModel(client: ScriptedClient(isAvailable: false, script: []))
        await vm.prepare()

        XCTAssertEqual(vm.snapshot.figures.income, 100_000)
        XCTAssertTrue(vm.isEmpty)
        XCTAssertNil(vm.failure, "Открытие экрана без сервера не должно показывать ошибку")
    }
}
