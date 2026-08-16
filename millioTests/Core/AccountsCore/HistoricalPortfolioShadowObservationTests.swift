import Foundation
import Testing
@testable import millio

@Suite("Historical portfolio shadow observation")
struct HistoricalPortfolioShadowObservationTests {
    @Test("cutover rejects silent drop, mismatch and unexplained numeric delta")
    func rejectsUnsafeObservationWindow() {
        let incomplete = observation(result: result(total: nil, expected: 2, resolved: 1), old: 10, oldCount: 1)
        let mismatch = observation(result: result(total: 10, expected: 2, resolved: 2), old: 10, oldCount: 1)
        let unexplained = observation(result: result(total: 12, expected: 2, resolved: 2), old: 10, oldCount: 2)

        let gate = HistoricalPortfolioCutoverGate.evaluate([incomplete, mismatch, unexplained])

        #expect(!gate.isApproved)
        #expect(gate.silentDropCount == 1)
        #expect(gate.accountSetMismatchCount == 1)
        #expect(gate.unexplainedDeltaCount == 1)
    }

    @Test("cutover accepts non-empty fully classified observation window")
    func acceptsClassifiedWindow() {
        let exact = observation(result: result(total: 10, expected: 1, resolved: 1), old: 10, oldCount: 1)
        let corrected = observation(result: result(total: 12, expected: 1, resolved: 1), old: 10, oldCount: 1,
                                    expectedCorrection: true)

        let gate = HistoricalPortfolioCutoverGate.evaluate([exact, corrected])

        #expect(gate.isApproved)
        #expect(exact.reason == .exact)
        #expect(corrected.reason == .expectedResolverCorrection)
    }

    @Test("structured reader cannot be selected before an accepted observation window")
    func cutoverTransitionIsFailClosed() {
        let defaults = UserDefaults(suiteName: "HistoricalPortfolioCutover.\(UUID().uuidString)")!
        // No persisted approval means no cutover. A new or restored scope must keep the
        // compatibility pixels while the structured reader collects its observation evidence.
        #expect(HistoricalPortfolioReaderConfiguration.current(defaults: defaults).mode == .shadow)
        defaults.set(HistoricalPortfolioReaderMode.structured.rawValue,
                     forKey: HistoricalPortfolioReaderConfiguration.userDefaultsKey)
        #expect(HistoricalPortfolioReaderConfiguration.current(defaults: defaults).mode == .shadow)

        let rejected = HistoricalPortfolioCutoverGate(
            observationCount: 1, silentDropCount: 1, unexplainedDeltaCount: 0,
            accountSetMismatchCount: 0
        )
        #expect(!HistoricalPortfolioReaderConfiguration.approveStructuredCutover(
            gate: rejected, defaults: defaults
        ))
        #expect(HistoricalPortfolioReaderConfiguration.current(defaults: defaults).mode == .shadow)

        let accepted = HistoricalPortfolioCutoverGate(
            observationCount: 2, silentDropCount: 0, unexplainedDeltaCount: 0,
            accountSetMismatchCount: 0
        )
        #expect(HistoricalPortfolioReaderConfiguration.approveStructuredCutover(
            gate: accepted, defaults: defaults
        ))
        #expect(HistoricalPortfolioReaderConfiguration.current(defaults: defaults).mode == .structured)
    }

    @Test("durable cutover requires days, device transitions and an offline transition")
    func durableMeaningfulWindow() {
        let defaults = UserDefaults(suiteName: "HistoricalPortfolioShadowWindow.\(UUID().uuidString)")!
        let readerDefaults = UserDefaults(suiteName: "HistoricalPortfolioShadowReader.\(UUID().uuidString)")!
        let store = HistoricalPortfolioShadowEvidenceStore(defaults: defaults)
        let exact = observation(result: result(total: 10, expected: 1, resolved: 1), old: 10, oldCount: 1)
        let policy = HistoricalPortfolioShadowWindowPolicy(
            minimumObservations: 3,
            minimumDistinctDays: 2,
            minimumDeviceTransitions: 2,
            requiresOfflineTransition: true
        )
        store.append(.init(observation: exact, dayKey: "2026-08-07", transitionID: "transition-a", wasOffline: false))
        store.append(.init(observation: exact, dayKey: "2026-08-08", transitionID: "transition-a", wasOffline: false))
        store.append(.init(observation: exact, dayKey: "2026-08-08", transitionID: "transition-b", wasOffline: false))

        #expect(!store.approveStructuredCutover(policy: policy, readerDefaults: readerDefaults))
        store.append(.init(observation: exact, dayKey: "2026-08-08", transitionID: "transition-b", wasOffline: true))

        #expect(store.approveStructuredCutover(policy: policy, readerDefaults: readerDefaults))
        #expect(HistoricalPortfolioReaderConfiguration.current(defaults: readerDefaults).mode == .structured)
        #expect(HistoricalPortfolioShadowEvidenceStore(defaults: defaults).window().gate.observationCount == 4)
    }

    private func observation(
        result: HistoricalValuationResult,
        old: Decimal?,
        oldCount: Int?,
        expectedCorrection: Bool = false
    ) -> HistoricalPortfolioShadowObservation {
        .classify(structured: result, compatibilityTotal: old,
                  compatibilityContributionCount: oldCount,
                  hasExpectedResolverCorrection: expectedCorrection)
    }

    private func result(total: Decimal?, expected: Int, resolved: Int) -> HistoricalValuationResult {
        HistoricalValuationResult(
            key: HistoricalValuationKey(
                schemaVersion: 7, scopeID: "guest", dayKey: "2026-08-07",
                timeZoneID: "Europe/Istanbul", displayCurrency: "USD",
                valuationPolicyVersion: 1,
                inputRevision: .init(accountSet: 0, financial: 0, events: 0, evidence: 0)
            ),
            diagnosticPartialTotal: total ?? 0,
            finality: .closed,
            quality: total == nil ? .unavailable : .exact,
            expectedContributionCount: expected,
            resolvedContributionCount: resolved,
            unresolved: total == nil ? [
                .init(opaqueAccountID: "missing", dimension: .fxRate, reasonCode: "offline")
            ] : [],
            resolutions: [],
            generatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}
