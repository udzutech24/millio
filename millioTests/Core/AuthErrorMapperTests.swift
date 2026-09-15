import Foundation
import Testing
@testable import millio

/// Регрессия для п.3 пакета фиксов 2.0(6): timeout к серверу и «нет интернета» —
/// разные категории и разные тексты, чтобы пользователь не проверял Wi-Fi там,
/// где проблема на стороне millio-сервера.
@Suite
struct AuthErrorMapperTests {
    @Test("URLError.timedOut → category .timeout, текст про сервер")
    func testTimedOutMapsToServerTimeout() {
        let transportError = AuthTransportError.from(URLError(.timedOut))
        #expect(transportError == .timeout)

        let presentation = AuthErrorMapper.presentation(for: AuthServiceError.transport(transportError))
        #expect(presentation.category == .timeout)
        #expect(presentation.message == "millio server is unavailable right now. Try again later.")
    }

    @Test("URLError.cannotConnectToHost → category .timeout")
    func testCannotConnectToHostMapsToTimeout() {
        let transportError = AuthTransportError.from(URLError(.cannotConnectToHost))
        #expect(transportError == .timeout)
        #expect(AuthErrorMapper.category(for: AuthServiceError.transport(transportError)) == .timeout)
    }

    @Test("URLError.notConnectedToInternet → category .noInternet, отдельный текст")
    func testNotConnectedMapsToNoInternet() {
        let transportError = AuthTransportError.from(URLError(.notConnectedToInternet))
        #expect(transportError == .noInternet)

        let presentation = AuthErrorMapper.presentation(for: AuthServiceError.transport(transportError))
        #expect(presentation.category == .noInternet)
        #expect(presentation.message == "No internet connection. Check your network and try again.")
        #expect(presentation.message != "millio server is unavailable right now. Try again later.")
    }
}
