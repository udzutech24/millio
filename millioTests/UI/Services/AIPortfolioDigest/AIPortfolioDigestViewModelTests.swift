import Foundation
import XCTest
@testable import millio

private let digestServerDisclaimer = "Информация, не инвестиционная рекомендация."

/// Дайджест: дисклеймер в любом состоянии, текст только при `ok`, сеть — только по открытию экрана.
@MainActor
final class AIPortfolioDigestViewModelTests: XCTestCase {
    private final class SpyClient: AIPortfolioDigestClient, @unchecked Sendable {
        let isAvailable: Bool
        let result: Result<AIPortfolioDigestResponse, Error>
        private(set) var requests: [AIPortfolioDigestRequest] = []

        init(isAvailable: Bool = true, result: Result<AIPortfolioDigestResponse, Error>) {
            self.isAvailable = isAvailable
            self.result = result
        }

        func digest(_ request: AIPortfolioDigestRequest) async throws -> AIPortfolioDigestResponse {
            requests.append(request)
            return try result.get()
        }
    }

    private func response(
        _ status: AIPortfolioDigestStatus,
        headline: String? = "Портфель вырос на 15,38% за месяц",
        disclaimer: String? = digestServerDisclaimer
    ) -> AIPortfolioDigestResponse {
        AIPortfolioDigestResponse(
            headline: headline,
            notes: [AIPortfolioDigestNote(text: "50% портфеля приходится на SBER", kind: .concentration, symbol: "SBER")],
            disclaimer: disclaimer,
            status: status
        )
    }

    private func figures(_ window: AIPortfolioWindow) -> AIPortfolioFigures? {
        AIPortfolioDigestPayloadBuilder.figures(
            window: window,
            currency: "RUB",
            positions: [
                .init(accountID: UUID(), name: "Сбер", symbol: "SBER", assetClass: .stock, quantity: 10, value: 3_000, startUnitPrice: 280, averageUnitCost: 250),
                .init(accountID: UUID(), name: "Газпром", symbol: "GAZP", assetClass: .stock, quantity: 20, value: 3_000, startUnitPrice: nil, averageUnitCost: 120)
            ],
            portfolioTotal: 6_000
        )
    }

    private func makeViewModel(
        _ client: SpyClient,
        figures provider: (@MainActor (AIPortfolioWindow) -> AIPortfolioFigures?)? = nil
    ) -> AIPortfolioDigestViewModel {
        AIPortfolioDigestViewModel(
            currency: "RUB",
            figuresProvider: provider ?? { [unowned self] in self.figures($0) },
            client: client,
            locale: { Locale(identifier: "ru_RU") }
        )
    }

    private var localDisclaimer: String { L("ai.portfolio.disclaimer") }

    private func openAndSettle(_ viewModel: AIPortfolioDigestViewModel) async {
        viewModel.open()
        await viewModel.loadTask?.value
    }

    // MARK: - Дисклеймер во всех состояниях

