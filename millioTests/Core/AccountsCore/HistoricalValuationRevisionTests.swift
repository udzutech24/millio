import Foundation
import Testing
@testable import millio

@Suite("Historical valuation revisions")
struct HistoricalValuationRevisionTests {
    @Test @MainActor
    func valuationRelevantMutationsChangeOnlyDeclaredRevisionDimensions() {
        let account = Account(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Account",
            kind: .cash,
            currency: "RUB",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let event = AccountEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            account: account,
            date: Date(timeIntervalSince1970: 1_700_000_100),
            createdAt: Date(timeIntervalSince1970: 1_700_000_101),
            type: .openingBalance,
            amount: 100
        )

        let baseline = HistoricalValuationRevisionBuilder.build(accounts: [account], eventsByAccountID: [account.id: [event]])

        event.amount = 101
        let eventChanged = HistoricalValuationRevisionBuilder.build(accounts: [account], eventsByAccountID: [account.id: [event]])
        #expect(eventChanged.events != baseline.events)
        #expect(eventChanged.accountSet == baseline.accountSet)
        #expect(eventChanged.financial == baseline.financial)

        event.amount = 100
        account.includeInTotal = false
        let membershipChanged = HistoricalValuationRevisionBuilder.build(accounts: [account], eventsByAccountID: [account.id: [event]])
        #expect(membershipChanged.accountSet != baseline.accountSet)
        #expect(membershipChanged.financial == baseline.financial)

        account.includeInTotal = true
        account.cardMeta = CardMeta(
            bank: nil, last4: nil, creditLimit: 1_000, statementDay: nil,
            dueDay: nil, minPayment: nil, graceDays: nil, overdraftLimit: nil
        )
        let financialChanged = HistoricalValuationRevisionBuilder.build(accounts: [account], eventsByAccountID: [account.id: [event]])
        #expect(financialChanged.financial != baseline.financial)
        #expect(financialChanged.accountSet == baseline.accountSet)

        let evidenceChanged = HistoricalValuationRevisionBuilder.build(
            accounts: [account], eventsByAccountID: [account.id: [event]], evidenceRevision: 42
        )
        #expect(evidenceChanged.evidence == 42)
    }

    @Test @MainActor
    func optionalProductIdentityAndPersistedBumpsParticipateInCanonicalRevision() {
        let account = Account(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            name: "Legacy",
            kind: .cash,
            productType: nil,
            currency: "RUB"
        )
        let baseline = HistoricalValuationRevisionBuilder.build(
            accounts: [account],
            eventsByAccountID: [account.id: []]
        )

        account.productType = .unknownLegacy
        account.productMigrationReason = "ambiguous_cash"
        let classified = HistoricalValuationRevisionBuilder.build(
            accounts: [account],
            eventsByAccountID: [account.id: []]
        )
        #expect(classified.financial != baseline.financial)
        #expect(classified.accountSet == baseline.accountSet)
        #expect(classified.events == baseline.events)

        HistoricalValuationRevisionTracker.bump([.accountSet, .financial, .events], on: account)
        let bumped = HistoricalValuationRevisionBuilder.build(
            accounts: [account],
            eventsByAccountID: [account.id: []]
        )
        #expect(bumped.accountSet != classified.accountSet)
        #expect(bumped.financial != classified.financial)
        #expect(bumped.events != classified.events)
        #expect(account.valuationMembershipRevision == 1)
        #expect(account.valuationFinancialRevision == 1)
        #expect(account.valuationEventRevision == 1)
    }

    @Test
    func writerInventoryCoversEveryRevisionDimensionAndLifecycleGate() {
        let inventory = HistoricalValuationWriterInventory.entries
        let impacts = Set(inventory.flatMap(\.revisionImpacts))
        let readiness = Set(inventory.flatMap(\.readinessImpacts))

        #expect(impacts == Set(HistoricalValuationRevisionDimension.allCases))
        #expect(readiness == Set(HistoricalScopeOperation.allCases))
        #expect(Set(inventory.map(\.id)).count == inventory.count)
        #expect(inventory.allSatisfy { !$0.sourcePath.isEmpty && !$0.entryPoint.isEmpty })
    }

    @Test
    func derivedCacheWritersNeverAdvanceSourceRevisions() {
        let cacheWriters = HistoricalValuationWriterInventory.entries.filter { $0.kind == .derivedCache }
        #expect(!cacheWriters.isEmpty)
        #expect(cacheWriters.allSatisfy { $0.revisionImpacts.isEmpty })
    }

    @Test
    func evidenceRevisionIncludesEverySelectedProvenanceField() {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let baseline = provenanceResult(.init(
            sourceID: "provider-a",
            recordID: "record-a",
            evidenceDayKey: "2026-08-07",
            observedAt: observedAt,
            calendarPolicyID: "calendar-a"
        ))
        let baselineDigest = HistoricalValuationEvidenceRevision.digest([baseline])
        let variants = [
            HistoricalValuationResolutionProvenance(
                sourceID: "provider-b", recordID: "record-a", evidenceDayKey: "2026-08-07",
                observedAt: observedAt, calendarPolicyID: "calendar-a"
            ),
            HistoricalValuationResolutionProvenance(
                sourceID: "provider-a", recordID: "record-b", evidenceDayKey: "2026-08-07",
                observedAt: observedAt, calendarPolicyID: "calendar-a"
            ),
            HistoricalValuationResolutionProvenance(
                sourceID: "provider-a", recordID: "record-a", evidenceDayKey: "2026-08-06",
                observedAt: observedAt, calendarPolicyID: "calendar-a"
            ),
            HistoricalValuationResolutionProvenance(
                sourceID: "provider-a", recordID: "record-a", evidenceDayKey: "2026-08-07",
                observedAt: observedAt.addingTimeInterval(1), calendarPolicyID: "calendar-a"
            ),
            HistoricalValuationResolutionProvenance(
                sourceID: "provider-a", recordID: "record-a", evidenceDayKey: "2026-08-07",
                observedAt: observedAt, calendarPolicyID: "calendar-b"
            )
        ]

        #expect(variants.allSatisfy {
            HistoricalValuationEvidenceRevision.digest([provenanceResult($0)]) != baselineDigest
        })
    }

    private func provenanceResult(
        _ provenance: HistoricalValuationResolutionProvenance
    ) -> HistoricalValuationContributionResolution {
        .init(
            requestID: "account-a",
            origin: .core,
            value: 900,
            quality: .fallback,
            dependencies: [.init(
                dimension: .fxRate,
                requestedDayKey: "2026-08-08",
                kind: .previousClose,
                value: 90,
                provenance: provenance,
                reasonCode: nil
            )],
            unresolvedDimensions: []
        )
    }
}
