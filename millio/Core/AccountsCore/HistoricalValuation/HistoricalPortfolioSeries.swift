import Foundation

enum HistoricalPortfolioAccountScope: Hashable, Sendable {
    case portfolio
    case accountIDs(Set<UUID>)
}

enum HistoricalPortfolioSamplingPolicy: Hashable, Sendable {
    /// Period endpoints plus one close-of-day point for every intervening civil day.
    case daily
    /// Exact caller-owned points. Used by scrub/export consumers which must preserve point identity.
    case exact([Date])
}

struct HistoricalPortfolioSeriesQuery: Hashable, Sendable {
    let period: DateInterval
    let timeZoneID: String
    let displayCurrency: String
    let accountScope: HistoricalPortfolioAccountScope
    let samplingPolicy: HistoricalPortfolioSamplingPolicy
    let valuationPolicyVersion: Int
    /// Logical accounts whose legacy/core boundary has not yet been proven by the producer.
    /// They make coverage incomplete; they are never omitted or interpreted as zero.
    let unresolvedExternalAccountIDs: Set<String>

    init(
        period: DateInterval,
        timeZoneID: String,
        displayCurrency: String,
        accountScope: HistoricalPortfolioAccountScope = .portfolio,
        samplingPolicy: HistoricalPortfolioSamplingPolicy = .daily,
        valuationPolicyVersion: Int = 1,
        unresolvedExternalAccountIDs: Set<String> = []
    ) {
        self.period = period
        self.timeZoneID = timeZoneID
        self.displayCurrency = HistoricalValuationCurrencyCode.normalized(displayCurrency)
        self.accountScope = accountScope
        self.samplingPolicy = samplingPolicy
        self.valuationPolicyVersion = valuationPolicyVersion
        self.unresolvedExternalAccountIDs = unresolvedExternalAccountIDs
    }
}

struct HistoricalPortfolioPointID: Codable, Hashable, Sendable {
    let dayKey: String
    let timeZoneID: String
    let displayCurrency: String
    let valuationPolicyVersion: Int
    let inputRevision: HistoricalValuationInputRevision

    init(_ key: HistoricalValuationKey) {
        dayKey = key.dayKey
        timeZoneID = key.timeZoneID
        displayCurrency = key.displayCurrency
        valuationPolicyVersion = key.valuationPolicyVersion
        inputRevision = key.inputRevision
    }
}

struct HistoricalPortfolioAccountContribution: Sendable {
    let opaqueAccountID: String
    let value: Decimal?
    let state: HistoricalValuationState
    let quality: HistoricalValuationQuality
    let unresolved: [HistoricalValuationUnresolvedContribution]
    let resolutions: [HistoricalValuationResolutionSummary]

    init(
        opaqueAccountID: String,
        value: Decimal?,
        state: HistoricalValuationState,
        quality: HistoricalValuationQuality,
        unresolved: [HistoricalValuationUnresolvedContribution],
        resolutions: [HistoricalValuationResolutionSummary] = []
    ) {
        self.opaqueAccountID = opaqueAccountID
        self.value = value
        self.state = state
        self.quality = quality
        self.unresolved = unresolved
        self.resolutions = resolutions
    }
}

struct HistoricalPortfolioSeriesPoint: Sendable {
    let id: HistoricalPortfolioPointID
    let date: Date
    let valuation: HistoricalValuationResult
    let accountContributions: [HistoricalPortfolioAccountContribution]
}

struct HistoricalPortfolioSeriesResult: Sendable {
    let query: HistoricalPortfolioSeriesQuery
    let points: [HistoricalPortfolioSeriesPoint]
    let generatedAt: Date

    func point(nearestTo date: Date) -> HistoricalPortfolioSeriesPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

/// Reader flag intentionally has no route back to a bare numeric historical result. Compatibility
/// means the structured producer without persisted-close preference; rollback therefore preserves
/// completeness instead of reviving the old `nil rate => drop account` behaviour.
enum HistoricalPortfolioReaderMode: String, Sendable {
    case compatibility
    case shadow
    case structured
}

struct HistoricalPortfolioReaderConfiguration: Sendable {
    static let userDefaultsKey = "historical_portfolio_reader_mode_v1"
    static let structuredApprovalKey = "historical_portfolio_structured_approved_v1"

    let mode: HistoricalPortfolioReaderMode

    static func current(defaults: UserDefaults = .standard) -> Self {
        // Phase 5 emergency correctness cutover: production readers default to the local-only
        // structured path. It consumes persisted V7 closes and local FX/market evidence and never
        // revives the legacy `nil dependency => omit account` pixels. An explicitly persisted mode
        // remains authoritative so QA can keep shadow observation and release operations can roll
        // back to the structured compatibility reader without deleting financial evidence.
        guard let raw = defaults.string(forKey: userDefaultsKey) else {
            return Self(mode: .structured)
        }
        let requested = HistoricalPortfolioReaderMode(rawValue: raw) ?? .structured
        if requested == .structured, !defaults.bool(forKey: structuredApprovalKey) {
            return Self(mode: .shadow)
        }
        return Self(mode: requested)
    }

    /// Cutover is a transition, not a debug toggle. Persist approval only for a non-empty accepted
    /// observation window; otherwise a manually-written reader flag remains safely in shadow.
    @discardableResult
    static func approveStructuredCutover(
        gate: HistoricalPortfolioCutoverGate,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard gate.isApproved else { return false }
        defaults.set(true, forKey: structuredApprovalKey)
        defaults.set(HistoricalPortfolioReaderMode.structured.rawValue, forKey: userDefaultsKey)
        return true
    }
}

enum HistoricalPortfolioShadowDeltaBucket: String, Codable, Sendable {
    case exact
    case underOnePercent
    case underFivePercent
    case fivePercentOrMore
    case unavailable

    static func classify(structured: Decimal?, compatibility: Decimal?) -> Self {
        guard let structured, let compatibility else { return .unavailable }
        guard structured != compatibility else { return .exact }
        let denominator = max(abs(compatibility), 1)
        let ratio = abs(structured - compatibility) / denominator
        if ratio < Decimal(string: "0.01")! { return .underOnePercent }
        if ratio < Decimal(string: "0.05")! { return .underFivePercent }
        return .fivePercentOrMore
    }
}
