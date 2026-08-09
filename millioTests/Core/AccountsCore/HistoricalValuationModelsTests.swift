import Foundation
import Testing
@testable import millio

@Suite("Historical valuation models")
struct HistoricalValuationModelsTests {
    private let revision = HistoricalValuationInputRevision(
        accountSet: 1, financial: 2, events: 3, evidence: 4
    )

    private func key(timeZoneID: String = "Europe/Istanbul") -> HistoricalValuationKey {
        HistoricalValuationKey(
            schemaVersion: 6,
            scopeID: "guest",
            dayKey: "2026-08-08",
            timeZoneID: timeZoneID,
            displayCurrency: "RUB",
            valuationPolicyVersion: 1,
            inputRevision: revision
        )
    }

    @Test
    func incompleteCoverageHasNoPublicTotal() {
        let unresolved = HistoricalValuationUnresolvedContribution(
            opaqueAccountID: "opaque-1", dimension: .fxRate, reasonCode: "missing"
        )
        let result = HistoricalValuationResult(
            key: key(),
            diagnosticPartialTotal: 77_125_067,
            finality: .closed,
            quality: .unavailable,
            expectedContributionCount: 2,
            resolvedContributionCount: 1,
            unresolved: [unresolved],
            resolutions: [],
            generatedAt: .distantPast
        )

        #expect(result.state == .incomplete)
        #expect(result.total == nil)
        #expect(result.diagnosticPartialTotal == 77_125_067)
    }

    @Test
    func completeFallbackIsIndependentFromFinalityAndCoverage() {
        let result = HistoricalValuationResult(
            key: key(),
            diagnosticPartialTotal: 99_633_041,
            finality: .closed,
            quality: .fallback,
            expectedContributionCount: 2,
            resolvedContributionCount: 2,
            unresolved: [],
            resolutions: [.init(kind: "frozenClose", sourceID: "rate-1")],
            generatedAt: .distantPast
        )

        #expect(result.state == .complete)
        #expect(result.finality == .closed)
        #expect(result.quality == .fallback)
        #expect(result.total == 99_633_041)
    }

    @Test
    func completeOpenDayIsProvisional() {
        let result = HistoricalValuationResult(
            key: key(),
            diagnosticPartialTotal: 0,
            finality: .open,
            quality: .exact,
            expectedContributionCount: 1,
            resolvedContributionCount: 1,
            unresolved: [],
            resolutions: [],
            generatedAt: .distantPast
        )

        #expect(result.state == .provisional)
        #expect(result.total == 0)
    }

    @Test
    func frozenTimezoneHasExplicitIdentityAcrossDeviceTimezoneChoices() throws {
        let istanbul = try #require(HistoricalValuationTimeContext(ianaTimeZoneID: "Europe/Istanbul"))
        let losAngeles = try #require(HistoricalValuationTimeContext(ianaTimeZoneID: "America/Los_Angeles"))
        let instant = Date(timeIntervalSince1970: 1_786_150_800) // 2026-08-08 01:00:00 UTC

        #expect(istanbul.dayKey(for: instant) == "2026-08-08")
        #expect(losAngeles.dayKey(for: instant) == "2026-08-07")
        #expect(istanbul.timeZoneID == "Europe/Istanbul")
        #expect(losAngeles.timeZoneID == "America/Los_Angeles")
        #expect(HistoricalValuationTimeContext(ianaTimeZoneID: "GMT+03:00") == nil)
    }

    @Test(arguments: [
        ("America/New_York", 2026, 3, 8, 23),
        ("America/New_York", 2026, 11, 1, 25),
        ("Europe/Istanbul", 2026, 3, 8, 24)
    ])
    func frozenGregorianDayHasCorrectDSTLength(
        timeZoneID: String,
        year: Int,
        month: Int,
        day: Int,
        expectedHours: Int
    ) throws {
        let timeZone = try #require(TimeZone(identifier: timeZoneID))
        let context = HistoricalValuationTimeContext(timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let instant = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))

