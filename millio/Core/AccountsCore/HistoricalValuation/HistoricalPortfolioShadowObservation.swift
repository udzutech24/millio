import Foundation

enum HistoricalPortfolioShadowDeltaReason: String, Codable, Sendable {
    case exact
    case structuredIncomplete
    case accountSetMismatch
    case compatibilityUnavailable
    case expectedResolverCorrection
    case unexplainedNumericDelta
}

struct HistoricalPortfolioShadowObservation: Codable, Equatable, Sendable {
    let deltaBucket: HistoricalPortfolioShadowDeltaBucket
    let reason: HistoricalPortfolioShadowDeltaReason
    let structuredState: HistoricalValuationState
    let structuredExpectedCount: Int
    let structuredResolvedCount: Int
    let compatibilityContributionCount: Int?
    let compatibilityPublishedValue: Bool

    var isSilentDrop: Bool {
        reason == .structuredIncomplete && compatibilityPublishedValue
    }

    var isClassified: Bool {
        reason != .unexplainedNumericDelta
    }

    static func classify(
        structured: HistoricalValuationResult,
        compatibilityTotal: Decimal?,
        compatibilityContributionCount: Int?,
        hasExpectedResolverCorrection: Bool
    ) -> Self {
        let bucket = HistoricalPortfolioShadowDeltaBucket.classify(
            structured: structured.total,
            compatibility: compatibilityTotal
        )
        let reason: HistoricalPortfolioShadowDeltaReason
        if structured.state == .incomplete {
            reason = .structuredIncomplete
        } else if let compatibilityContributionCount,
                  compatibilityContributionCount != structured.expectedContributionCount {
            reason = .accountSetMismatch
        } else if compatibilityTotal == nil {
            reason = .compatibilityUnavailable
        } else if bucket == .exact {
            reason = .exact
        } else if hasExpectedResolverCorrection {
            reason = .expectedResolverCorrection
        } else {
            reason = .unexplainedNumericDelta
        }
        return .init(
            deltaBucket: bucket,
            reason: reason,
            structuredState: structured.state,
            structuredExpectedCount: structured.expectedContributionCount,
            structuredResolvedCount: structured.resolvedContributionCount,
            compatibilityContributionCount: compatibilityContributionCount,
            compatibilityPublishedValue: compatibilityTotal != nil
        )
    }
}

struct HistoricalPortfolioCutoverGate: Equatable, Sendable {
    let observationCount: Int
    let silentDropCount: Int
    let unexplainedDeltaCount: Int
    let accountSetMismatchCount: Int

    var isApproved: Bool {
        observationCount > 0
            && silentDropCount == 0
            && unexplainedDeltaCount == 0
            && accountSetMismatchCount == 0
    }

    static func evaluate(_ observations: [HistoricalPortfolioShadowObservation]) -> Self {
        .init(
            observationCount: observations.count,
            silentDropCount: observations.filter(\.isSilentDrop).count,
            unexplainedDeltaCount: observations.filter { !$0.isClassified }.count,
            accountSetMismatchCount: observations.filter { $0.reason == .accountSetMismatch }.count
        )
    }
}

/// Durable evidence required before an explicit structured-reader approval. A raw observation
/// count is weak: one hot loop can manufacture it. The window therefore spans civil days and at
/// least two device transitions, including an offline transition.
struct HistoricalPortfolioShadowWindowPolicy: Equatable, Sendable {
    let minimumObservations: Int
    let minimumDistinctDays: Int
    let minimumDeviceTransitions: Int
    let requiresOfflineTransition: Bool

    static let production = Self(
        minimumObservations: 30,
        minimumDistinctDays: 7,
        minimumDeviceTransitions: 2,
        requiresOfflineTransition: true
    )
}

struct HistoricalPortfolioShadowEvidence: Codable, Equatable, Sendable {
    let observation: HistoricalPortfolioShadowObservation
    let dayKey: String
    /// Opaque QA transition identifier. It must not contain a device/user identifier.
    let transitionID: String?
    let wasOffline: Bool?

    init(
        observation: HistoricalPortfolioShadowObservation,
        dayKey: String,
        transitionID: String? = nil,
        wasOffline: Bool? = nil
    ) {
        self.observation = observation
        self.dayKey = dayKey
        self.transitionID = transitionID
        self.wasOffline = wasOffline
    }
}

struct HistoricalPortfolioShadowWindow: Equatable, Sendable {
    let gate: HistoricalPortfolioCutoverGate
    let distinctDayCount: Int
    let deviceTransitionCount: Int
    let hasOfflineTransition: Bool

    func isApproved(by policy: HistoricalPortfolioShadowWindowPolicy) -> Bool {
        gate.isApproved
            && gate.observationCount >= policy.minimumObservations
            && distinctDayCount >= policy.minimumDistinctDays
            && deviceTransitionCount >= policy.minimumDeviceTransitions
            && (!policy.requiresOfflineTransition || hasOfflineTransition)
    }
}

final class HistoricalPortfolioShadowEvidenceStore: @unchecked Sendable {
    private static let storageKey = "historical_portfolio_shadow_evidence_v1"
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func append(_ evidence: HistoricalPortfolioShadowEvidence) {
        lock.withLock {
            var values = decoded()
            values.append(evidence)
            if values.count > 500 { values.removeFirst(values.count - 500) }
            if let data = try? JSONEncoder().encode(values) {
                defaults.set(data, forKey: Self.storageKey)
            }
        }
    }

    func window() -> HistoricalPortfolioShadowWindow {
        lock.withLock {
            let values = decoded()
            return .init(
                gate: .evaluate(values.map(\.observation)),
                distinctDayCount: Set(values.map(\.dayKey)).count,
                deviceTransitionCount: Set(values.compactMap(\.transitionID)).count,
                hasOfflineTransition: values.contains { $0.wasOffline == true }
            )
        }
    }

    @discardableResult
    func approveStructuredCutover(
        policy: HistoricalPortfolioShadowWindowPolicy = .production,
        readerDefaults: UserDefaults = .standard
    ) -> Bool {
        let current = window()
        guard current.isApproved(by: policy) else { return false }
        return HistoricalPortfolioReaderConfiguration.approveStructuredCutover(
            gate: current.gate,
            defaults: readerDefaults
        )
    }

    private func decoded() -> [HistoricalPortfolioShadowEvidence] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let values = try? JSONDecoder().decode([HistoricalPortfolioShadowEvidence].self, from: data)
        else { return [] }
        return values
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
