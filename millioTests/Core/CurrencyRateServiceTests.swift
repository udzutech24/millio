//
//  CurrencyRateServiceTests.swift
//  millioTests
//
//  Created by Claude on 01.02.2026.
//

import Foundation
import Testing
@testable import millio

// MARK: - Mock Rate Repository

/// Мок RateRepository для изоляции тестов от сети
@MainActor
final class MockRateRepository: RateRepositoryProtocol, @unchecked Sendable {
    var rates: [String: Double] = [:]
    var shouldFail: Bool = false
    var callCount: Int = 0

    nonisolated func getLatestRates(source: RateSource, forceRefresh: Bool, allowStaleOnError: Bool) async throws -> RateSnapshot {
        await MainActor.run {
            callCount += 1
        }

        let shouldFailValue = await MainActor.run { shouldFail }
        if shouldFailValue {
            throw URLError(.notConnectedToInternet)
        }

        let ratesValue = await MainActor.run { rates }
        return RateSnapshot(
            source: source,
            rates: ratesValue,
            updatedAt: Date().timeIntervalSince1970,
            fetchedAt: Date().timeIntervalSince1970
        )
    }
}

// MARK: - Tests

@Suite(.serialized)
@MainActor
struct CurrencyRateServiceTests {

    @Test("Одинаковые валюты возвращают курс 1.0")
    func testSameCurrencyReturnsOne() async {
        let mockRepo = MockRateRepository()
        mockRepo.rates = ["USD": 1.0, "EUR": 0.92, "RUB": 90.0]

        let service = CurrencyRateService(rateSource: .erapi, rateRepository: mockRepo)

        let rate = await service.getRate(from: "USD", to: "USD")
        #expect(rate == 1.0)

        let rateEUR = await service.getRate(from: "EUR", to: "EUR")
        #expect(rateEUR == 1.0)

        let rateRUB = await service.getRate(from: "rub", to: "RUB") // проверка регистронезависимости
        #expect(rateRUB == 1.0)
    }

    @Test("Конвертация через USD: EUR→RUB")
    func testCrossRateViaUSD() async {
        let mockRepo = MockRateRepository()
        // Курсы к USD: 1 USD = 0.92 EUR, 1 USD = 90 RUB
        mockRepo.rates = ["USD": 1.0, "EUR": 0.92, "RUB": 90.0]

        let service = CurrencyRateService(rateSource: .erapi, rateRepository: mockRepo)

        // EUR→RUB: 1 EUR = (90 / 0.92) RUB ≈ 97.83
        let rate = await service.getRate(from: "EUR", to: "RUB")
        #expect(rate != nil)
        #expect(abs(rate! - (90.0 / 0.92)) < 0.01)
    }

    @Test("Конвертация суммы: convert(100, USD, RUB)")
    func testConvertAmount() async {
        let mockRepo = MockRateRepository()
        mockRepo.rates = ["USD": 1.0, "RUB": 90.0]

        let service = CurrencyRateService(rateSource: .erapi, rateRepository: mockRepo)

        let result = await service.convert(amount: 100, from: "USD", to: "RUB")
        #expect(result != nil)
        #expect(abs(result! - 9000.0) < 0.01)
    }

    @Test("Кэширование: повторный вызов не обращается к API")
    func testCachingPreventsAPICall() async {
        let mockRepo = MockRateRepository()
        mockRepo.rates = ["USD": 1.0, "EUR": 0.92]

        let service = CurrencyRateService(rateSource: .erapi, rateRepository: mockRepo)

        // Первый вызов — загрузка
        _ = await service.getRate(from: "USD", to: "EUR")
        let firstCallCount = mockRepo.callCount

        // Второй вызов — из кэша
        _ = await service.getRate(from: "USD", to: "EUR")
        let secondCallCount = mockRepo.callCount

        // Количество вызовов не должно увеличиться
        #expect(secondCallCount == firstCallCount)
    }

    @Test("Недоступная валюта возвращает nil")
    func testUnavailableCurrencyReturnsNil() async {
        let mockRepo = MockRateRepository()
        mockRepo.rates = ["USD": 1.0, "EUR": 0.92]

        let service = CurrencyRateService(rateSource: .erapi, rateRepository: mockRepo)

        // XYZ — несуществующая валюта
        let rate = await service.getRate(from: "USD", to: "XYZ")
        #expect(rate == nil)

        let rateReverse = await service.getRate(from: "XYZ", to: "USD")
        #expect(rateReverse == nil)
    }

    @Test("Ошибка API: используются старые значения из кэша")
    func testAPIErrorKeepsOldCache() async {
        let mockRepo = MockRateRepository()
        mockRepo.rates = ["USD": 1.0, "EUR": 0.92]

        let service = CurrencyRateService(rateSource: .erapi, rateRepository: mockRepo)

        // Первый вызов — успешная загрузка
        let rate1 = await service.getRate(from: "USD", to: "EUR")
        #expect(rate1 != nil)

        // Эмулируем ошибку сети
        mockRepo.shouldFail = true

        // forceRefreshRates должен завершиться без краша
        await service.forceRefreshRates()

        // Курс всё ещё доступен из кэша
        let rate2 = await service.getRate(from: "USD", to: "EUR")
        #expect(rate2 != nil)
        #expect(rate2 == rate1)
    }

