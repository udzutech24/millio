//
//  CashflowHeroPresentationTests.swift
//  millioTests
//


import Foundation
import Testing
@testable import millio

struct CashflowHeroPresentationTests {
    @Test("Hero difference includes only income and expenses")
    func differenceExcludesAssetRevaluation() {
        let presentation = CashflowHeroPresentationPolicy.make(
            totalIncome: 210_000,
            contributedExpense: 200
        )

        #expect(presentation.difference == 209_800)
        #expect(presentation.income == 210_000)
        #expect(presentation.expense == -200)
    }

    @Test("Expense remains negative even if upstream contribution has an unexpected sign")
    func expenseToneIsStable() {
        let presentation = CashflowHeroPresentationPolicy.make(
            totalIncome: 0,
            contributedExpense: -50
        )

        #expect(presentation.expense == -50)
        #expect(presentation.difference == -50)
    }

    @Test("Zero cashflow produces a neutral zero difference")
    func zeroDifference() {
        let presentation = CashflowHeroPresentationPolicy.make(
            totalIncome: 0,
            contributedExpense: 0
        )

        #expect(presentation.difference == 0)
    }

}