        let nextStart = context.endOfDay(for: instant).addingTimeInterval(0.000_001)
        #expect(nextStart.timeIntervalSince(context.startOfDay(for: instant)) == Double(expectedHours * 3_600))
    }

    @Test
    func localMidnightChangesOnlyTheFrozenDayKey() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let context = HistoricalValuationTimeContext(timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 8)))

        #expect(context.dayKey(for: midnight.addingTimeInterval(-0.001)) == "2026-08-07")
        #expect(context.dayKey(for: midnight) == "2026-08-08")
    }

    @Test
    func nonReadyScopeCannotPublishAnEmptyCompletePortfolio() {
        let result = HistoricalValuationResult(
            key: key(),
            diagnosticPartialTotal: 0,
            finality: .closed,
            quality: .unavailable,
            scopeReadiness: .restoring,
            expectedContributionCount: 0,
            resolvedContributionCount: 0,
            unresolved: [
                .init(opaqueAccountID: "scope", dimension: .scopeReadiness, reasonCode: "restore_in_progress")
            ],
            resolutions: [],
            generatedAt: .distantPast
        )

        #expect(result.state == .incomplete)
        #expect(result.total == nil)
        #expect(result.scopeReadiness == .restoring)
    }

    @Test
    func closedResolvedComputationIsProvisionalUntilPublished() {
        let result = HistoricalValuationResult(
            key: key(),
            diagnosticPartialTotal: 42,
            finality: .closed,
            quality: .exact,
            publication: .unpublished,
            expectedContributionCount: 1,
            resolvedContributionCount: 1,
            unresolved: [],
            resolutions: [],
            generatedAt: .distantPast
        )

        #expect(result.total == 42)
        #expect(result.state == .provisional)
        #expect(result.publication == .unpublished)
    }

    @Test
    func corruptedDecodedIncompleteResultWithPublicTotalThrows() throws {
        let unresolved = HistoricalValuationUnresolvedContribution(
            opaqueAccountID: "opaque", dimension: .fxRate, reasonCode: "missing"
        )
        let valid = HistoricalValuationResult(
            key: key(),
            diagnosticPartialTotal: 77,
            finality: .closed,
            quality: .unavailable,
            expectedContributionCount: 2,
            resolvedContributionCount: 1,
            unresolved: [unresolved],
            resolutions: [],
            generatedAt: .distantPast
        )
        let encoded = try JSONEncoder().encode(valid)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["total"] = 77
        let corrupted = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HistoricalValuationResult.self, from: corrupted)
        }
    }

    @Test
    func validatedFactoryRejectsImpossibleCoverage() {
        #expect(throws: HistoricalValuationResult.ValidationError.invalidResolvedCount) {
            _ = try HistoricalValuationResult.validated(
                key: key(),
                diagnosticPartialTotal: 0,
                finality: .closed,
                quality: .unavailable,
                publication: .unpublished,
                scopeReadiness: .ready,
                expectedContributionCount: 0,
                resolvedContributionCount: 1,
                unresolved: [],
                resolutions: [],
                generatedAt: .distantPast
            )
        }
    }

    @Test
    func resolutionSummaryPreservesCompleteTypedProvenanceThroughCodable() throws {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let summary = HistoricalValuationResolutionSummary(
            opaqueAccountID: "opaque-account-1",
            dimension: .fxRate,
            kind: "previousClose",
            sourceID: "cbr",
            recordID: "rate-record-1",
            evidenceDayKey: "2026-08-07",
            observedAt: observedAt,
            calendarPolicyID: "cbr-calendar-v1"
        )

        let decoded = try JSONDecoder().decode(
            HistoricalValuationResolutionSummary.self,
            from: JSONEncoder().encode(summary)
        )

        #expect(decoded == summary)
        #expect(decoded.opaqueAccountID == "opaque-account-1")
        #expect(decoded.sourceID == "cbr")
        #expect(decoded.recordID == "rate-record-1")
        #expect(decoded.evidenceDayKey == "2026-08-07")
        #expect(decoded.observedAt == observedAt)
        #expect(decoded.calendarPolicyID == "cbr-calendar-v1")
    }

    @Test
    func accountIdentityCannotBeMisdecodedAsProviderIdentity() throws {
        let summary = HistoricalValuationResolutionSummary(
            opaqueAccountID: "opaque-account-1",
            kind: "provenZero"
        )

        let decoded = try JSONDecoder().decode(
            HistoricalValuationResolutionSummary.self,
            from: JSONEncoder().encode(summary)
        )

        #expect(decoded.opaqueAccountID == "opaque-account-1")
        #expect(decoded.sourceID == nil)
        #expect(decoded.recordID == nil)
    }
}
