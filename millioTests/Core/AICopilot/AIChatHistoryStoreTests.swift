import Foundation
import XCTest
@testable import millio

/// История живёт на устройстве, сервер ничего не помнит — обрезка и изоляция по scope на клиенте.
final class AIChatHistoryStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ai.chat.history.tests.\(UUID().uuidString)")!
    }

    func testRoundTripKeepsOrderAndSignature() {
        let store = AIChatHistoryStore(defaults: makeDefaults(), storageKey: "k")
        let messages = [
            AIChatMessage(role: .user, text: "Вопрос"),
            AIChatMessage(role: .assistant, text: "Ответ", contextSignature: "sig")
        ]
        store.save(messages)
        XCTAssertEqual(store.load(), messages)
    }

    func testKeepsOnlyLast20Turns() {
        let store = AIChatHistoryStore(defaults: makeDefaults(), storageKey: "k")
        let messages = (0..<30).map { AIChatMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, text: "m\($0)") }
        store.save(messages)

        let loaded = store.load()
        XCTAssertLessThanOrEqual(loaded.count, 20)
        XCTAssertEqual(loaded.last?.text, "m29")
    }

    func testDanglingAnswerAtHeadIsDropped() {
        let store = AIChatHistoryStore(defaults: makeDefaults(), storageKey: "k", capacity: 3)
        store.save([
            AIChatMessage(role: .user, text: "q1"),
            AIChatMessage(role: .assistant, text: "a1"),
            AIChatMessage(role: .user, text: "q2"),
            AIChatMessage(role: .assistant, text: "a2")
        ])
        // suffix(3) = [a1, q2, a2] — ответ без вопроса в начале отбрасывается.
        XCTAssertEqual(store.load().map(\.text), ["q2", "a2"])
    }

    func testScopesDoNotSeeEachOther() {
        let defaults = makeDefaults()
        let owner = AIChatHistoryStore(defaults: defaults, storageKey: AIChatHistoryStore.storageKey(forScopeKey: "millio_user_abc"))
        let guest = AIChatHistoryStore(defaults: defaults, storageKey: AIChatHistoryStore.storageKey(forScopeKey: "millio_guest"))

        owner.save([AIChatMessage(role: .user, text: "личное")])

        XCTAssertTrue(guest.load().isEmpty)
        XCTAssertEqual(owner.load().count, 1)
    }

    func testClearRemovesEverything() {
        let store = AIChatHistoryStore(defaults: makeDefaults(), storageKey: "k")
        store.save([AIChatMessage(role: .user, text: "q")])
        store.clear()
        XCTAssertTrue(store.load().isEmpty)
    }

    func testCorruptedPayloadLoadsAsEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data("garbage".utf8), forKey: "k")
        XCTAssertTrue(AIChatHistoryStore(defaults: defaults, storageKey: "k").load().isEmpty)
    }
}
