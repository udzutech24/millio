import Foundation
import XCTest
@testable import millio

/// Контракт `POST /ai/portfolio-digest`: строгий whitelist полей и разбор трёх статусов текста.
final class AIPortfolioDigestContractTests: XCTestCase {
    private func decode(_ json: String) throws -> AIPortfolioDigestResponse {
        try JSONDecoder().decode(AIPortfolioDigestResponse.self, from: Data(json.utf8))
    }

    /// `forbidNonWhitelisted`: лишнее поле = 400, поэтому набор ключей — ровно как в `PortfolioDigestRequestDto`.
    func testRequestEncodesExactlyTheWhitelistedKeys() throws {
        let request = AIPortfolioDigestRequest(
            schemaVersion: "1",
            locale: "ru",
            currency: "RUB",
            window: "month",
            totals: AIPortfolioDigestRequest.Totals(value: 1, changeAmount: 0, changePercent: 0),
            positions: [
                AIPortfolioDigestRequest.Position(symbol: "SBER", assetClass: "stock", value: 1, sharePercent: 100, changePercent: 0)
            ]
        )

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "locale", "currency", "window", "totals", "positions"])
        let totals = try XCTUnwrap(object["totals"] as? [String: Any])
        XCTAssertEqual(Set(totals.keys), ["value", "changeAmount", "changePercent"])
        let position = try XCTUnwrap((object["positions"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(position.keys), ["symbol", "assetClass", "value", "sharePercent", "changePercent"])
    }

    func testOkResponseExposesTextNotesAndServerDisclaimer() throws {
        let response = try decode("""
        {"window":"month","currency":"RUB","totals":{"value":6000,"changeAmount":800,"changePercent":15.38},
         "headline":"Портфель вырос на 15,38% за месяц",
         "notes":[{"text":"50% портфеля приходится на SBER","kind":"concentration","symbol":"SBER"},
                  {"text":"GAZP прибавил 25%","kind":"movement"}],
         "disclaimer":"Информация, не инвестиционная рекомендация.","status":"ok"}
        """)

        XCTAssertEqual(response.status, .ok)
        let text = try XCTUnwrap(response.text)
        XCTAssertEqual(text.headline, "Портфель вырос на 15,38% за месяц")
        XCTAssertEqual(text.notes.map(\.kind), [.concentration, .movement])
        XCTAssertEqual(text.notes.first?.symbol, "SBER")
        XCTAssertEqual(response.disclaimer, "Информация, не инвестиционная рекомендация.")
    }

    /// Даже если сервер по ошибке прислал формулировку со статусом `filtered`, клиент её не показывает.
    func testFilteredResponseNeverShowsText() throws {
        let response = try decode("""
        {"headline":"Докупите SBER","notes":[{"text":"Продайте GAZP","kind":"movement"}],
         "disclaimer":"Information only, not investment advice.","status":"filtered"}
        """)

        XCTAssertEqual(response.status, .filtered)
        XCTAssertNil(response.text)
        XCTAssertEqual(response.disclaimer, "Information only, not investment advice.")
    }

    func testUnavailableResponseHasNoText() throws {
        let response = try decode("""
        {"headline":null,"notes":[],"disclaimer":"仅供参考，不构成投资建议。","status":"unavailable"}
        """)

        XCTAssertEqual(response.status, .unavailable)
        XCTAssertNil(response.text)
        XCTAssertEqual(response.disclaimer, "仅供参考，不构成投资建议。")
    }

    func testUnknownOrMissingStatusIsTreatedAsNoText() throws {
        let unknown = try decode(#"{"headline":"Текст","notes":[],"status":"beta"}"#)
        XCTAssertEqual(unknown.status, .unavailable)
        XCTAssertNil(unknown.text)

        let missing = try decode(#"{"headline":"Текст"}"#)
        XCTAssertEqual(missing.status, .unavailable)
        XCTAssertNil(missing.text)
        XCTAssertNil(missing.disclaimer)
    }

    func testUnknownNoteKindDegradesToStructure() throws {
        let response = try decode(#"{"headline":"Итог","notes":[{"text":"Факт","kind":"forecast"}],"status":"ok"}"#)
        XCTAssertEqual(response.text?.notes.first?.kind, .structure)
    }

    func testBlankOkTextIsNoText() throws {
        let response = try decode(#"{"headline":"   ","notes":[{"text":" ","kind":"movement"}],"status":"ok"}"#)
        XCTAssertNil(response.text)
    }
}
