//
//  MainConverterDashboardSupportTests.swift
//  millioTests
//
//  Created by Codex on 04.04.2026.
//

import Foundation
import Testing
@testable import millio

struct MainConverterDashboardSupportTests {
    @Test("Блок конвертера показывает только три целевые валюты без дублей и базовой")
    func quoteTargetsLimitAndFilterPrimary() {
        let result = MainConverterDashboardSupport.quoteTargets(
            primaryCode: "RUB",
            favoriteCodes: ["USD", "EUR", "RUB", "USD", "CNY", "GBP"]
        )

        #expect(result == ["USD", "EUR", "CNY"])
    }

    @Test("Котировка считает стоимость одной базовой валюты в целевой")
    func rateSummaryUsesBaseToTargetRate() {
        let summary = MainConverterDashboardSupport.rateSummary(
            primaryCode: "RUB",
            targetCode: "USD",
            rates: ["USD": 1.0, "RUB": 100.0],
            locale: Locale(identifier: "en_US")
        )

        #expect(summary == "0.01 USD")
    }

    @Test("При отсутствии курса блок показывает безопасный fallback")
    func rateSummaryUsesFallbackWhenRatesMissing() {
        let summary = MainConverterDashboardSupport.rateSummary(
            primaryCode: "RUB",
            targetCode: "AED",
            rates: ["USD": 1.0, "RUB": 100.0],
            locale: Locale(identifier: "en_US")
        )

        #expect(summary == "— AED")
    }
}
