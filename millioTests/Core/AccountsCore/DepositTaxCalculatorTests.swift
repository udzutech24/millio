import Foundation
import Testing
@testable import millio

/// Фаза 3 (S7, план §2.8): налог «чистыми» на проценты по вкладам — расчёт против РУЧНОГО вычисления
/// (обязательный тест брифинга) на двух вкладах, распределение превышения лимита пропорционально.
@Suite("DepositTaxCalculator")
struct DepositTaxCalculatorTests {

    // MARK: - Ручной расчёт: вклад A 16 875 000 ₽ @16% (проценты 2 700 000), вклад B 30 000 000 ₽ @15% (4 500 000)

    @Test
    func calculateMatchesManualNumbersForTwoDeposits() {
        let accountA = UUID()
        let accountB = UUID()

        let settings = DepositTaxSettings(ndflRatePercent: 13, keyRateForYear: 0.16)
        let result = DepositTaxCalculator.calculate(
            interestEventsInRUB: [
                .init(accountID: accountA, amountRUB: 2_700_000),
                .init(accountID: accountB, amountRUB: 4_500_000),
            ],
            year: 2025,
            settings: settings
        )

        // Лимит = 1 000 000 × 0.16 = 160 000.
        #expect(result.taxFreeLimitRUB == 160_000)
        // Σ процентов = 7 200 000.
        #expect(result.totalGrossInterestRUB == 7_200_000)
        // Превышение = 7 200 000 − 160 000 = 7 040 000.
        #expect(result.taxableExcessRUB == 7_040_000)
        // Налог = 7 040 000 × 13% = 915 200.
        #expect(result.totalTaxRUB == 915_200)

        #expect(result.perAccount.count == 2)
        let allocationA = result.perAccount.first { $0.accountID == accountA }
        let allocationB = result.perAccount.first { $0.accountID == accountB }

        // Доля A = 2 700 000 / 7 200 000 = 3/8 → превышение 7 040 000 × 3/8 = 2 640 000, налог 343 200.
        #expect(allocationA?.allocatedExcessRUB == 2_640_000)
        #expect(allocationA?.allocatedTaxRUB == 343_200)
        // Доля B = 5/8 → превышение 4 400 000, налог 572 000.
        #expect(allocationB?.allocatedExcessRUB == 4_400_000)
        #expect(allocationB?.allocatedTaxRUB == 572_000)

        // Сумма распределённых долей = общей сумме (без потерь на округлении в этом наборе чисел).
        #expect((allocationA?.allocatedExcessRUB ?? 0) + (allocationB?.allocatedExcessRUB ?? 0) == result.taxableExcessRUB)
        #expect((allocationA?.allocatedTaxRUB ?? 0) + (allocationB?.allocatedTaxRUB ?? 0) == result.totalTaxRUB)
    }

    // MARK: - Ниже лимита — налога нет

    @Test
    func belowLimitProducesNoTax() {
        let account = UUID()
        let settings = DepositTaxSettings(ndflRatePercent: 13, keyRateForYear: 0.16)
        let result = DepositTaxCalculator.calculate(
            interestEventsInRUB: [.init(accountID: account, amountRUB: 100_000)],
            year: 2025,
            settings: settings
        )
        #expect(result.taxableExcessRUB == 0)
        #expect(result.totalTaxRUB == 0)
        #expect(result.perAccount.first?.allocatedTaxRUB == 0)
    }

    // MARK: - Нет процентов вовсе — пустой результат, без деления на ноль

    @Test
    func noInterestEventsProducesEmptyResult() {
        let settings = DepositTaxSettings.default
        let result = DepositTaxCalculator.calculate(interestEventsInRUB: [], year: 2025, settings: settings)
        #expect(result.totalGrossInterestRUB == 0)
        #expect(result.totalTaxRUB == 0)
        #expect(result.perAccount.isEmpty)
    }
}
