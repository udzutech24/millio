//
//  CustomRateStoreTests.swift
//  millioTests
//

import XCTest
@testable import millio

final class CustomRateStoreTests: XCTestCase {
    private var store: CustomRateStore!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.custom-rate-store")!
        defaults.removePersistentDomain(forName: "test.custom-rate-store")
        store = CustomRateStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "test.custom-rate-store")
        super.tearDown()
    }

    // MARK: - isConfigured

    func test_isConfigured_emptyRates_returnsFalse() {
        XCTAssertFalse(store.isConfigured)
    }

    func test_isConfigured_withoutUSD_primaryNotUSD_returnsFalse() {
        store.rates = ["EUR": 80.5]
        store.primaryForRates = "RUB"
        XCTAssertFalse(store.isConfigured)
    }

    func test_isConfigured_withUSD_primaryRUB_returnsTrue() {
        store.rates = ["USD": 71.2, "EUR": 80.5]
        store.primaryForRates = "RUB"
        XCTAssertTrue(store.isConfigured)
    }

    func test_isConfigured_primaryUSD_noUSDEntry_returnsTrue() {
        store.rates = ["EUR": 1.13]
        store.primaryForRates = "USD"
        XCTAssertTrue(store.isConfigured)
    }

    // MARK: - toUSDBase: primary = RUB

    func test_toUSDBase_primaryRUB_usdRate() {
        // 1 USD = 71.2 RUB → cachedRates["RUB"] = 1/71.2 ≈ 0.01404
        store.rates = ["USD": 71.2]
        let result = store.toUSDBase(currentPrimary: "RUB")
        XCTAssertEqual(result["RUB"] ?? 0, 1.0 / 71.2, accuracy: 1e-9)
        // USD в USD-base не хранится (он всегда 1.0 в CurrencyRateService)
        XCTAssertNil(result["USD"])
    }

    func test_toUSDBase_primaryRUB_eurRate() {
        // 1 USD = 71.2 RUB, 1 EUR = 80.5 RUB
        // cachedRates["EUR"] = 80.5/71.2 ≈ 1.1306 (USD за 1 EUR)
        store.rates = ["USD": 71.2, "EUR": 80.5]
        let result = store.toUSDBase(currentPrimary: "RUB")
        let expected = 80.5 / 71.2
        XCTAssertEqual(result["EUR"] ?? 0, expected, accuracy: 1e-9)
        XCTAssertEqual(result["RUB"] ?? 0, 1.0 / 71.2, accuracy: 1e-9)
    }

    func test_toUSDBase_primaryRUB_cnyRate() {
        // 1 USD = 71.2 RUB, 1 CNY = 9.8 RUB
        // cachedRates["CNY"] = 9.8/71.2
        store.rates = ["USD": 71.2, "EUR": 80.5, "CNY": 9.8]
        let result = store.toUSDBase(currentPrimary: "RUB")
        XCTAssertEqual(result["CNY"] ?? 0, 9.8 / 71.2, accuracy: 1e-9)
    }

    func test_toUSDBase_primaryRUB_missingUSD_returnsEmpty() {
        store.rates = ["EUR": 80.5]
        let result = store.toUSDBase(currentPrimary: "RUB")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - toUSDBase: primary = USD

    func test_toUSDBase_primaryUSD_eurRate() {
        // 1 EUR = 1.13 USD → cachedRates["EUR"] = 1.13/1.0 = 1.13
        store.rates = ["EUR": 1.13, "CNY": 0.138]
        store.primaryForRates = "USD"
        let result = store.toUSDBase(currentPrimary: "USD")
        XCTAssertEqual(result["EUR"] ?? 0, 1.13, accuracy: 1e-9)
        XCTAssertEqual(result["CNY"] ?? 0, 0.138, accuracy: 1e-9)
    }

    func test_toUSDBase_primaryUSD_usdEntry_equalsOne() {
        // Если пользователь случайно ввёл USD (= 1 USD за 1 USD)
        store.rates = ["USD": 1.0, "EUR": 1.13]
        store.primaryForRates = "USD"
        let result = store.toUSDBase(currentPrimary: "USD")
        XCTAssertEqual(result["EUR"] ?? 0, 1.13, accuracy: 1e-9)
    }

    // MARK: - Case sensitivity

    func test_toUSDBase_lowercaseKeys_normalizedToUppercase() {
        store.rates = ["usd": 71.2, "eur": 80.5]
        let result = store.toUSDBase(currentPrimary: "RUB")
        XCTAssertNotNil(result["EUR"])
        XCTAssertNotNil(result["RUB"])
    }

    // MARK: - reset

    func test_reset_clearsRates() {
        store.rates = ["USD": 71.2]
        store.primaryForRates = "RUB"
        store.reset()
        XCTAssertTrue(store.rates.isEmpty)
        XCTAssertFalse(store.isConfigured)
    }

    // MARK: - RateSource.custom existence

    func test_rateSource_customExists() {
        XCTAssertNotNil(RateSource(rawValue: "custom"))
        XCTAssertEqual(RateSource(rawValue: "custom"), .custom)
    }

    func test_rateSource_allCasesContainsCustom() {
        XCTAssertTrue(RateSource.allCases.contains(.custom))
    }

    func test_rateSource_customLatestURL_isNil() {
        XCTAssertNil(RateSource.custom.latestURL)
    }

    func test_rateSource_customCapability_globalFiatDailyScope() {
        XCTAssertEqual(RateSource.custom.capability.scope, .globalFiatDaily)
        XCTAssertFalse(RateSource.custom.capability.supportsHistorical)
        XCTAssertFalse(RateSource.custom.capability.requiresAPIKey)
    }
}
