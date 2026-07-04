import Foundation
import Testing
@testable import millio

/// S8 (риск плана): решение «предупредить перед архивацией ненулевого счёта» — чистая логика,
/// без UI (проверяем по Decimal, не по Double — новое ядро считает всё в Decimal, Т9 в плане).
struct AccountArchivePolicyTests {
    @Test("Положительный баланс требует предупреждения")
    func positiveBalanceTriggersWarning() {
        #expect(AccountArchivePolicy.shouldWarnBeforeArchiving(balance: 138) == true)
    }

    @Test("Отрицательный баланс (долг/кредит) требует предупреждения")
    func negativeBalanceTriggersWarning() {
        #expect(AccountArchivePolicy.shouldWarnBeforeArchiving(balance: -5000) == true)
    }

    @Test("Нулевой баланс не требует предупреждения")
    func zeroBalanceNoWarning() {
        #expect(AccountArchivePolicy.shouldWarnBeforeArchiving(balance: 0) == false)
    }

    @Test("Баланс ниже порога (< 0.01) не требует предупреждения")
    func belowThresholdNoWarning() {
        #expect(AccountArchivePolicy.shouldWarnBeforeArchiving(balance: 0.005) == false)
    }

    @Test("Баланс ровно на пороге (0.01) требует предупреждения — Decimal точен, без Double-дрейфа")
    func exactThresholdTriggersWarning() {
        #expect(AccountArchivePolicy.shouldWarnBeforeArchiving(balance: 0.01) == true)
    }
}
