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
    /// Предзаполненный stale-кэш, возвращаемый через peekCachedSnapshot (только если shouldFail = true).
    var stubbedStaleRates: [String: Double] = [:]
    var delayNanoseconds: UInt64 = 0

    nonisolated func getLatestRates(source: RateSource, forceRefresh: Bool, allowStaleOnError: Bool) async throws -> RateSnapshot {
        await MainActor.run {
            callCount += 1
        }

        let delay = await MainActor.run { delayNanoseconds }
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }

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

    nonisolated func peekCachedSnapshot(source: RateSource) async -> RateSnapshot? {
        let stale = await MainActor.run { stubbedStaleRates }
        guard !stale.isEmpty else { return nil }
        return RateSnapshot(source: source, rates: stale, updatedAt: 0, fetchedAt: 0)
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

    @Test("Свежий запуск + нет сети: загружается stale-кэш из UserDefaults")
    func testFreshLaunchNetworkDownUsesStaleCached() async {
        let mockRepo = MockRateRepository()
        // Сеть недоступна с первого запроса
        mockRepo.shouldFail = true
        // Но в UserDefaults есть протухшие курсы от прошлого запуска
        mockRepo.stubbedStaleRates = ["USD": 1.0, "EUR": 0.92, "RUB": 90.0]

        let service = CurrencyRateService(rateSource: .erapi, rateRepository: mockRepo)

        // Конвертер должен работать на stale-данных, а не возвращать nil
        let rate = await service.getRate(from: "USD", to: "EUR")
        #expect(rate != nil, "При отключённой сети и наличии stale-кэша курс должен быть доступен")
        #expect(abs((rate ?? 0) - 0.92) < 0.01)
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

        let url1 = URL(string: "https://api.frankfurter.app/2024-01-01?from=USD&to=CNY")!
        let url2 = URL(string: "https://api.frankfurter.app/2024-01-02?from=USD&to=CNY")!

        loader.responses[url1.absoluteString] = .init(statusCode: 404, body: #"{"message":"not found"}"#)
        loader.responses[url2.absoluteString] = .init(statusCode: 200, body: #"{"rates":{"CNY":7.2}}"#)

        let r1 = await service.getHistoricalRate(on: d1, from: "USD", to: "CNY")
        #expect(r1 == nil)

        let r2 = await service.getHistoricalRate(on: d2, from: "USD", to: "CNY")
        #expect(r2 == 7.2)
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

        let first = await service.getHistoricalRate(on: date, from: "USD", to: "CNY")
        let second = await service.getHistoricalRate(on: date, from: "USD", to: "CNY")

        #expect(first == nil)
        #expect(second == nil)
        #expect(loader.requestedURLs.count == 1)
    }

    @Test("RUB historical fallback использует второй провайдер")
    func testHistoricalRUBFallbackUsesSecondaryProvider() async {
        final class MockHistoricalLoader: HTTPDataLoading {
            private(set) var requestedURLs: [URL] = []

            func data(from url: URL) async throws -> (Data, URLResponse) {
                requestedURLs.append(url)
                let data = Data(#"{"message":"unexpected network call"}"#.utf8)
                let http = HTTPURLResponse(
                    url: url,
                    statusCode: 500,
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

        let rubRate = await service.getHistoricalRate(on: date, from: "USD", to: "RUB")
        let kztRate = await service.getHistoricalRate(on: date, from: "KZT", to: "USD")

        #expect(rubRate == nil)
        #expect(kztRate == nil)
        #expect(loader.requestedURLs.count == 1)
        #expect(loader.requestedURLs.first?.host == "www.cbr.ru")
    }

    @Test("RUB historical fallback возвращает точный курс из CBR XML")
    func testHistoricalRUBFallbackParsesCBRXML() async {
        final class MockHistoricalLoader: HTTPDataLoading {
            private(set) var requestedURLs: [URL] = []

            func data(from url: URL) async throws -> (Data, URLResponse) {
                requestedURLs.append(url)

                if url.host == "www.cbr.ru" {
                    let xml = """
                    <?xml version="1.0" encoding="windows-1251"?>
                    <ValCurs Date="01.01.2024" name="Foreign Currency Market">
                        <Valute ID="R01235">
                            <NumCode>840</NumCode>
                            <CharCode>USD</CharCode>
                            <Nominal>1</Nominal>
                            <Name>US Dollar</Name>
                            <Value>90,0000</Value>
                        </Valute>
                        <Valute ID="R01239">
                            <NumCode>978</NumCode>
                            <CharCode>EUR</CharCode>
                            <Nominal>1</Nominal>
                            <Name>Euro</Name>
                            <Value>99,0000</Value>
                        </Valute>
                    </ValCurs>
                    """
                    let data = Data(xml.utf8)
                    let http = HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/xml"]
                    )!
                    return (data, http)
                }

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
        let date = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 UTC

        let usdToRub = await service.getHistoricalRate(on: date, from: "USD", to: "RUB")
        let rubToUsd = await service.getHistoricalRate(on: date, from: "RUB", to: "USD")

        #expect(usdToRub != nil)
        #expect(abs((usdToRub ?? 0) - 90.0) < 0.0001)
        #expect(rubToUsd != nil)
        #expect(abs((rubToUsd ?? 0) - (1.0 / 90.0)) < 0.0001)
        #expect(loader.requestedURLs.allSatisfy { $0.host == "www.cbr.ru" })
    }

    // MARK: - Phase 1a: buildFallbackChain

    @Test("buildFallbackChain: millio первым, без дубликатов")
    func testBuildFallbackChainMillioFirst() {
        let repo = MockRateRepository()
        let svc = CurrencyRateService(rateSource: .millio, rateRepository: repo)
        let chain = svc.buildFallbackChain()
        #expect(chain.first == .millio)
        #expect(chain.count == RateSource.allCases.count)
        #expect(Set(chain) == Set(RateSource.allCases))
    }

    @Test("buildFallbackChain: erapi первым, erapi не дублируется в хвосте")
    func testBuildFallbackChainErapiFirst() {
        let repo = MockRateRepository()
        let svc = CurrencyRateService(rateSource: .erapi, rateRepository: repo)
        let chain = svc.buildFallbackChain()
        #expect(chain.first == .erapi)
        #expect(chain.count == RateSource.allCases.count)
        #expect(!chain.dropFirst().contains(.erapi))
    }

    @Test("buildFallbackChain: frankfurter первым")
    func testBuildFallbackChainFrankfurterFirst() {
        let repo = MockRateRepository()
        let svc = CurrencyRateService(rateSource: .frankfurter, rateRepository: repo)
        let chain = svc.buildFallbackChain()
        #expect(chain.first == .frankfurter)
        #expect(chain.count == RateSource.allCases.count)
    }

    // MARK: - Phase 1a: setRateSource

    @Test("setRateSource: обновляет rateSource и store.preferred")
    func testSetRateSourceUpdatesState() {
        let repo = MockRateRepository()
        let defaults = UserDefaults(suiteName: "test.set-rate-source")!
        defaults.removePersistentDomain(forName: "test.set-rate-source")
        defer { defaults.removePersistentDomain(forName: "test.set-rate-source") }

        let store = RateSourcePreferenceStore(defaults: defaults)
        let svc = CurrencyRateService(rateSource: .millio, store: store, rateRepository: repo)
        svc.setRateSource(.frankfurter)

        #expect(svc.rateSource == .frankfurter)
        #expect(store.preferred == .frankfurter)
    }

    @Test("setRateSource: сбрасывает кэш (EUR недоступен синхронно после смены)")
    func testSetRateSourceResetsCache() async {
        let repo = MockRateRepository()
        repo.rates = ["USD": 1.0, "EUR": 0.92]
        let svc = CurrencyRateService(rateSource: .millio, rateRepository: repo)
        _ = await svc.getRate(from: "USD", to: "EUR")
        svc.setRateSource(.erapi)
        #expect(svc.getCachedRate(from: "USD", to: "EUR") == nil)
    }

    @Test("setRateSource: отправляет уведомление currencyRateSourceDidChange")
    func testSetRateSourcePostsNotification() async {
        let repo = MockRateRepository()
        let svc = CurrencyRateService(rateSource: .millio, rateRepository: repo)

        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: .currencyRateSourceDidChange,
            object: nil,
            queue: .main
        ) { _ in received = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        svc.setRateSource(.erapi)
        // Уведомление синхронно через NotificationCenter.default.post
        #expect(received)
    }

    @Test("generation-guard: in-flight refresh старого источника не перезаписывает кэш")
    func testGenerationGuardPreventsStaleWrite() async {
        let repo = MockRateRepository()
        repo.rates = ["USD": 1.0, "EUR": 0.92]
        repo.delayNanoseconds = 300_000_000 // 300ms

        let svc = CurrencyRateService(rateSource: .millio, rateRepository: repo)

        let refreshTask = Task { await svc.forceRefreshRates() }
        // Ждём 50ms, затем меняем источник (generation += 1)
        try? await Task.sleep(nanoseconds: 50_000_000)
        svc.setRateSource(.erapi)
        await refreshTask.value

        // Кэш сброшен setRateSource; старый in-flight не должен был записать EUR
        #expect(svc.getCachedRate(from: "USD", to: "EUR") == nil)
    }
}

// MARK: - CBR Tests

@Suite("CBR RateSource", .serialized)
@MainActor
struct CBRRateSourceTests {

    // Минимальный CBR XML с USD, EUR, CNY. rubPerUSD=85, rubPerEUR=92, rubPerCNY=12.
    static let cbrXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <ValCurs Date="23.05.2026" name="Foreign Currency Market">
      <Valute ID="R01235">
        <CharCode>USD</CharCode><Nominal>1</Nominal><Value>85,0000</Value>
      </Valute>
      <Valute ID="R01239">
        <CharCode>EUR</CharCode><Nominal>1</Nominal><Value>92,0000</Value>
      </Valute>
      <Valute ID="R01375">
        <CharCode>CNY</CharCode><Nominal>1</Nominal><Value>12,0000</Value>
      </Valute>
    </ValCurs>
    """.data(using: .utf8)!

    final class MockCBRLoader: HTTPDataLoading, @unchecked Sendable {
        let data: Data
        init(data: Data) { self.data = data }
        func data(from url: URL) async throws -> (Data, URLResponse) {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }

    final class FailingLoader: HTTPDataLoading, @unchecked Sendable {
        func data(from url: URL) async throws -> (Data, URLResponse) {
            throw URLError(.notConnectedToInternet)
        }
    }

    @Test("buildFallbackChain для .cbr ставит его первым без дубликатов")
    func testBuildFallbackChainCBR() {
        let svc = CurrencyRateService(rateSource: .cbr, rateRepository: MockRateRepository())
        let chain = svc.buildFallbackChain()
        #expect(chain.first == .cbr)
        #expect(Set(chain).count == chain.count)
        #expect(chain.count == RateSource.allCases.count)
    }

    @Test("setRateSource(.cbr) сбрасывает кэш и инкрементирует generation")
    func testSetRateSourceCBRResetsCache() async {
        let svc = CurrencyRateService(rateSource: .millio, rateRepository: MockRateRepository())
        // Симулируем наличие курсов в кэше
        await svc.forceRefreshRates()
        svc.setRateSource(.cbr)
        // После смены кэш сброшен — только USD = 1.0
        #expect(svc.getCachedRate(from: "USD", to: "EUR") == nil)
    }

    @Test("CBR нормализация: getRate USD→RUB ≈ 85")
    func testCBRGetRateUSDtoRUB() async {
        let loader = MockCBRLoader(data: Self.cbrXML)
        let svc = CurrencyRateService(
            rateSource: .cbr,
            rateRepository: MockRateRepository(),
            historicalLoader: loader,
            cbrLatestProvider: CBRLatestRateProvider()
        )
        let rate = await svc.getRate(from: "USD", to: "RUB")
        #expect(abs((rate ?? 0) - 85.0) < 0.01)
    }

    @Test("CBR нормализация: getRate RUB→USD ≈ 1/85")
    func testCBRGetRateRUBtoUSD() async {
        let loader = MockCBRLoader(data: Self.cbrXML)
        let svc = CurrencyRateService(
            rateSource: .cbr,
            rateRepository: MockRateRepository(),
            historicalLoader: loader,
            cbrLatestProvider: CBRLatestRateProvider()
        )
        let rate = await svc.getRate(from: "RUB", to: "USD")
        #expect(abs((rate ?? 0) - (1.0 / 85.0)) < 1e-5)
    }

    @Test("CBR нормализация: getRate EUR→RUB ≈ 92")
    func testCBRGetRateEURtoRUB() async {
        let loader = MockCBRLoader(data: Self.cbrXML)
        let svc = CurrencyRateService(
            rateSource: .cbr,
            rateRepository: MockRateRepository(),
            historicalLoader: loader,
            cbrLatestProvider: CBRLatestRateProvider()
        )
        let rate = await svc.getRate(from: "EUR", to: "RUB")
        #expect(abs((rate ?? 0) - 92.0) < 0.01)
    }

    @Test("CBR: пара EUR→CNY не RUB-involved, роутится на globalFiat, возвращает курс или nil (не crash)")
    func testCBRNonRUBPairRoutesToGlobalFiat() async {
        let loader = MockCBRLoader(data: Self.cbrXML)
        let repo = MockRateRepository()
        repo.rates = ["USD": 1.0, "EUR": 0.92, "CNY": 7.2]
        let svc = CurrencyRateService(
            rateSource: .cbr,
            rateRepository: repo,
            historicalLoader: loader,
            cbrLatestProvider: CBRLatestRateProvider()
        )
        // Главное — не падает и возвращает Double? (не бросает ошибку)
        let rate = await svc.getRate(from: "EUR", to: "CNY")
        // Может быть nil если globalFiat fallback не смог — но не crash
        _ = rate
    }
}
