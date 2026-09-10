import Foundation
import XCTest
@testable import millio

/// Формат кадров, который шлёт `chat.controller.ts`: `event: <type>\ndata: <json>\n\n`.
final class AIChatSSEParserTests: XCTestCase {
    private func events(from lines: [String]) -> [AIChatEvent] {
        var parser = AIChatSSEParser()
        var result: [AIChatEvent] = []
        for line in lines {
            if let frame = parser.consume(line: line), let event = AIChatSSEParser.event(from: frame) {
                result.append(event)
            }
        }
        if let frame = parser.flush(), let event = AIChatSSEParser.event(from: frame) {
            result.append(event)
        }
        return result
    }

    func testDeltaAndDoneFramesAreParsedInOrder() {
        let result = events(from: [
            "event: delta", "data: {\"text\":\"Больше \"}", "",
            "event: delta", "data: {\"text\":\"всего — продукты\"}", "",
            "event: done", "data: {\"reply\":\"Больше всего — продукты\",\"status\":\"ok\"}", ""
        ])

        XCTAssertEqual(result, [
            .delta("Больше "),
            .delta("всего — продукты"),
            .done(AIChatReply(reply: "Больше всего — продукты", status: .ok))
        ])
    }

    func testCarriageReturnFromCRLFDoesNotLeakIntoText() {
        let result = events(from: ["event: delta\r", "data: {\"text\":\"ok\"}\r", "\r"])
        XCTAssertEqual(result, [.delta("ok")])
    }

    func testHeartbeatCommentsAndUnknownEventsAreIgnored() {
        let result = events(from: [
            ": ping", "",
            "event: progress", "data: {\"text\":\"x\"}", "",
            "id: 7", "event: delta", "data: {\"text\":\"y\"}", ""
        ])
        XCTAssertEqual(result, [.delta("y")])
    }

    func testBrokenJSONFrameIsSkippedWithoutDroppingTheRest() {
        let result = events(from: [
            "event: delta", "data: {not json", "",
            "event: done", "data: {\"reply\":null,\"status\":\"failed\"}", ""
        ])
        XCTAssertEqual(result, [.done(AIChatReply(reply: nil, status: .failed))])
    }

    func testMultilineDataIsJoinedWithNewline() {
        var parser = AIChatSSEParser()
        _ = parser.consume(line: "event: delta")
        _ = parser.consume(line: "data: {\"text\":")
        _ = parser.consume(line: "data: \"a\"}")
        let frame = parser.consume(line: "")
        XCTAssertEqual(frame, AIChatSSEParser.Frame(event: "delta", data: "{\"text\":\n\"a\"}"))
    }

    func testUnterminatedLastFrameIsFlushedAtStreamEnd() {
        let result = events(from: ["event: done", "data: {\"reply\":\"Итог\",\"status\":\"ok\"}"])
        XCTAssertEqual(result, [.done(AIChatReply(reply: "Итог", status: .ok))])
    }

    func testUnknownStatusDegradesToFailed() {
        let result = events(from: ["event: done", "data: {\"reply\":\"x\",\"status\":\"weird\"}", ""])
        XCTAssertEqual(result, [.done(AIChatReply(reply: "x", status: .failed))])
    }

    /// `filtered`: сервер оборвал ответ на инвестиционной рекомендации и прислал отказ в `reply`.
    func testFilteredStatusCarriesRefusal() {
        let result = events(from: [
            "event: delta", "data: {\"text\":\"Купите облигации.\"}", "",
            "event: done", "data: {\"reply\":\"Я не даю инвестиционных рекомендаций.\",\"status\":\"filtered\"}", ""
        ])
        XCTAssertEqual(result, [
            .delta("Купите облигации."),
            .done(AIChatReply(reply: "Я не даю инвестиционных рекомендаций.", status: .filtered))
        ])
    }

    func testEmptyDeltaIsDropped() {
        XCTAssertTrue(events(from: ["event: delta", "data: {\"text\":\"\"}", ""]).isEmpty)
    }
}
