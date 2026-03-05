import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct AppLockPinStoreTests {
    @Test("AppLockPinStore сохраняет и проверяет PIN")
    func testSaveAndVerifyPin() throws {
        let store = AppLockPinStore(
            service: "com.millio.tests.applock.\(UUID().uuidString)",
            account: "pin"
        )
        defer { store.clear() }

        try store.save(pin: "1234")

        #expect(store.hasPin() == true)
        #expect(store.verify(pin: "1234") == true)
        #expect(store.verify(pin: "0000") == false)
    }

    @Test("AppLockPinStore отклоняет невалидный PIN")
    func testRejectsInvalidPin() {
        let store = AppLockPinStore(
            service: "com.millio.tests.applock.\(UUID().uuidString)",
            account: "pin"
        )
        defer { store.clear() }

        #expect(throws: AppError.securityFailed("PIN must contain exactly 4 digits")) {
            try store.save(pin: "12")
        }
    }

    @Test("AppLockPinStore clear удаляет PIN")
    func testClearPin() throws {
        let store = AppLockPinStore(
            service: "com.millio.tests.applock.\(UUID().uuidString)",
            account: "pin"
        )

        try store.save(pin: "5555")
        #expect(store.hasPin() == true)

        store.clear()
        #expect(store.hasPin() == false)
    }
}
