//
//  FinancialRainViewTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

// AC7 — reduceMotion=true → анимация отключена (EmptyView).
// Тип тела SwiftUI недоступен в unit-тестах без ViewInspector.
// Поведение проверяется вручную в Simulator:
//   Settings → Accessibility → Motion → Reduce Motion ON → launch screen пустой.
//
// AC8 — Easter egg фраза локализована для EN / RU / zh-Hans.

struct FinancialRainViewTests {

    @Test("launch.rain.message — EN: SAVE & GROW")
    func easterEggEnglish() {
        let result = AppLocalization.string("launch.rain.message", locale: Locale(identifier: "en"))
        #expect(result == "SAVE & GROW")
    }

    @Test("launch.rain.message — RU: КОПИ И РАСТИ")
    func easterEggRussian() {
        let result = AppLocalization.string("launch.rain.message", locale: Locale(identifier: "ru"))
        #expect(result == "КОПИ И РАСТИ")
    }

    @Test("launch.rain.message — zh-Hans: 储蓄成长")
    func easterEggChinese() {
        let result = AppLocalization.string("launch.rain.message", locale: Locale(identifier: "zh-Hans"))
        #expect(result == "储蓄成长")
    }
}
