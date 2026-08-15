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
        let valuation = try HistoricalPortfolioValuation.make(
            from: closedValuation(scopeID: "guest"),
            publishedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )
        context.insert(group)
        context.insert(account)
        context.insert(valuation)
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
        let valuation = try HistoricalPortfolioValuation.make(
            from: closedValuation(scopeID: "guest"),
            publishedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )
        context.insert(account)
        context.insert(event)
        context.insert(group)
        context.insert(valuation)
        try context.save()

        let input = try ScopeMergeReader.readGuestInput(context: context)
        let json = try JSONSerialization.jsonObject(with: input.legacyData) as? [String: Any]
        let models = try #require(json?["models"] as? [[String: Any]])
        let types = Set(models.compactMap { $0["_type"] as? String })

        #expect(types.isDisjoint(with: ScopeMergeReader.newCoreTypeNames))
        // New-core всё равно участвует в merge — но через NewCoreSnapshot (copyNewCore), не legacyData.
        #expect(input.newCore.accounts.count == 1)
        #expect(input.newCore.groups.count == 1)
        #expect(!types.contains("HistoricalPortfolioValuation"))
    }

    @Test("destination rebuild queue is durable and idempotent")
    func destinationRebuildQueue() throws {
        let suiteName = "HistoricalValuationRebuildQueueTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let secondDate = firstDate.addingTimeInterval(1)

        let first = try HistoricalValuationRebuildQueue.enqueue(
            scopeID: "user-scope",
            reasonCode: "guest_reconciliation",
            enqueuedAt: firstDate,
            defaults: defaults
        )
        let second = try HistoricalValuationRebuildQueue.enqueue(
            scopeID: "user-scope",
            reasonCode: "guest_reconciliation",
            enqueuedAt: secondDate,
            defaults: defaults
        )

        #expect(try HistoricalValuationRebuildQueue.pending(
            scopeID: "user-scope", defaults: defaults
        )?.enqueuedAt == secondDate)
        #expect(try !HistoricalValuationRebuildQueue.acknowledge(first, defaults: defaults))
        #expect(try HistoricalValuationRebuildQueue.acknowledge(second, defaults: defaults))
        #expect(try HistoricalValuationRebuildQueue.pending(
            scopeID: "user-scope", defaults: defaults
        ) == nil)
    }

    @Test("corrupted rebuild marker fails closed")
    func corruptedRebuildMarker() throws {
        let suiteName = "HistoricalValuationRebuildQueueCorruption.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scopeID = "user-scope"
        let key = "historicalValuation.rebuild.v1." + Data(scopeID.utf8).base64EncodedString()
        defaults.set(Data("not-json".utf8), forKey: key)

        #expect(throws: HistoricalValuationRebuildQueueError.corruptedMarker) {
            _ = try HistoricalValuationRebuildQueue.pending(
                scopeID: scopeID,
                defaults: defaults
            )
        }
    }

    private func closedValuation(scopeID: String) -> HistoricalValuationResult {
        HistoricalValuationResult(
            key: .init(
                schemaVersion: HistoricalPortfolioValuation.storageSchemaVersion,
                scopeID: scopeID,
                dayKey: "2026-08-07",
                timeZoneID: "Europe/Istanbul",
                displayCurrency: "RUB",
                valuationPolicyVersion: 1,
                inputRevision: .init(accountSet: 1, financial: 2, events: 3, evidence: 4)
            ),
            diagnosticPartialTotal: 100,
            finality: .closed,
            quality: .exact,
            expectedContributionCount: 1,
            resolvedContributionCount: 1,
            unresolved: [],
            resolutions: [.init(
                opaqueAccountID: "opaque-account",
                dimension: .fxRate,
                kind: "nativeParity"
            )],
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}
