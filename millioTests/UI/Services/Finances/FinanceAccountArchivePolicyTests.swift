import Testing
@testable import millio

struct FinanceAccountArchivePolicyTests {
    @Test("Счёт с положительным балансом требует предупреждения")
    func positiveBalanceTriggerWarning() {
        #expect(
            FinanceAccountArchivePolicy.shouldShowBalanceWarning(balance: 138.0) == true
        )
    }

    @Test("Счёт с нулевым балансом не требует предупреждения")
    func zeroBalanceNoWarning() {
        #expect(
            FinanceAccountArchivePolicy.shouldShowBalanceWarning(balance: 0.0) == false
        )
    }

    @Test("Кредит с долгом (отрицательный баланс) требует предупреждения")
    func negativeBalanceTriggerWarning() {
        #expect(
            FinanceAccountArchivePolicy.shouldShowBalanceWarning(balance: -5000.0) == true
        )
    }

    @Test("Баланс меньше порога (менее 0.01) не требует предупреждения")
    func belowThresholdNoWarning() {
        #expect(
            FinanceAccountArchivePolicy.shouldShowBalanceWarning(balance: 0.005) == false
        )
    }

    @Test("Баланс ровно на пороге (0.01) требует предупреждения")
    func exactThresholdTriggerWarning() {
        #expect(
            FinanceAccountArchivePolicy.shouldShowBalanceWarning(balance: 0.01) == true
        )
    }
}
