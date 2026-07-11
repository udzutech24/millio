import Testing
@testable import millio

/// Гейт 5c.7.6.2 — чистая логика бакетирования групп «Счетов» на секции «Активы»/«Обязательства».
@Suite("FinanceAccountsSectionSplitter")
struct FinanceAccountsSectionSplitterTests {

    @Test("Инвариант: сумма подытогов секций == сумма всех входов (группы + Ungrouped)")
    func subtotalsSumMatchesInputTotal() {
        let totals: [String: Double] = ["a": 500_000, "b": -300_000, "c": 120_000]
        let ungrouped: Double = 150_000
        let split = FinanceAccountsSectionSplitter.split(
            orderedGroupIDs: ["a", "b", "c"],
            totalsInPrimaryCurrency: totals,
            ungroupedTotal: ungrouped
        )
        let inputSum = totals.values.reduce(0, +) + ungrouped
        let sectionsSum = split.assets.subtotal + split.liabilities.subtotal
        #expect(abs(sectionsSum - inputSum) < 0.0001)
    }

    @Test("Положительный net-тотал группы → секция «Активы»; отрицательный → «Обязательства»")
    func classifiesBySign() {
        let split = FinanceAccountsSectionSplitter.split(
            orderedGroupIDs: ["asset-group", "liability-group"],
            totalsInPrimaryCurrency: ["asset-group": 1_000, "liability-group": -1_000],
            ungroupedTotal: nil
        )
        #expect(split.assets.groupIDs == ["asset-group"])
        #expect(split.liabilities.groupIDs == ["liability-group"])
        #expect(split.assets.subtotal == 1_000)
        #expect(split.liabilities.subtotal == -1_000)
    }

    @Test("Нулевой net-тотал группы уходит в «Активы» (не теряется, не задваивается)")
    func zeroTotalGoesToAssets() {
        let split = FinanceAccountsSectionSplitter.split(
            orderedGroupIDs: ["empty-net"],
            totalsInPrimaryCurrency: ["empty-net": 0],
            ungroupedTotal: nil
        )
        #expect(split.assets.groupIDs == ["empty-net"])
        #expect(split.liabilities.groupIDs.isEmpty)
    }

    @Test("Ungrouped nil (бакета нет) — не участвует ни в одной секции, ungroupedInAssets == nil")
    func nilUngroupedIsExcluded() {
        let split = FinanceAccountsSectionSplitter.split(
            orderedGroupIDs: ["a"],
            totalsInPrimaryCurrency: ["a": 100],
            ungroupedTotal: nil
        )
        #expect(split.ungroupedInAssets == nil)
        #expect(split.assets.subtotal == 100)
    }

    @Test("Ungrouped с отрицательным net уходит в «Обязательства»")
    func negativeUngroupedGoesToLiabilities() {
        let split = FinanceAccountsSectionSplitter.split(
            orderedGroupIDs: [],
            totalsInPrimaryCurrency: [:],
            ungroupedTotal: -50
        )
        #expect(split.ungroupedInAssets == false)
        #expect(split.liabilities.subtotal == -50)
        #expect(split.assets.subtotal == 0)
    }

    @Test("Порядок групп внутри секции сохраняется (не пересортировывается сплиттером)")
    func preservesOrderWithinSection() {
        let split = FinanceAccountsSectionSplitter.split(
            orderedGroupIDs: ["z", "a", "m"],
            totalsInPrimaryCurrency: ["z": 10, "a": 20, "m": 30],
            ungroupedTotal: nil
        )
        #expect(split.assets.groupIDs == ["z", "a", "m"])
    }

    @Test("Все группы — обязательства (пустой массив активов, не крашится)")
    func allLiabilities() {
        let split = FinanceAccountsSectionSplitter.split(
            orderedGroupIDs: ["a", "b"],
            totalsInPrimaryCurrency: ["a": -10, "b": -20],
            ungroupedTotal: nil
        )
        #expect(split.assets.groupIDs.isEmpty)
        #expect(split.assets.subtotal == 0)
        #expect(split.liabilities.subtotal == -30)
    }

    @Test("Пустой вход (нет групп, нет Ungrouped) — обе секции пусты")
    func emptyInput() {
        let split = FinanceAccountsSectionSplitter.split(
            orderedGroupIDs: [],
            totalsInPrimaryCurrency: [:],
            ungroupedTotal: nil
        )
        #expect(split.assets.groupIDs.isEmpty)
        #expect(split.liabilities.groupIDs.isEmpty)
        #expect(split.ungroupedInAssets == nil)
    }
}