    @Test("forceRefreshRates обновляет кэш принудительно")
    func testForceRefreshUpdatesCache() async {
        let mockRepo = MockRateRepository()
        mockRepo.rates = ["USD": 1.0, "EUR": 0.92]

        let service = CurrencyRateService(rateSource: .erapi, rateRepository: mockRepo)

        // Загружаем начальные курсы
        _ = await service.getRate(from: "USD", to: "EUR")
        let initialCallCount = mockRepo.callCount

        // Меняем курсы
        mockRepo.rates = ["USD": 1.0, "EUR": 0.95]

        // Принудительное обновление
        await service.forceRefreshRates()

        // Должен быть новый вызов
        #expect(mockRepo.callCount > initialCallCount)

        // Курс должен обновиться
        let newRate = await service.getRate(from: "USD", to: "EUR")
        #expect(newRate != nil)
        #expect(abs(newRate! - 0.95) < 0.01)
    }

    @Test("Курс из USD всегда 1.0 даже без загрузки")
    func testUSDRateAlwaysOne() async {
        let mockRepo = MockRateRepository()
        mockRepo.rates = ["USD": 1.0, "EUR": 0.92, "RUB": 90.0]

        let service = CurrencyRateService(rateSource: .erapi, rateRepository: mockRepo)

        // USD→EUR
        let rate = await service.getRate(from: "USD", to: "EUR")
        #expect(rate != nil)
        #expect(abs(rate! - 0.92) < 0.01)

        // EUR→USD
        let rateReverse = await service.getRate(from: "EUR", to: "USD")
        #expect(rateReverse != nil)
        #expect(abs(rateReverse! - (1.0 / 0.92)) < 0.01)
    }

    @Test("Frankfurter HTTP 404 не должен банить пару навсегда (следующий запрос должен выполняться)")
    func testHistorical404DoesNotBlacklistPair() async {
        final class MockHistoricalLoader: HTTPDataLoading {
            struct Response {
                let statusCode: Int
                let body: String
            }

            private(set) var requestedURLs: [URL] = []
            var responses: [String: Response] = [:]

            func data(from url: URL) async throws -> (Data, URLResponse) {
                requestedURLs.append(url)

                let response = responses[url.absoluteString] ?? Response(statusCode: 404, body: #"{"message":"not found"}"#)
                let data = Data(response.body.utf8)
                let http = HTTPURLResponse(
                    url: url,
                    statusCode: response.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (data, http)
            }
        }

        let loader = MockHistoricalLoader()
        let mockRepo = MockRateRepository()
        let service = CurrencyRateService(rateSource: .erapi, rateRepository: mockRepo, historicalLoader: loader)

        let d1 = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 00:00:00 UTC
        let d2 = Date(timeIntervalSince1970: 1_704_153_600) // 2024-01-02 00:00:00 UTC

        let url1 = URL(string: "https://api.frankfurter.app/2024-01-01?from=USD&to=RUB")!
        let url2 = URL(string: "https://api.frankfurter.app/2024-01-02?from=USD&to=RUB")!

        loader.responses[url1.absoluteString] = .init(statusCode: 404, body: #"{"message":"not found"}"#)
        loader.responses[url2.absoluteString] = .init(statusCode: 200, body: #"{"rates":{"RUB":90.0}}"#)

        let r1 = await service.getHistoricalRate(on: d1, from: "USD", to: "RUB")
        #expect(r1 == nil)

        let r2 = await service.getHistoricalRate(on: d2, from: "USD", to: "RUB")
        #expect(r2 == 90.0)
        #expect(loader.requestedURLs == [url1, url2])
    }

    @Test("Frankfurter HTTP 404 для той же даты и пары не должен повторно ходить в сеть")
    func testHistorical404IsNegativeCachedPerDateAndPair() async {
        final class MockHistoricalLoader: HTTPDataLoading {
            private(set) var requestedURLs: [URL] = []

            func data(from url: URL) async throws -> (Data, URLResponse) {
                requestedURLs.append(url)
                let data = Data(#"{"message":"not found"}"#.utf8)
                let http = HTTPURLResponse(
                    url: url,
                    statusCode: 404,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (data, http)
            }
        }

        let loader = MockHistoricalLoader()
        let service = CurrencyRateService(
            rateSource: .erapi,
            rateRepository: MockRateRepository(),
            historicalLoader: loader
        )
        let date = Date(timeIntervalSince1970: 1_704_067_200)

        let first = await service.getHistoricalRate(on: date, from: "CNY", to: "RUB")
        let second = await service.getHistoricalRate(on: date, from: "CNY", to: "RUB")

        #expect(first == nil)
        #expect(second == nil)
        #expect(loader.requestedURLs.count == 1)
    }
}
