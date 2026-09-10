//
//  AIChatViewModel.swift
//  millio
//

import Combine
import Foundation

/// Почему ответа нет. Разделено по действию пользователя: повторять есть смысл не всегда.
enum AIChatFailure: Equatable {
    /// Модель не подключена на сервере — повтор ничего не изменит.
    case unavailable
    /// Обрыв связи или сбой генерации — повтор уместен.
    case network
    /// Лимит запросов в минуту.
    case rateLimited
}

/// Диалог по агрегатам. Цифры берутся из локального среза и в ответе не пересчитываются —
/// модель отдаёт только текст.
@MainActor
final class AIChatViewModel: ObservableObject {
    @Published private(set) var messages: [AIChatMessage] = []
    /// Текст, который печатается прямо сейчас. В историю не попадает до финала — иначе обрыв
    /// оставлял бы «призрак» недописанного ответа.
    @Published private(set) var pendingAnswer: String?
    @Published private(set) var isSending = false
    @Published private(set) var failure: AIChatFailure?
    @Published private(set) var snapshot: AIChatContextSnapshot = .empty
    @Published var draft: String = ""

    private let contextProvider: @MainActor () async -> AIChatContextSnapshot
    private let client: any AIChatClient
    private let store: AIChatHistoryStore
    private let now: () -> Date
    private let calendar: Calendar
    private let locale: () -> Locale

    private var sendTask: Task<Void, Never>?
    /// Вопрос, оставшийся без ответа: по нему работает «Повторить», не дублируя реплику в ленте.
    private var retryQuestion: String?

    var canSend: Bool {
        !isSending && !AIChatPayloadBuilder.normalizedQuestion(draft).isEmpty
    }

    /// Повтор предлагаем только там, где он может помочь: при `unavailable` модель не подключена.
    var canRetry: Bool {
        guard retryQuestion != nil else { return false }
        switch failure {
        case .network, .rateLimited: return true
        case .unavailable, nil: return false
        }
    }

    var isEmpty: Bool { messages.isEmpty && pendingAnswer == nil }

    init(
        contextProvider: @escaping @MainActor () async -> AIChatContextSnapshot,
        client: any AIChatClient,
        store: AIChatHistoryStore = AIChatHistoryStore(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        locale: @escaping () -> Locale = { AppLocalization.currentAppLocale }
    ) {
        self.contextProvider = contextProvider
        self.client = client
        self.store = store
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.messages = store.load()
    }

    // MARK: - Действия

    /// Подтягивает свежий срез, ничего не спрашивая: экран показывает цифры сразу при открытии.
    func prepare() async {
        snapshot = await contextProvider()
    }

    func send(_ question: String) {
        let normalized = AIChatPayloadBuilder.normalizedQuestion(question)
        guard !normalized.isEmpty, !isSending else { return }

        draft = ""
        failure = nil
        retryQuestion = nil

        sendTask?.cancel()
        sendTask = Task { [weak self] in
            await self?.ask(normalized, appendQuestion: true)
        }
    }

    func retry() {
        guard let question = retryQuestion, !isSending else { return }
        failure = nil
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            await self?.ask(question, appendQuestion: false)
        }
    }

    /// Остановка генерации: недописанный текст выбрасываем, вопрос остаётся в ленте.
    /// Без гейта по `isSending`: экран, закрытый ещё до старта запроса (срез считается async),
    /// тоже обязан его отменить.
    func stopGenerating() {
        sendTask?.cancel()
        sendTask = nil
        pendingAnswer = nil
        isSending = false
    }

    func clearHistory() {
        sendTask?.cancel()
        sendTask = nil
        pendingAnswer = nil
        isSending = false
        failure = nil
        retryQuestion = nil
        messages = []
        store.clear()
    }

    // MARK: - Запрос

    private func ask(_ question: String, appendQuestion: Bool) async {
        snapshot = await contextProvider()
        // Экран закрыли, пока считался срез: вопрос не уходит вовсе.
        guard !Task.isCancelled else { return }
        let signature = AIChatPayloadBuilder.contextSignature(
            snapshot: snapshot,
            locale: locale(),
            now: now(),
            calendar: calendar
        )

        if appendQuestion {
            appendMessage(AIChatMessage(role: .user, text: question, date: now()))
        }

        // Тот же вопрос на тех же цифрах — ответ уже есть в истории: отдаём мгновенно,
        // без сети и без имитации печати.
        if let cached = cachedAnswer(for: question, signature: signature) {
            appendMessage(AIChatMessage(role: .assistant, text: cached, date: now(), contextSignature: signature))
            return
        }

        guard client.isAvailable else {
            retryQuestion = question
            failure = .unavailable
            return
        }

        // Сам вопрос уже лежит последней репликой — в `history` его не дублируем,
        // он уходит отдельным полем `question`.
        var history = messages
        if let last = history.last, last.role == .user, last.text == question { history.removeLast() }

        let request = AIChatPayloadBuilder.makeRequest(
            question: question,
            history: history,
            snapshot: snapshot,
            locale: locale(),
            now: now(),
            calendar: calendar
        )

        isSending = true
        pendingAnswer = ""
        defer { isSending = false }

        var finished = false
        do {
            for try await event in client.stream(request) {
                if Task.isCancelled { return }
                switch event {
                case .delta(let chunk):
                    pendingAnswer = (pendingAnswer ?? "") + chunk
                case .done(let reply):
                    finished = true
                    finalize(reply, question: question, signature: signature)
                }
            }
        } catch {
            if Task.isCancelled { return }
            pendingAnswer = nil
            retryQuestion = question
            failure = map(error)
            return
        }

        if Task.isCancelled { return }
        guard finished else {
            // Поток закрылся без финального события — считаем это обрывом, а не пустым ответом.
            pendingAnswer = nil
            retryQuestion = question
            failure = .network
            return
        }
    }

    private func finalize(_ reply: AIChatReply, question: String, signature: String) {
        // Финал несёт полный текст; накопленные куски — страховка на случай, если он пуст.
        let text = (reply.reply?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? pendingAnswer?.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingAnswer = nil

        switch reply.status {
        case .ok:
            guard let text, !text.isEmpty else {
                retryQuestion = question
                failure = .network
                return
            }
            appendMessage(AIChatMessage(role: .assistant, text: text, date: now(), contextSignature: signature))
            retryQuestion = nil
            failure = nil
        case .unavailable:
            retryQuestion = question
            failure = .unavailable
        case .failed:
            retryQuestion = question
            failure = .network
        }
    }

    private func map(_ error: Error) -> AIChatFailure {
        switch error {
        case AIChatClientError.rateLimited: return .rateLimited
        case AIChatClientError.unavailable: return .unavailable
        default: return .network
        }
    }

    // MARK: - История

    private func appendMessage(_ message: AIChatMessage) {
        messages.append(message)
        messages = Array(messages.suffix(AIChatPayloadBuilder.maxHistoryMessages))
        store.save(messages)
    }

    /// Ответ на тот же вопрос, полученный на тех же цифрах. Подпись обязательна: без неё повтор
    /// вопроса в следующем месяце вернул бы прошлые суммы.
    private func cachedAnswer(for question: String, signature: String) -> String? {
        let key = AIChatPayloadBuilder.questionKey(question)
        for index in messages.indices.reversed() {
            let message = messages[index]
            guard message.role == .assistant, message.contextSignature == signature else { continue }
            let previous = index > 0 ? messages[index - 1] : nil
            guard
                let previous,
                previous.role == .user,
                AIChatPayloadBuilder.questionKey(previous.text) == key
            else { continue }
            return message.text
        }
        return nil
    }
}
