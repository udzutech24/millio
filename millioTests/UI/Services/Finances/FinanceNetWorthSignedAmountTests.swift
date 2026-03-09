//
//  FinanceNetWorthSignedAmountTests.swift
//  millioTests
//
//  Created by Codex on 09.03.2026.
//

import Foundation
import Testing
@testable import millio

struct FinanceNetWorthSignedAmountTests {
    @Test("SignedAmount: кредитная карта учитывается как отрицательный долг")
    func creditCardDebtIsNegative() {
        let card = Card(
            name: "CC",
            cardNumber: "0000",
            cardType: .credit,
            currency: "RUB",
            balance: 200,
            creditLimit: 1000
        )

        #expect(FinanceNetWorthSignedAmount.signedValue(for: card) == -800)
    }

    @Test("SignedAmount: дебетовая карта учитывается как баланс со знаком")
    func debitCardBalanceKeepsSign() {
        let positive = Card(name: "D1", cardNumber: "0000", cardType: .debit, currency: "RUB", balance: 150)
        let negative = Card(name: "D2", cardNumber: "0000", cardType: .debit, currency: "RUB", balance: -50)

        #expect(FinanceNetWorthSignedAmount.signedValue(for: positive) == 150)
        #expect(FinanceNetWorthSignedAmount.signedValue(for: negative) == -50)
    }

    @Test("SignedAmount: кредит учитывается как отрицательный остаток долга")
    func creditRemainingIsNegative() {
        let credit = Credit(
            name: "Loan",
            amount: 500,
            interestRate: 0,
            monthlyPayment: 0,
            startDate: Date(),
            termMonths: 1,
            currency: "RUB"
        )
        credit.remainingAmount = 420

        #expect(FinanceNetWorthSignedAmount.signedValue(for: credit) == -420)
    }

    @Test("SignedAmount: отрицательная инвестиция уменьшает итог")
    func negativeInvestmentIsNegative() {
        let investment = Investment(
            name: "Debt",
            investmentType: .negative,
            category: .other,
            amount: 10_000,
            currency: "RUB"
        )

        #expect(FinanceNetWorthSignedAmount.signedValue(for: investment) == -10_000)
    }

    @Test("SignedAmount: exclude/includeInTotal исключает продукт из итога")
    func includeInTotalFalseReturnsNil() {
        let card = Card(name: "D", cardNumber: "0000", cardType: .debit, currency: "RUB", balance: 150, includeInTotal: false)
        let credit = Credit(
            name: "Loan",
            amount: 500,
            interestRate: 0,
            monthlyPayment: 0,
            startDate: Date(),
            termMonths: 1,
            currency: "RUB",
            includeInTotal: false
        )
        let investment = Investment(name: "Asset", investmentType: .positive, category: .other, amount: 10_000, currency: "RUB", includeInTotal: false)

        #expect(FinanceNetWorthSignedAmount.signedValue(for: card) == nil)
        #expect(FinanceNetWorthSignedAmount.signedValue(for: credit) == nil)
        #expect(FinanceNetWorthSignedAmount.signedValue(for: investment) == nil)
    }

    @Test("SignedAmount: расчет по FinanceAccount использует правильный источник")
    func signedValueForFinanceAccountUsesDictionaries() {
        let investment = Investment(
            name: "Debt",
            investmentType: .negative,
            category: .other,
            amount: 10_000,
            currency: "RUB"
        )
        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)

        let value = FinanceNetWorthSignedAmount.signedValue(
            for: account,
            cardsByID: [:],
            creditsByID: [:],
            investmentsByID: [investment.investmentUniqueID: investment]
        )

        #expect(value == -10_000)
    }
}

