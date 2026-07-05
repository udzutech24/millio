import Foundation
import Testing
@testable import millio

/// Юнит-тесты канонической политики участия legacy-счёта в net-total.
/// Покрывает ровно те edge cases, которые раньше расходились между Dynamics и TotalsService —
/// см. plans/2026-07-05__unified-totals.md.
struct AccountTotalPolicyTests {

    // MARK: - isActive

    @Test("Обычный активный счёт (includeInTotal=true, не архивирован) — участвует")
    func activeAccountIsIncluded() {
        #expect(
            AccountTotalPolicy.isActive(includeInTotal: true, archivedAt: nil, at: Date()) == true
        )
    }

    @Test("Счёт с includeInTotal=false — не участвует независимо от архивации")
    func excludedByFlagRegardlessOfArchive() {
        #expect(
            AccountTotalPolicy.isActive(includeInTotal: false, archivedAt: nil, at: Date()) == false
        )
    }

    @Test("Счёт архивирован СТРОГО ПОЗЖЕ запрашиваемой даты — на эту дату ещё активен (time-aware история)")
    func archivedInFutureRelativeToDateIsStillActive() {
        let date = Date()
        let archivedAt = date.addingTimeInterval(3600) // архив через час после запрашиваемой даты
        #expect(
            AccountTotalPolicy.isActive(includeInTotal: true, archivedAt: archivedAt, at: date) == true
        )
    }

    @Test("Счёт архивирован РАНЬШЕ запрашиваемой даты — не участвует")
    func archivedInPastRelativeToDateIsExcluded() {
        let date = Date()
        let archivedAt = date.addingTimeInterval(-3600)
        #expect(
            AccountTotalPolicy.isActive(includeInTotal: true, archivedAt: archivedAt, at: date) == false
        )
    }

    @Test("Дата запроса РОВНО совпадает с archivedAt — ещё участвует (граница строго `date > archivedAt`, не `>=`)")
    func exactArchiveMomentIsStillIncluded() {
        let date = Date()
        #expect(
            AccountTotalPolicy.isActive(includeInTotal: true, archivedAt: date, at: date) == true
        )
    }

    // MARK: - signedContribution

    @Test("Liability-счёт с debtAsNegative=true — сумма становится отрицательной")
    func liabilityWithNetTotalsBecomesNegative() {
        #expect(
            AccountTotalPolicy.signedContribution(1000, isLiability: true, debtAsNegative: true) == -1000
        )
    }

    @Test("Liability-счёт с debtAsNegative=false (просмотр одного счёта) — знак не меняется")
    func liabilityWithoutNetTotalsKeepsSign() {
        #expect(
            AccountTotalPolicy.signedContribution(1000, isLiability: true, debtAsNegative: false) == 1000
        )
    }

    @Test("Не-liability счёт с debtAsNegative=true — знак не меняется")
    func nonLiabilityKeepsSignRegardlessOfNetTotals() {
        #expect(
            AccountTotalPolicy.signedContribution(1000, isLiability: false, debtAsNegative: true) == 1000
        )
    }

    @Test("Liability-сумма уже отрицательная (edge case) — берём abs, знак остаётся минус")
    func liabilityNegativeInputStaysNegative() {
        #expect(
            AccountTotalPolicy.signedContribution(-500, isLiability: true, debtAsNegative: true) == -500
        )
    }
}
