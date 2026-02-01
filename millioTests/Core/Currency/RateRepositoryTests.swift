//
//  RateRepositoryTests.swift
//  millioTests
//
//  Created by Claude on 01.02.2026.
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct RateRepositoryTests {

    @Test("RateSource имеет валидные URL для всех источников")
    func testRateSourceURLs() {
        #expect(RateSource.erapi.latestURL != nil)
        #expect(RateSource.frankfurter.latestURL != nil)
    }

    @Test("RateSnapshot содержит корректные данные")
    func testRateSnapshotStructure() {
        let now = Date().timeIntervalSince1970
        let rates: [String: Double] = ["USD": 1.0, "EUR": 0.92, "RUB": 90.0]

        let snapshot = RateSnapshot(
            source: .erapi,
            rates: rates,
            updatedAt: now,
            fetchedAt: now
        )

        #expect(snapshot.source == .erapi)
        #expect(snapshot.rates["USD"] == 1.0)
        #expect(snapshot.rates["EUR"] == 0.92)
        #expect(snapshot.rates["RUB"] == 90.0)
        #expect(snapshot.updatedAt == now)
        #expect(snapshot.fetchedAt == now)
    }

    @Test("RateSnapshot rates не пустой")
    func testRateSnapshotNotEmpty() {
        let snapshot = RateSnapshot(
            source: .frankfurter,
            rates: ["USD": 1.0],
            updatedAt: Date().timeIntervalSince1970,
            fetchedAt: Date().timeIntervalSince1970
        )

        #expect(!snapshot.rates.isEmpty)
        #expect(snapshot.rates.count >= 1)
    }

    @Test("ERAPI URL содержит корректный путь")
    func testERAPIURLPath() {
        let url = RateSource.erapi.latestURL
        #expect(url != nil)
        #expect(url!.absoluteString.contains("api"))
    }

    @Test("Frankfurter URL содержит корректный путь")
    func testFrankfurterURLPath() {
        let url = RateSource.frankfurter.latestURL
        #expect(url != nil)
        #expect(url!.absoluteString.contains("frankfurter"))
    }

    @Test("RateSource rawValue соответствует ожидаемым значениям")
    func testRateSourceRawValues() {
        #expect(RateSource.erapi.rawValue == "erapi")
        #expect(RateSource.frankfurter.rawValue == "frankfurter")
    }

    @Test("RateSource инициализируется из rawValue")
    func testRateSourceInitFromRawValue() {
        let erapi = RateSource(rawValue: "erapi")
        #expect(erapi == .erapi)

        let frankfurter = RateSource(rawValue: "frankfurter")
        #expect(frankfurter == .frankfurter)

        let invalid = RateSource(rawValue: "invalid")
        #expect(invalid == nil)
    }
}
