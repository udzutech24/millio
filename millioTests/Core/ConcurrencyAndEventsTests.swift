import Foundation
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct ConcurrencyAndEventsTests {
    @Test("EventBus доставляет событие подписчику")
    func testEventBusDeliversEventToSubscriber() {
        var received: AppEvent?
        let id = EventBus.shared.subscribe { event in
            received = event
        }
        defer { EventBus.shared.unsubscribe(id) }
        
        EventBus.shared.publish(BackupEvent.started)
        
        let event = received as? BackupEvent
        switch event {
        case .started:
            #expect(true)
        default:
            #expect(false)
        }
    }
    
    @Test("EventBus не доставляет события после unsubscribe")
    func testEventBusDoesNotDeliverAfterUnsubscribe() {
        var callCount = 0
        let id = EventBus.shared.subscribe { _ in
            callCount += 1
        }
        
        EventBus.shared.unsubscribe(id)
        EventBus.shared.publish(BackupEvent.started)
        
        #expect(callCount == 0)
    }
    
    @Test("EventBus доставляет событие нескольким подписчикам")
    func testEventBusDeliversToMultipleSubscribers() {
        var calls: Set<String> = []
        
        let id1 = EventBus.shared.subscribe { _ in
            calls.insert("a")
        }
        let id2 = EventBus.shared.subscribe { _ in
            calls.insert("b")
        }
        defer {
            EventBus.shared.unsubscribe(id1)
            EventBus.shared.unsubscribe(id2)
        }
        
        EventBus.shared.publish(FinanceEvent.cardsUpdated)
        
        #expect(calls == ["a", "b"])
    }
    
    @Test("withTimeout возвращает результат, если операция завершилась раньше таймаута")
    func testWithTimeoutReturnsResultBeforeTimeout() async {
        let result = await withTimeout(seconds: 0.2) {
            42
        }
        #expect(result == 42)
    }
    
    @Test("withTimeout возвращает nil, если операция не успела до таймаута")
    func testWithTimeoutReturnsNilOnTimeout() async {
        let result = await withTimeout(seconds: 0.01) {
            try? await Task.sleep(for: .seconds(0.2))
            return 1
        }
        #expect(result == nil)
    }
}
