//
//  CashflowValueToneTests.swift
//  millioTests
//
//  Created by Codex on 01.03.2026.
//

import Testing
@testable import millio

struct CashflowValueToneTests {
    @Test("Положительное значение классифицируется как positive")
    func positiveTone() {
        #expect(cashflowValueTone(for: 0.1) == .positive)
        #expect(cashflowValueTone(for: 10_000) == .positive)
    }

    @Test("Отрицательное значение классифицируется как negative")
    func negativeTone() {
        #expect(cashflowValueTone(for: -0.1) == .negative)
        #expect(cashflowValueTone(for: -10_000) == .negative)
    }

    @Test("Значение около нуля классифицируется как neutral")
    func neutralToneNearZero() {
        #expect(cashflowValueTone(for: 0) == .neutral)
        #expect(cashflowValueTone(for: 0.00000001) == .neutral)
        #expect(cashflowValueTone(for: -0.00000001) == .neutral)
    }
}
