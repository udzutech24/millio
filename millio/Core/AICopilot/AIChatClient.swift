//
//  AIChatClient.swift
//  millio
//

import Foundation

/// Диалог по уже посчитанным агрегатам. Цифры считает приложение — клиент отдаёт готовый срез
/// и получает обратно только текст, кусками по мере генерации.
protocol AIChatClient: Sendable {
    var isAvailable: Bool { get }
    func stream(_ request: AIChatRequest) -> AsyncThrowingStream<AIChatEvent, Error>
}

/// Заглушка, когда DI-контейнера нет. Экран обязан сказать «сейчас недоступно», а не крутить
/// спиннер вечно — поэтому финал отдаётся сразу, а не через ошибку.
struct UnavailableAIChatClient: AIChatClient {
    var isAvailable: Bool { false }

    func stream(_ request: AIChatRequest) -> AsyncThrowingStream<AIChatEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.done(AIChatReply(reply: nil, status: .unavailable)))
            continuation.finish()
        }
    }
}
