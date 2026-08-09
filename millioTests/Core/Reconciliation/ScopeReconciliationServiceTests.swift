import Foundation
import SwiftData
import Testing
@testable import millio

/// B2c: оркестратор reconciliation (детектор → lineage → merge → маркер).
/// Кейсы спеки §5: чужой guest (lineage-fail → отложен) / нет расхождения / merged+done / fallback (без done).
@Suite(.serialized)
@MainActor
struct ScopeReconciliationServiceTests {

    private func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: AppSchema.create(), configurations: [config])
    }

    private func registerFeatures() {
        FinanceFeatureRegistration.register()
        CashflowFeatureRegistration.register()
        CardFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        CashbackFeatureRegistration.register()
        UserSubscriptionsFeatureRegistration.register()
    }

    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let fixedCreated = Date(timeIntervalSince1970: 1_600_000_000)

    /// Fingerprint определяется amount (date/createdAt фиксированы) — управляем идентичностью через сумму.
    private func insertTx(_ container: ModelContainer, amount: Double, updatedAt: TimeInterval) {
        let tx = CashflowTransaction(transactionType: .expense, amount: amount, currency: "RUB", transactionDate: fixedDate)
        tx.createdAt = fixedCreated
        tx.updatedAt = Date(timeIntervalSince1970: updatedAt)
        container.mainContext.insert(tx)
        try? container.mainContext.save()
    }

    private func insertHistoricalClose(_ container: ModelContainer, scopeID: String) {
        let close = HistoricalPortfolioValuation(
            logicalID: UUID().uuidString,
            schemaVersion: 7,
            scopeID: scopeID,
            dayKey: "2026-08-07",
            timeZoneID: "UTC",
            displayCurrency: "RUB",
            valuationPolicyVersion: 1,
            accountSetRevisionRaw: "1",
            financialRevisionRaw: "1",
            eventRevisionRaw: "1",
            evidenceRevisionRaw: "1",
            totalRaw: "100",
            diagnosticPartialTotalRaw: "100",
            stateRaw: HistoricalValuationState.complete.rawValue,
            finalityRaw: HistoricalValuationFinality.closed.rawValue,
            qualityRaw: HistoricalValuationQuality.exact.rawValue,
            publicationRaw: HistoricalValuationPublication.published.rawValue,
            expectedContributionCount: 1,
            resolvedContributionCount: 1,
            manifestData: Data(),
            generatedAt: fixedDate,
            publishedAt: fixedDate
        )
        container.mainContext.insert(close)
        try? container.mainContext.save()
    }

    private func uniqueUserScope() -> DataScope { .user(id: UUID().uuidString) }

    private func cleanup(_ scope: DataScope) {
        let key = scope.storeConfigurationName
        for prefix in ["reconciliation.done.", "reconciliation.report.", "reconciliation.needsConfirmation."] {
            UserDefaults.standard.removeObject(forKey: prefix + key)
        }
        if let request = try? HistoricalValuationRebuildQueue.pending(scopeID: key) {
            _ = try? HistoricalValuationRebuildQueue.acknowledge(request)
        }
        HistoricalValuationReadinessCoordinator.shared.resetForTesting()
    }

    private func count<T: PersistentModel>(_ type: T.Type, in container: ModelContainer) -> Int {
        (try? ModelContext(container).fetchCount(FetchDescriptor<T>())) ?? -1
    }

    private func run(guest: ModelContainer, user: ModelContainer, scope: DataScope, fallback: Bool = false) async -> ScopeMergeOutcome {
        await ScopeReconciliationService().reconcile(
            userContainer: user, userScope: scope, guestContainer: guest,
            userStoreURL: nil, guestStoreURL: nil, usedFallbackOpen: fallback,
            onWillMerge: {}
        )
    }

    private func withRegistry(_ body: () async throws -> Void) async throws {
        let state = ModelTypeRegistry.shared.captureState()
        registerFeatures()
        do { try await body() } catch { ModelTypeRegistry.shared.restoreState(state); throw error }
        ModelTypeRegistry.shared.restoreState(state)
    }

    // MARK: - Кейсы

    @Test func foreignGuest_deferredNotMerged() async throws {
        try await withRegistry {
            let scope = uniqueUserScope(); defer { cleanup(scope) }
            let guest = makeContainer(); let user = makeContainer()
            // Расхождение есть (guest.count > user), но идентичность непересекающаяся → чужой guest.
            insertTx(guest, amount: 11, updatedAt: 100)
            insertTx(guest, amount: 22, updatedAt: 100)
            insertTx(guest, amount: 33, updatedAt: 100)
            insertTx(user, amount: 99, updatedAt: 100)

            let outcome = await run(guest: guest, user: user, scope: scope)
            #expect(outcome == .deferredForeignGuest)
            #expect(count(CashflowTransaction.self, in: user) == 1) // не слито
            #expect(ScopeMergeMarker.needsConfirmation(userScopeKey: scope.storeConfigurationName))
            #expect(ScopeMergeMarker.isDone(userScopeKey: scope.storeConfigurationName) == false)
        }
    }

    @Test func noDivergence_marksDoneWithoutMerge() async throws {
        try await withRegistry {
            let scope = uniqueUserScope(); defer { cleanup(scope) }
            let guest = makeContainer(); let user = makeContainer()
            insertTx(guest, amount: 100, updatedAt: 100)
            insertTx(user, amount: 100, updatedAt: 100)

            let outcome = await run(guest: guest, user: user, scope: scope)
            #expect(outcome == .noDivergence)
            #expect(ScopeMergeMarker.isDone(userScopeKey: scope.storeConfigurationName))
        }
    }

    @Test func noDivergenceWithGuestClose_enqueuesDestinationRebuildWithoutCopyingClose() async throws {
        try await withRegistry {
            let scope = uniqueUserScope(); defer { cleanup(scope) }
            let guest = makeContainer(); let user = makeContainer()
            insertTx(guest, amount: 100, updatedAt: 100)
            insertTx(user, amount: 100, updatedAt: 100)
            insertHistoricalClose(guest, scopeID: DataScope.guest.storeConfigurationName)

            let outcome = await run(guest: guest, user: user, scope: scope)
            let pending = try HistoricalValuationRebuildQueue.pending(
                scopeID: scope.storeConfigurationName
            )

            #expect(outcome == .noDivergence)
            #expect(pending?.reasonCode == "guest_close_scope_rebuild")
            #expect(count(HistoricalPortfolioValuation.self, in: user) == 0)
            #expect(HistoricalValuationReadinessCoordinator.shared.readiness(
                scopeID: scope.storeConfigurationName
            ) == .ready)
        }
    }

    @Test func mergedHappyPath_marksDoneAndReportsCounts() async throws {
        try await withRegistry {
            let scope = uniqueUserScope(); defer { cleanup(scope) }
            let guest = makeContainer(); let user = makeContainer()
            insertTx(guest, amount: 100, updatedAt: 100) // общая база
            insertTx(guest, amount: 250, updatedAt: 150) // дельта
            insertTx(user, amount: 100, updatedAt: 100)

            let outcome = await run(guest: guest, user: user, scope: scope)
            guard case .merged(let report) = outcome else { Issue.record("ожидался .merged, получено \(outcome)"); return }
            #expect(report.transactionsAdded == 1)
            #expect(count(CashflowTransaction.self, in: user) == 2)
            #expect(ScopeMergeMarker.isDone(userScopeKey: scope.storeConfigurationName))

            // Simulate an older-build crash after durable done but before clearing process-local
            // readiness. The done fast path must heal that stale state.
            HistoricalValuationReadinessCoordinator.shared.fail(
                scopeID: scope.storeConfigurationName,
                operation: .reconciliation,
                reasonCode: "stale_reconciliation_failure"
            )
            let second = await run(guest: guest, user: user, scope: scope)
            #expect(second == .alreadyDone)
            #expect(count(CashflowTransaction.self, in: user) == 2)
            #expect(HistoricalValuationReadinessCoordinator.shared.readiness(
                scopeID: scope.storeConfigurationName
            ) == .ready)
        }
    }

    @Test func partiallyReadable_mergesButDoesNotMarkDone() async throws {
        try await withRegistry {
            let scope = uniqueUserScope(); defer { cleanup(scope) }
            let guest = makeContainer(); let user = makeContainer()
            insertTx(guest, amount: 100, updatedAt: 100)
            insertTx(guest, amount: 250, updatedAt: 150)
            insertTx(user, amount: 100, updatedAt: 100)

            let outcome = await run(guest: guest, user: user, scope: scope, fallback: true)
            guard case .merged = outcome else { Issue.record("ожидался .merged, получено \(outcome)"); return }
            // Митигация B1b №6: partially readable → done НЕ ставим (повтор при чистом открытии).
            #expect(ScopeMergeMarker.isDone(userScopeKey: scope.storeConfigurationName) == false)
            #expect(ScopeMergeMarker.storedReport(userScopeKey: scope.storeConfigurationName)?.partiallyReadable == true)
        }
    }

    @Test func rebuildEnqueueFailurePreventsCommitAndRetryCannotFallIntoFalseNoDivergence() async throws {
        struct EnqueueFailure: Error {}
        try await withRegistry {
            let scope = uniqueUserScope(); defer { cleanup(scope) }
            let guest = makeContainer(); let user = makeContainer()
            insertTx(guest, amount: 100, updatedAt: 100)
            insertTx(guest, amount: 250, updatedAt: 150)
            insertTx(user, amount: 100, updatedAt: 100)
            let service = ScopeReconciliationService { _, _ in throw EnqueueFailure() }

            let outcome = await service.reconcile(
                userContainer: user,
                userScope: scope,
                guestContainer: guest,
                userStoreURL: nil,
                guestStoreURL: nil,
                usedFallbackOpen: false,
                onWillMerge: {}
            )

            #expect(outcome == .skipped)
            #expect(count(CashflowTransaction.self, in: user) == 1)
            #expect(!ScopeMergeMarker.isDone(userScopeKey: scope.storeConfigurationName))
            #expect(HistoricalValuationReadinessCoordinator.shared.readiness(
                scopeID: scope.storeConfigurationName
            ) == .failed(reasonCode: "reconciliation_failed"))

            let retry = await run(guest: guest, user: user, scope: scope)
            guard case .merged(let report) = retry else {
                Issue.record("повтор должен выполнить merge, получено \(retry)")
                return
            }
            let pending = try HistoricalValuationRebuildQueue.pending(
                scopeID: scope.storeConfigurationName
            )
            #expect(report.transactionsAdded == 1)
            #expect(count(CashflowTransaction.self, in: user) == 2)
            #expect(pending?.reasonCode == "guest_reconciliation")
        }
    }
}
