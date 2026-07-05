import Foundation
import SwiftData
import Testing
@testable import millio

/// Инвариант закрытия release-блокера ModelTypeRegistry: регистрация new-core моделей ради полного
/// CloudKit backup НЕ должна протечь в `legacyData` reconciliation (Track B) — единственный merge-путь
/// для Account/AccountEvent/AccountGroup/AccountDailySnapshot остаётся `ScopeMergeDedup.copyNewCore`
/// (спека §0.4). См. `ScopeMergeReader.newCoreTypeNames`, `AccountsCoreFeatureRegistration`.
@Suite(.serialized)
@MainActor
struct ScopeMergeReaderExclusionTests {

    private func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: AppSchema.create(), configurations: [config])
    }

    @Test("exportAllData(excluding:) не включает исключённые типы в результат")
    func testExportAllDataExcludesGivenTypeNames() throws {
        let state = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(state) }
        FinanceFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()

        let container = makeContainer()
        let context = container.mainContext
        let group = AccountGroup(name: "Тест")
        let account = Account(name: "Счёт", kind: .cash)
        context.insert(group)
        context.insert(account)
        try context.save()

        let data = try DataRepository.exportAllData(from: context, excluding: ScopeMergeReader.newCoreTypeNames)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = try #require(json?["models"] as? [[String: Any]])
        let types = Set(models.compactMap { $0["_type"] as? String })

        #expect(types.isDisjoint(with: ScopeMergeReader.newCoreTypeNames))
    }

    @Test("readGuestInput().legacyData не содержит new-core типы, даже когда они зарегистрированы в ModelTypeRegistry")
    func testReadGuestInputLegacyDataNeverContainsNewCoreTypes() throws {
        let state = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(state) }
        FinanceFeatureRegistration.register()
        CashflowFeatureRegistration.register()
        CardFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        CashbackFeatureRegistration.register()
        UserSubscriptionsFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()

        let container = makeContainer()
        let context = container.mainContext
        let account = Account(name: "Счёт", kind: .cash)
        let event = AccountEvent(account: account, date: Date(), type: .openingBalance, amount: 100)
        let group = AccountGroup(name: "Группа")
        context.insert(account)
        context.insert(event)
        context.insert(group)
        try context.save()

        let input = try ScopeMergeReader.readGuestInput(context: context)
        let json = try JSONSerialization.jsonObject(with: input.legacyData) as? [String: Any]
        let models = try #require(json?["models"] as? [[String: Any]])
        let types = Set(models.compactMap { $0["_type"] as? String })

        #expect(types.isDisjoint(with: ScopeMergeReader.newCoreTypeNames))
        // New-core всё равно участвует в merge — но через NewCoreSnapshot (copyNewCore), не legacyData.
        #expect(input.newCore.accounts.count == 1)
        #expect(input.newCore.groups.count == 1)
    }
}
