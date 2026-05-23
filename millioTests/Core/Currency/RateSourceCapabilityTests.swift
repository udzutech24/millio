//
//  RateSourceCapabilityTests.swift
//  millioTests
//

import XCTest
@testable import millio

final class RateSourceCapabilityTests: XCTestCase {

    // Snapshot-тест: capability каждого источника совпадает с таблицей из спека.
    // При добавлении нового кейса RateSource тест упадёт — напомнит заполнить capability.

    func testMillioCapability() {
        let cap = RateSource.millio.capability
        XCTAssertEqual(cap.scope, .globalFiatDaily)
        XCTAssertEqual(cap.baseCurrency, .usd)
        XCTAssertFalse(cap.requiresAPIKey)
        XCTAssertTrue(cap.supportsMatrixFetch)
        XCTAssertFalse(cap.supportsHistorical)
        XCTAssertEqual(cap.freshnessLabel, .daily)
        XCTAssertEqual(cap.legalLabel, .aggregator)
    }

    func testErapiCapability() {
        let cap = RateSource.erapi.capability
        XCTAssertEqual(cap.scope, .globalFiatDaily)
        XCTAssertEqual(cap.baseCurrency, .usd)
        XCTAssertFalse(cap.requiresAPIKey)
        XCTAssertTrue(cap.supportsMatrixFetch)
        XCTAssertFalse(cap.supportsHistorical)
        XCTAssertEqual(cap.freshnessLabel, .daily)
        XCTAssertEqual(cap.legalLabel, .reference)
    }

    func testFrankfurterCapability() {
        let cap = RateSource.frankfurter.capability
        XCTAssertEqual(cap.scope, .globalFiatDaily)
        XCTAssertEqual(cap.baseCurrency, .eur)
        XCTAssertFalse(cap.requiresAPIKey)
        XCTAssertTrue(cap.supportsMatrixFetch)
        XCTAssertTrue(cap.supportsHistorical)
        XCTAssertEqual(cap.freshnessLabel, .daily)
        XCTAssertEqual(cap.legalLabel, .reference)
    }

    func testCBRCapability() {
        let cap = RateSource.cbr.capability
        XCTAssertEqual(cap.scope, .rubOfficialDaily)
        XCTAssertEqual(cap.baseCurrency, .rub)
        XCTAssertFalse(cap.requiresAPIKey)
        XCTAssertTrue(cap.supportsMatrixFetch)
        XCTAssertTrue(cap.supportsHistorical)
        XCTAssertEqual(cap.freshnessLabel, .daily)
        XCTAssertEqual(cap.legalLabel, .official)
    }

    func testAllCasesHaveCapability() {
        // Гарантия: у всех 5 кейсов capability определён (не crashит).
        XCTAssertEqual(RateSource.allCases.count, 5)
        for source in RateSource.allCases {
            _ = source.capability
        }
    }

    func testCBRRawValueAndURL() {
        XCTAssertEqual(RateSource.cbr.rawValue, "cbr")
        XCTAssertNotNil(RateSource.cbr.latestURL)
        XCTAssertTrue(RateSource.cbr.latestURL!.absoluteString.contains("cbr.ru"))
    }

    func testCBRNormalizationToUSD() {
        // rubPerUSD = 85, rubPerEUR = 92, rubPerCNY = 12
        let rubPerCurrency: [String: Double] = ["USD": 85.0, "EUR": 92.0, "CNY": 12.0]
        let result = CBRLatestRateProvider.normalizeToUSD(rubPerCurrency: rubPerCurrency)

        XCTAssertEqual(result["USD"] ?? 0, 1.0, accuracy: 1e-6)
        XCTAssertEqual(result["RUB"] ?? 0, 85.0, accuracy: 1e-6)
        // EUR в USD: rubPerUSD / rubPerEUR = 85 / 92 ≈ 0.9239
        XCTAssertEqual(result["EUR"] ?? 0, 85.0 / 92.0, accuracy: 1e-6)
        // CNY в USD: 85 / 12 ≈ 7.0833
        XCTAssertEqual(result["CNY"] ?? 0, 85.0 / 12.0, accuracy: 1e-6)
    }

    func testCBRNormalizationWithoutUSDReturnsEmpty() {
        // Если USD отсутствует в XML — нормализация невозможна.
        let rubPerCurrency: [String: Double] = ["EUR": 92.0, "CNY": 12.0]
        let result = CBRLatestRateProvider.normalizeToUSD(rubPerCurrency: rubPerCurrency)
        XCTAssertTrue(result.isEmpty)
    }
}
