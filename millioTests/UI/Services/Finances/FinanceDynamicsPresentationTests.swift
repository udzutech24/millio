//
//  FinanceDynamicsPresentationTests.swift
//  millioTests
//

import Testing
@testable import millio

struct FinanceDynamicsPresentationTests {
    @Test("Accounts total row uses net values for liabilities")
    func totalRowSubtractsLiabilitiesInAccountsMode() {
        let asset = DynamicsBreakdownItem(
            id: "asset",
            name: "Cash",
            startValue: 100,
            endValue: 150,
            delta: 50,
            deltaPercent: 50,
            icon: nil,
            accountType: .card,
            isCreditCard: false,
            isArchived: false
        )
        let liability = DynamicsBreakdownItem(
            id: "liability",
            name: "Credit",
            startValue: 40,
            endValue: 10,
            delta: 30,
            deltaPercent: 75,
            icon: nil,
            accountType: .credit,
            isCreditCard: false,
            isArchived: false
        )

        let total = FinanceDynamicsPresentation.totalRow(
            from: [asset, liability],
            viewMode: .accounts
        )

        #expect(total != nil)
        #expect(total?.startValue == 60)
        #expect(total?.endValue == 140)
        #expect(total?.delta == 80)
        #expect(abs((total?.deltaPercent ?? 0) - 133.33333333333334) < 0.0001)
    }

    @Test("Accounts total row subtracts credit-card debt from totals")
    func totalRowSubtractsCreditCardDebtInAccountsMode() {
        let asset = DynamicsBreakdownItem(
            id: "asset",
            name: "Brokerage",
            startValue: 1_000,
            endValue: 900,
            delta: -100,
            deltaPercent: -10,
            icon: nil,
            accountType: .investment,
            isCreditCard: false,
            isArchived: false
        )
        let creditCardDebt = DynamicsBreakdownItem(
            id: "credit-card",
            name: "Credit card",
            startValue: 250,
            endValue: 300,
            delta: -50,
            deltaPercent: -20,
            icon: nil,
            accountType: .card,
            isCreditCard: true,
            isArchived: false
        )

        let total = FinanceDynamicsPresentation.totalRow(
            from: [asset, creditCardDebt],
            viewMode: .accounts
        )

        #expect(total != nil)
        #expect(total?.startValue == 750)
        #expect(total?.endValue == 600)
        #expect(total?.delta == -150)
        #expect(total?.deltaPercent == -20)
    }

    @Test("Groups total row keeps provided values unchanged")
    func totalRowKeepsGroupTotalsAsProvided() {
        let cashGroup = DynamicsBreakdownItem(
            id: "cash",
            name: "Cash",
            startValue: 500,
            endValue: 700,
            delta: 200,
            deltaPercent: 40,
            icon: nil,
            accountType: nil,
            isCreditCard: false,
            isArchived: false
        )
        let debtGroup = DynamicsBreakdownItem(
            id: "debt",
            name: "Debt",
            startValue: -100,
            endValue: -50,
            delta: 50,
            deltaPercent: 50,
            icon: nil,
            accountType: nil,
            isCreditCard: false,
            isArchived: false
        )

        let total = FinanceDynamicsPresentation.totalRow(
            from: [cashGroup, debtGroup],
            viewMode: .groups
        )

        #expect(total != nil)
        #expect(total?.startValue == 400)
        #expect(total?.endValue == 650)
        #expect(total?.delta == 250)
        #expect(total?.deltaPercent == 62.5)
    }

    @Test("Non-zero delta from a zero baseline has an undefined percentage")
    func totalRowUsesUndefinedPercentageForZeroBaseline() {
        let item = DynamicsBreakdownItem(
            id: "new",
            name: "New account",
            startValue: 0,
            endValue: 100,
            delta: 100,
            deltaPercent: nil,
            icon: nil,
            accountType: nil,
            isCreditCard: false,
            isArchived: false
        )

        let total = FinanceDynamicsPresentation.totalRow(from: [item], viewMode: .accounts)

        #expect(total?.deltaPercent == nil)
    }
}