    func testLocalDisclaimerIsCompiledIntoTheCatalog() {
        XCTAssertNotEqual(localDisclaimer, "ai.portfolio.disclaimer")
        XCTAssertFalse(localDisclaimer.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    func testDisclaimerAndFiguresAreThereBeforeAnyRequest() {
        let client = SpyClient(result: .success(response(.ok)))
        let viewModel = makeViewModel(client)

        XCTAssertNotNil(viewModel.figures)
        XCTAssertEqual(viewModel.disclaimer, localDisclaimer)
        XCTAssertTrue(client.requests.isEmpty, "без открытия экрана запроса быть не должно")
    }

    func testOkShowsTextAndServerDisclaimer() async {
        let viewModel = makeViewModel(SpyClient(result: .success(response(.ok))))
        await openAndSettle(viewModel)

        XCTAssertEqual(viewModel.text?.headline, "Портфель вырос на 15,38% за месяц")
        XCTAssertEqual(viewModel.disclaimer, digestServerDisclaimer)
        XCTAssertFalse(viewModel.isLoadingText)
    }

    func testFilteredShowsFiguresWithoutTextAndKeepsDisclaimer() async {
        let viewModel = makeViewModel(SpyClient(result: .success(response(.filtered, headline: "Докупите SBER"))))
        await openAndSettle(viewModel)

        XCTAssertNil(viewModel.text)
        XCTAssertNotNil(viewModel.figures)
        XCTAssertEqual(viewModel.disclaimer, digestServerDisclaimer)
        XCTAssertFalse(viewModel.isLoadingText)
    }

    func testUnavailableShowsFiguresWithoutTextAndKeepsDisclaimer() async {
        let viewModel = makeViewModel(SpyClient(result: .success(response(.unavailable, headline: nil))))
        await openAndSettle(viewModel)

        XCTAssertNil(viewModel.text)
        XCTAssertNotNil(viewModel.figures)
        XCTAssertEqual(viewModel.disclaimer, digestServerDisclaimer)
    }

    func testOfflineFallsBackToLocalDisclaimer() async {
        let viewModel = makeViewModel(SpyClient(result: .failure(AICopilotClientError.transport)))
        await openAndSettle(viewModel)

        XCTAssertNil(viewModel.text)
        XCTAssertNotNil(viewModel.figures)
        XCTAssertEqual(viewModel.disclaimer, localDisclaimer)
        XCTAssertFalse(viewModel.isLoadingText)
    }

    func testBlankServerDisclaimerFallsBackToLocal() async {
        let viewModel = makeViewModel(SpyClient(result: .success(response(.ok, disclaimer: "  "))))
        await openAndSettle(viewModel)

        XCTAssertEqual(viewModel.disclaimer, localDisclaimer)
    }

    func testMissingClientKeepsFiguresAndDisclaimerWithoutSpinner() {
        let client = SpyClient(isAvailable: false, result: .failure(AICopilotClientError.unavailable))
        let viewModel = makeViewModel(client)
        viewModel.open()

        XCTAssertFalse(viewModel.isLoadingText)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertEqual(viewModel.disclaimer, localDisclaimer)
    }

    func testEmptyPortfolioSendsNothingAndKeepsDisclaimer() {
        let client = SpyClient(result: .success(response(.ok)))
        let viewModel = makeViewModel(client, figures: { _ in nil })
        viewModel.open()

        XCTAssertNil(viewModel.figures)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertEqual(viewModel.disclaimer, localDisclaimer)
    }

    // MARK: - Стоимость: сеть только по явному действию

    func testReappearingScreenDoesNotCallAgain() async {
        let client = SpyClient(result: .success(response(.ok)))
        let viewModel = makeViewModel(client)
        await openAndSettle(viewModel)
        viewModel.open()
        viewModel.open()

        XCTAssertEqual(client.requests.count, 1)
    }

    func testEachWindowIsRequestedOnceWhileSwitchingBackAndForth() async {
        let client = SpyClient(result: .success(response(.ok)))
        let viewModel = makeViewModel(client)
        await openAndSettle(viewModel)

        viewModel.select(.quarter)
        await viewModel.loadTask?.value
        viewModel.select(.month)
        viewModel.select(.quarter)
        viewModel.select(.month)

        XCTAssertEqual(client.requests.map(\.window), ["month", "quarter"])
        XCTAssertEqual(viewModel.text?.headline, "Портфель вырос на 15,38% за месяц")
    }

    func testSelectingWindowBeforeOpenDoesNotHitNetwork() {
        let client = SpyClient(result: .success(response(.ok)))
        let viewModel = makeViewModel(client)
        viewModel.select(.year)

        XCTAssertEqual(viewModel.figures?.window, .year)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testFailedWindowIsNotRetriedInTheSameScreen() async {
        let client = SpyClient(result: .failure(AICopilotClientError.rateLimited))
        let viewModel = makeViewModel(client)
        await openAndSettle(viewModel)
        viewModel.select(.quarter)
        await viewModel.loadTask?.value
        viewModel.select(.month)

        XCTAssertEqual(client.requests.map(\.window), ["month", "quarter"])
    }

    // MARK: - Модель получает ровно те цифры, что на экране

    func testRequestCarriesTheFiguresShownOnScreen() async throws {
        let client = SpyClient(result: .success(response(.ok)))
        let viewModel = makeViewModel(client)
        await openAndSettle(viewModel)

        let shown = try XCTUnwrap(viewModel.figures)
        let sent = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(sent.locale, "ru")
        XCTAssertEqual(sent.currency, "RUB")
        XCTAssertEqual(sent.totals.value, AIPortfolioDigestPayloadBuilder.rounded(shown.value))
        XCTAssertEqual(sent.totals.changeAmount, AIPortfolioDigestPayloadBuilder.rounded(shown.changeAmount))
        XCTAssertEqual(sent.positions.map(\.symbol), shown.positions.map(\.symbol))
        XCTAssertEqual(sent.positions.map(\.sharePercent), shown.positions.map { AIPortfolioDigestPayloadBuilder.rounded($0.sharePercent) })
    }
}
