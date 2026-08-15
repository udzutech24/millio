import Foundation

enum HistoricalValuationState: String, Codable, Sendable {
    case provisional
    case complete
    case incomplete
}

enum HistoricalValuationFinality: String, Codable, Sendable {
    case open
    case closed
}

enum HistoricalValuationPublication: String, Codable, Sendable {
    case unpublished
    case published
}

enum HistoricalValuationQuality: String, Codable, Sendable {
    case exact
    case fallback
    case estimated
    case mixed
    case unavailable
}

enum HistoricalValuationMissingDimension: String, Codable, Sendable {
    case accountData
    case events
    case nativeBalance
    case marketPrice
    case fxRate
    case migrationBoundary
    case scopeReadiness
    case cache
}

struct HistoricalValuationUnresolvedContribution: Codable, Hashable, Sendable {
    let opaqueAccountID: String
    let dimension: HistoricalValuationMissingDimension
    let reasonCode: String
}

struct HistoricalValuationResolutionSummary: Codable, Hashable, Sendable {
    let opaqueAccountID: String?
    let dimension: HistoricalValuationMissingDimension?
    let kind: String
    let sourceID: String?
    let recordID: String?
    let evidenceDayKey: String?
    let observedAt: Date?
    let calendarPolicyID: String?

    init(
        opaqueAccountID: String? = nil,
        dimension: HistoricalValuationMissingDimension? = nil,
        kind: String,
        sourceID: String? = nil,
        recordID: String? = nil,
        evidenceDayKey: String? = nil,
        observedAt: Date? = nil,
        calendarPolicyID: String? = nil
    ) {
        self.opaqueAccountID = opaqueAccountID
        self.dimension = dimension
        self.kind = kind
        self.sourceID = sourceID
        self.recordID = recordID
        self.evidenceDayKey = evidenceDayKey
        self.observedAt = observedAt
        self.calendarPolicyID = calendarPolicyID
    }
}

struct HistoricalValuationInputRevision: Codable, Hashable, Sendable {
    let accountSet: UInt64
    let financial: UInt64
    let events: UInt64
    let evidence: UInt64
}

struct HistoricalValuationKey: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let scopeID: String
    let dayKey: String
    let timeZoneID: String
    let displayCurrency: String
    let valuationPolicyVersion: Int
    let inputRevision: HistoricalValuationInputRevision
}

/// Structured historical result. The only initializer derives the public total from coverage,
/// so an incomplete result cannot accidentally expose a diagnostic subtotal as portfolio truth.
struct HistoricalValuationResult: Codable, Sendable {
    let key: HistoricalValuationKey
    let total: Decimal?
    let diagnosticPartialTotal: Decimal
    let state: HistoricalValuationState
    let finality: HistoricalValuationFinality
    let quality: HistoricalValuationQuality
    let publication: HistoricalValuationPublication
    let scopeReadiness: HistoricalScopeReadiness
    let readinessToken: HistoricalValuationReadinessToken
    let expectedContributionCount: Int
    let resolvedContributionCount: Int
    let unresolved: [HistoricalValuationUnresolvedContribution]
    let resolutions: [HistoricalValuationResolutionSummary]
    let generatedAt: Date

    init(
        key: HistoricalValuationKey,
        diagnosticPartialTotal: Decimal,
        finality: HistoricalValuationFinality,
        quality: HistoricalValuationQuality,
        publication: HistoricalValuationPublication = .published,
        scopeReadiness: HistoricalScopeReadiness = .ready,
        readinessToken: HistoricalValuationReadinessToken? = nil,
        expectedContributionCount: Int,
        resolvedContributionCount: Int,
        unresolved: [HistoricalValuationUnresolvedContribution],
        resolutions: [HistoricalValuationResolutionSummary],
        generatedAt: Date
    ) {
        precondition(expectedContributionCount >= 0)
        precondition((0...expectedContributionCount).contains(resolvedContributionCount))
        precondition(unresolved.count >= expectedContributionCount - resolvedContributionCount)

        self.key = key
        self.diagnosticPartialTotal = diagnosticPartialTotal
        self.finality = finality
        self.quality = quality
        self.publication = publication
        self.scopeReadiness = scopeReadiness
        self.readinessToken = readinessToken
            ?? HistoricalValuationReadinessCoordinator.shared.snapshot(
                scopeID: key.scopeID
            ).token
        self.expectedContributionCount = expectedContributionCount
        self.resolvedContributionCount = resolvedContributionCount
        self.unresolved = unresolved
        self.resolutions = resolutions
        self.generatedAt = generatedAt

        if resolvedContributionCount == expectedContributionCount,
           unresolved.isEmpty,
           scopeReadiness == .ready {
            total = diagnosticPartialTotal
            state = finality == .closed && publication == .published ? .complete : .provisional
        } else {
            total = nil
            state = .incomplete
        }
    }

    enum ValidationError: Error, Equatable {
        case negativeExpectedCount
        case invalidResolvedCount
        case unresolvedCoverageMismatch
    }

