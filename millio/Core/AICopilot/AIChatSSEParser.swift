//
//  AIChatSSEParser.swift
//  millio
//

import Foundation

/// Разбор потока `text/event-stream` построчно. Отдельный чистый тип, потому что сеть проверить
/// тестом дорого, а формат кадра — дёшево: именно здесь ломается печать по мере генерации.
struct AIChatSSEParser {
    /// Готовый кадр: имя события и склеенные строки `data:`.
    struct Frame: Equatable {
        let event: String
        let data: String
    }

    private var event: String?
    private var dataLines: [String] = []

    /// Кадр возвращается только на пустой строке — она и есть разделитель кадров в SSE.
    mutating func consume(line rawLine: String) -> Frame? {
        // URLSession режет поток по `\n`, а сервер шлёт `\r\n` — иначе `\r` уедет в текст ответа.
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine

        if line.isEmpty { return flush() }
        // Комментарий-heartbeat: держит соединение живым и данных не несёт.
        if line.hasPrefix(":") { return nil }

        guard let separator = line.firstIndex(of: ":") else { return nil }
        let field = String(line[line.startIndex..<separator])
        var value = String(line[line.index(after: separator)...])
        // По спецификации один ведущий пробел после двоеточия — часть разделителя, а не данных.
        if value.hasPrefix(" ") { value.removeFirst() }

        switch field {
        case "event": event = value
        case "data": dataLines.append(value)
        default: break
        }
        return nil
    }

    /// Закрывает незавершённый кадр в конце потока.
    mutating func flush() -> Frame? {
        defer {
            event = nil
            dataLines = []
        }
        guard let event, !dataLines.isEmpty else { return nil }
        return Frame(event: event, data: dataLines.joined(separator: "\n"))
    }

    /// Кадр → событие чата. Незнакомое событие и битый JSON пропускаем: одна кривая строка
    /// не должна ронять весь ответ.
    static func event(from frame: Frame) -> AIChatEvent? {
        guard let data = frame.data.data(using: .utf8) else { return nil }

        switch frame.event {
        case "delta":
            guard let chunk = try? JSONDecoder().decode(Delta.self, from: data), !chunk.text.isEmpty else { return nil }
            return .delta(chunk.text)
        case "done":
            guard let reply = try? JSONDecoder().decode(AIChatReply.self, from: data) else { return nil }
            return .done(reply)
        default:
            return nil
        }
    }

    private struct Delta: Decodable {
        let text: String
    }
}
