import Foundation
import Testing
@testable import millio

/// AC2: Accounts-тотал и Analytics-тотал получают вклад нового ядра из ОДНОЙ функции.
/// Здесь проверяется точка интеграции в `FinanceTotalsService` — `newCoreTotalProvider`
/// вызывается и его результат складывается со старым миром (а не отбрасывается/дублируется).
@Suite("FinanceTotalsService + AccountsCore")
struct FinanceTotalsServiceAccountsCoreTests {

    @Test @MainActor
    func totalsSnapshotAddsNewCoreContributionOnTopOfOldWorld() async {
        let service = FinanceTotalsService(
            currencyService: MockDynamicsCurrencyRateService(),
            groupsProvider: { [] }, // старый мир пуст — изолируем вклад нового ядра
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [:] },
            creditByIDProvider: { [:] },
            investmentByIDProvider: { [:] },
            newCoreTotalProvider: { currency in
                currency == "RUB" ? 12_345 : 0
            }
        )

        let snapshot = await service.calculateTotalsSnapshot()
        #expect(snapshot.totalAmount == 12_345)
    }

    @Test @MainActor
    func totalsSnapshotDefaultsToZeroWithoutProvider() async {
        // Провайдер по умолчанию (не передан) — старое поведение не меняется для существующих
        // вызывающих кодов, которые ещё не знают про новое ядро (регрессия исключена).
        let service = FinanceTotalsService(
            currencyService: MockDynamicsCurrencyRateService(),
            groupsProvider: { [] },
            displayCurrencyProvider: { "RUB" },
            secondaryDisplayCurrencyProvider: { nil },
            cardByIDProvider: { [:] },
            creditByIDProvider: { [:] },
            investmentByIDProvider: { [:] }
        )

        let snapshot = await service.calculateTotalsSnapshot()
        #expect(snapshot.totalAmount == 0)
    }
}
