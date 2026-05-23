//
//  RateSourcePreferenceStoreTests.swift
//  millioTests
//

import XCTest
@testable import millio

final class RateSourcePreferenceStoreTests: XCTestCase {
    private var store: RateSourcePreferenceStore!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.rate-source-pref")!
        defaults.removePersistentDomain(forName: "test.rate-source-pref")
        store = RateSourcePreferenceStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "test.rate-source-pref")
        super.tearDown()
    }

    // MARK: - preferred

    func testPreferredDefaultIsMillio() {
        XCTAssertEqual(store.preferred, .millio)
    }

    func testPreferredSetAndGet() {
        store.preferred = .erapi
        XCTAssertEqual(store.preferred, .erapi)

        store.preferred = .frankfurter
        XCTAssertEqual(store.preferred, .frankfurter)
    }

    func testPreferredUnknownRawValueFallsBackToMillio() {
        defaults.set("unknown_source", forKey: "preferred_rate_source")
        XCTAssertEqual(store.preferred, .millio)
    }

    // MARK: - converterOverride

    func testConverterOverrideNilByDefault() {
        XCTAssertNil(store.converterOverride)
    }

    func testConverterOverrideSetAndGet() {
        store.converterOverride = .erapi
        XCTAssertEqual(store.converterOverride, .erapi)
    }

    func testConverterOverrideSetToNilRemovesKey() {
        store.converterOverride = .frankfurter
        store.converterOverride = nil
        XCTAssertNil(store.converterOverride)
        XCTAssertNil(defaults.string(forKey: "conv_rate_source"))
    }

    // MARK: - reset

    func testResetClearsBothKeys() {
        store.preferred = .erapi
        store.converterOverride = .frankfurter

        store.reset()

        XCTAssertEqual(store.preferred, .millio, "После reset preferred должен вернуться к дефолту .millio")
        XCTAssertNil(store.converterOverride, "После reset converterOverride должен быть nil")
        XCTAssertNil(defaults.string(forKey: "preferred_rate_source"))
        XCTAssertNil(defaults.string(forKey: "conv_rate_source"))
    }
}