    static func validated(
        key: HistoricalValuationKey,
        diagnosticPartialTotal: Decimal,
        finality: HistoricalValuationFinality,
        quality: HistoricalValuationQuality,
        publication: HistoricalValuationPublication,
        scopeReadiness: HistoricalScopeReadiness,
        readinessToken: HistoricalValuationReadinessToken? = nil,
        expectedContributionCount: Int,
        resolvedContributionCount: Int,
        unresolved: [HistoricalValuationUnresolvedContribution],
        resolutions: [HistoricalValuationResolutionSummary],
        generatedAt: Date
    ) throws -> Self {
        guard expectedContributionCount >= 0 else { throw ValidationError.negativeExpectedCount }
        guard (0...expectedContributionCount).contains(resolvedContributionCount) else {
            throw ValidationError.invalidResolvedCount
        }
        guard unresolved.count >= expectedContributionCount - resolvedContributionCount else {
            throw ValidationError.unresolvedCoverageMismatch
        }
        return .init(
            key: key,
            diagnosticPartialTotal: diagnosticPartialTotal,
            finality: finality,
            quality: quality,
            publication: publication,
            scopeReadiness: scopeReadiness,
            readinessToken: readinessToken,
            expectedContributionCount: expectedContributionCount,
            resolvedContributionCount: resolvedContributionCount,
            unresolved: unresolved,
            resolutions: resolutions,
            generatedAt: generatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case total
        case diagnosticPartialTotal
        case state
        case finality
        case quality
        case publication
        case scopeReadiness
        case readinessToken
        case expectedContributionCount
        case resolvedContributionCount
        case unresolved
        case resolutions
        case generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let encodedTotal = try container.decodeIfPresent(Decimal.self, forKey: .total)
        let encodedState = try container.decode(HistoricalValuationState.self, forKey: .state)
        let decoded = try Self.validated(
            key: container.decode(HistoricalValuationKey.self, forKey: .key),
            diagnosticPartialTotal: container.decode(Decimal.self, forKey: .diagnosticPartialTotal),
            finality: container.decode(HistoricalValuationFinality.self, forKey: .finality),
            quality: container.decode(HistoricalValuationQuality.self, forKey: .quality),
            publication: container.decodeIfPresent(HistoricalValuationPublication.self, forKey: .publication) ?? .published,
            scopeReadiness: container.decodeIfPresent(HistoricalScopeReadiness.self, forKey: .scopeReadiness) ?? .ready,
            readinessToken: container.decodeIfPresent(
                HistoricalValuationReadinessToken.self,
                forKey: .readinessToken
            ),
            expectedContributionCount: container.decode(Int.self, forKey: .expectedContributionCount),
            resolvedContributionCount: container.decode(Int.self, forKey: .resolvedContributionCount),
            unresolved: container.decode([HistoricalValuationUnresolvedContribution].self, forKey: .unresolved),
            resolutions: container.decode([HistoricalValuationResolutionSummary].self, forKey: .resolutions),
            generatedAt: container.decode(Date.self, forKey: .generatedAt)
        )
        guard encodedTotal == decoded.total, encodedState == decoded.state else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Historical valuation total/state contradict derived coverage"
            ))
        }
        self = decoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encodeIfPresent(total, forKey: .total)
        try container.encode(diagnosticPartialTotal, forKey: .diagnosticPartialTotal)
        try container.encode(state, forKey: .state)
        try container.encode(finality, forKey: .finality)
        try container.encode(quality, forKey: .quality)
        try container.encode(publication, forKey: .publication)
        try container.encode(scopeReadiness, forKey: .scopeReadiness)
        try container.encode(readinessToken, forKey: .readinessToken)
        try container.encode(expectedContributionCount, forKey: .expectedContributionCount)
        try container.encode(resolvedContributionCount, forKey: .resolvedContributionCount)
        try container.encode(unresolved, forKey: .unresolved)
        try container.encode(resolutions, forKey: .resolutions)
        try container.encode(generatedAt, forKey: .generatedAt)
    }
}

protocol HistoricalValuationClock: Sendable {
    var now: Date { get }
}

struct SystemHistoricalValuationClock: HistoricalValuationClock {
    var now: Date { Date() }
}

struct HistoricalValuationTimeContext: Sendable {
    let timeZone: TimeZone
    private let calendar: Calendar

    init(timeZone: TimeZone) {
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    init?(ianaTimeZoneID: String) {
        guard TimeZone.knownTimeZoneIdentifiers.contains(ianaTimeZoneID),
              let timeZone = TimeZone(identifier: ianaTimeZoneID) else {
            return nil
        }
        self.init(timeZone: timeZone)
    }

    var timeZoneID: String { timeZone.identifier }

    func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func endOfDay(for date: Date) -> Date {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay(for: date)) else {
            return date
        }
        return nextDay.addingTimeInterval(-0.000_001)
    }

    func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    func isOpenDay(_ date: Date, now: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    func isValid(dayKey: String) -> Bool {
        let parts = dayKey.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return false
        }
        return self.dayKey(for: date) == dayKey
    }
}

enum HistoricalScopeReadiness: Codable, Hashable, Sendable {
    case ready
    case restoring
    case reconciling
    case backfilling
    case revisionMigrating
    case failed(reasonCode: String)

    var reasonCode: String? {
        switch self {
        case .ready: nil
        case .restoring: "restore_in_progress"
        case .reconciling: "reconciliation_in_progress"
        case .backfilling: "backfill_in_progress"
        case .revisionMigrating: "revision_migration_in_progress"
        case .failed(let reasonCode): reasonCode
        }
    }
}
