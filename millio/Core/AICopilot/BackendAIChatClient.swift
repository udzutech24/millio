//
//  BackendAIChatClient.swift
//  millio
//

import Foundation

/// `POST /ai/chat` с Bearer-токеном и одним повтором при 401 — по образцу
/// `BackendAIPeriodSummaryClient`. Отличие одно: ответ читается потоком (`URLSession.bytes`),
/// чтобы текст печатался по мере генерации, а не появлялся целиком через несколько секунд.
final class BackendAIChatClient: AIChatClient, @unchecked Sendable {
    private let authService: any AuthServiceProtocol
    private let configurationProvider: @Sendable () throws -> AuthConfiguration
    private let session: URLSession
    private let maxResponseBytes: Int
    private let timeout: TimeInterval

    var isAvailable: Bool { true }

    init(
        authService: any AuthServiceProtocol,
        configurationProvider: @escaping @Sendable () throws -> AuthConfiguration,
        session: URLSession = .shared,
        maxResponseBytes: Int = 256 * 1_024,
        // Генерация ответа длиннее обычного запроса: 20 с (таймаут итогов) обрывали бы её на полуслове.
        timeout: TimeInterval = 60
    ) {
        self.authService = authService
        self.configurationProvider = configurationProvider
        self.session = session
        self.maxResponseBytes = maxResponseBytes
        self.timeout = timeout
    }

    func stream(_ request: AIChatRequest) -> AsyncThrowingStream<AIChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    do {
                        try await perform(request, forceRefresh: false, into: continuation)
                    } catch AIChatClientError.unauthorized {
                        // 401 виден до первого байта тела, поэтому повтор не может задвоить текст.
                        try await perform(request, forceRefresh: true, into: continuation)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func perform(
        _ payload: AIChatRequest,
        forceRefresh: Bool,
        into continuation: AsyncThrowingStream<AIChatEvent, Error>.Continuation
    ) async throws {
        let configuration = try configurationProvider()
        let url = configuration.baseURL.appending(path: "ai/chat")
        let token = try await authService.accessToken(forceRefresh: forceRefresh)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(payload)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw AIChatClientError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw AIChatClientError.transport }
        switch http.statusCode {
        case 200: break
        case 401: throw AIChatClientError.unauthorized
        case 429: throw AIChatClientError.rateLimited
        case 400, 422: throw AIChatClientError.invalidContract
        default: throw AIChatClientError.unavailable
        }

        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        guard contentType.contains("text/event-stream") else {
            // Прокси перед бэкендом может отдать ответ целиком одним JSON. Ответ при этом валиден —
            // терять его из-за пропавшего стриминга нельзя, просто печати по токенам не будет.
            try await yieldWholeBody(bytes, into: continuation)
            return
        }

        var parser = AIChatSSEParser()
        var receivedDone = false
        var received = 0
        var lineBuffer: [UInt8] = []

        func deliver(_ frame: AIChatSSEParser.Frame?) {
            guard let frame, let event = AIChatSSEParser.event(from: frame) else { return }
            continuation.yield(event)
            if case .done = event { receivedDone = true }
        }

        do {
            // Строки режем сами, а не через `bytes.lines`: та проглатывает пустые строки, а в SSE
            // пустая строка и есть граница кадра. Кадры слипались в один — печать по токенам
            // пропадала, финал не разбирался, и каждый ответ выглядел как сбой.
            // Байт `\n` не встречается внутри многобайтовых UTF-8 символов, поэтому резать по нему безопасно.
            for try await byte in bytes {
                received += 1
                guard received <= maxResponseBytes else { throw AIChatClientError.invalidContract }
                guard byte == UInt8(ascii: "\n") else {
                    lineBuffer.append(byte)
                    continue
                }
                try Task.checkCancellation()
                deliver(parser.consume(line: String(decoding: lineBuffer, as: UTF8.self)))
                lineBuffer.removeAll(keepingCapacity: true)
            }
        } catch let error as AIChatClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AIChatClientError.transport
        }

        if !lineBuffer.isEmpty {
            deliver(parser.consume(line: String(decoding: lineBuffer, as: UTF8.self)))
        }
        deliver(parser.flush())

        // Поток кончился без финала — соединение оборвалось. Частичный текст наверх уже ушёл,
        // но экран обязан узнать про обрыв и не оставить его в истории.
        guard receivedDone else { throw AIChatClientError.transport }
    }

    private func yieldWholeBody(
        _ bytes: URLSession.AsyncBytes,
        into continuation: AsyncThrowingStream<AIChatEvent, Error>.Continuation
    ) async throws {
        var body = Data()
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                body.append(byte)
                guard body.count <= maxResponseBytes else { throw AIChatClientError.invalidContract }
            }
        } catch let error as AIChatClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AIChatClientError.transport
        }

        guard let reply = try? JSONDecoder().decode(AIChatReply.self, from: body) else {
            throw AIChatClientError.invalidContract
        }
        continuation.yield(.done(reply))
    }
}
