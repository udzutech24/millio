import Foundation
import SwiftData

enum HistoricalValuationRepositoryError: Error, Equatable, Sendable {
    case openResultCannotBePublished
    case unpublishedResultCannotBeStored
    case invalidSchemaVersion(Int)
    case manifestTooLarge(actualBytes: Int, maximumBytes: Int)
    case manifestCorrupted
    case recordCorrupted
    case scopeNotReady(String)
    case invalidKey
    case manifestSemanticallyInvalid
    case revisionReasonRequired
}

private struct HistoricalPortfolioValuationManifest: Codable, Sendable {
    let scopeReadiness: HistoricalScopeReadiness
    let readinessToken: HistoricalValuationReadinessToken
    let unresolved: [HistoricalValuationUnresolvedContribution]
    let resolutions: [HistoricalValuationResolutionSummary]
}

/// Additive V7 source of truth for an immutable local close.
///
/// SwiftData uniqueness is deliberately not claimed. `logicalID` is deterministic, while the
/// repository actor serializes local publication and resolves physical duplicates introduced by
/// restore/import. Source Account/Event/Snapshot rows are never related to or owned by this model.
@Model
final class HistoricalPortfolioValuation: Persistable {
    static let storageSchemaVersion = 7
    /// Hard cap sized for at least 250 accounts with both market-price and FX provenance. The
    /// measured-capacity regression in `HistoricalValuationRepositoryTests` must be updated before
    /// changing this value; evidence is rejected, never truncated.
    static let maximumManifestBytes = 256 * 1024

    var id: UUID = UUID()
    var logicalID: String = ""

    var schemaVersion: Int = storageSchemaVersion
    var scopeID: String = ""
    var dayKey: String = ""
    var timeZoneID: String = ""
    var displayCurrency: String = ""
    var valuationPolicyVersion: Int = 0
    var accountSetRevisionRaw: String = "0"
    var financialRevisionRaw: String = "0"
    var eventRevisionRaw: String = "0"
    var evidenceRevisionRaw: String = "0"

    var totalRaw: String?
    var diagnosticPartialTotalRaw: String = "0"
    var stateRaw: String = HistoricalValuationState.incomplete.rawValue
    var finalityRaw: String = HistoricalValuationFinality.closed.rawValue
    var qualityRaw: String = HistoricalValuationQuality.unavailable.rawValue
    var publicationRaw: String = HistoricalValuationPublication.published.rawValue
    var expectedContributionCount: Int = 0
    var resolvedContributionCount: Int = 0
    var manifestData: Data = Data()

    var generatedAt: Date = Date()
    var publishedAt: Date = Date()
    var revisionReasonCode: String?

    /// Duplicate/corrupt physical rows remain available for diagnosis but never participate in a
    /// logical read. Quarantine changes repository metadata only, not financial evidence.
    var isQuarantined: Bool = false
    var quarantineReasonCode: String?

    init(
        id: UUID = UUID(),
        logicalID: String,
        schemaVersion: Int,
        scopeID: String,
        dayKey: String,
        timeZoneID: String,
        displayCurrency: String,
        valuationPolicyVersion: Int,
        accountSetRevisionRaw: String,
        financialRevisionRaw: String,
        eventRevisionRaw: String,
        evidenceRevisionRaw: String,
        totalRaw: String?,
        diagnosticPartialTotalRaw: String,
        stateRaw: String,
        finalityRaw: String,
        qualityRaw: String,
        publicationRaw: String,
        expectedContributionCount: Int,
        resolvedContributionCount: Int,
        manifestData: Data,
        generatedAt: Date,
        publishedAt: Date,
        revisionReasonCode: String? = nil,
        isQuarantined: Bool = false,
        quarantineReasonCode: String? = nil
    ) {
        self.id = id
        self.logicalID = logicalID
        self.schemaVersion = schemaVersion
        self.scopeID = scopeID
        self.dayKey = dayKey
        self.timeZoneID = timeZoneID
        self.displayCurrency = displayCurrency
        self.valuationPolicyVersion = valuationPolicyVersion
        self.accountSetRevisionRaw = accountSetRevisionRaw
        self.financialRevisionRaw = financialRevisionRaw
        self.eventRevisionRaw = eventRevisionRaw
        self.evidenceRevisionRaw = evidenceRevisionRaw
        self.totalRaw = totalRaw
        self.diagnosticPartialTotalRaw = diagnosticPartialTotalRaw
        self.stateRaw = stateRaw
        self.finalityRaw = finalityRaw
        self.qualityRaw = qualityRaw
        self.publicationRaw = publicationRaw
        self.expectedContributionCount = expectedContributionCount
        self.resolvedContributionCount = resolvedContributionCount
        self.manifestData = manifestData
        self.generatedAt = generatedAt
        self.publishedAt = publishedAt
        self.revisionReasonCode = revisionReasonCode
        self.isQuarantined = isQuarantined
        self.quarantineReasonCode = quarantineReasonCode
    }

    static func make(
        from result: HistoricalValuationResult,
        publishedAt: Date,
        revisionReasonCode: String? = nil,
        id: UUID = UUID(),
        maximumManifestBytes: Int = maximumManifestBytes
    ) throws -> HistoricalPortfolioValuation {
        guard result.finality == .closed else {
            throw HistoricalValuationRepositoryError.openResultCannotBePublished
        }
        guard result.publication == .published else {
            throw HistoricalValuationRepositoryError.unpublishedResultCannotBeStored
        }
        guard result.key.schemaVersion == storageSchemaVersion else {
            throw HistoricalValuationRepositoryError.invalidSchemaVersion(result.key.schemaVersion)
        }
        if let revisionReasonCode,
           revisionReasonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw HistoricalValuationRepositoryError.revisionReasonRequired
        }
        guard publishedAt >= result.generatedAt else {
            throw HistoricalValuationRepositoryError.recordCorrupted
        }
        guard result.scopeReadiness == .ready else {
            throw HistoricalValuationRepositoryError.scopeNotReady(
                result.scopeReadiness.reasonCode ?? "scope_not_ready"
            )
        }
        guard !result.diagnosticPartialTotal.isNaN,
              result.total.map({ !$0.isNaN }) ?? true else {
            throw HistoricalValuationRepositoryError.recordCorrupted
        }
        guard isValid(key: result.key) else {
            throw HistoricalValuationRepositoryError.invalidKey
        }
        guard isValid(manifest: result) else {
            throw HistoricalValuationRepositoryError.manifestSemanticallyInvalid
        }

        let manifest = HistoricalPortfolioValuationManifest(
            scopeReadiness: result.scopeReadiness,
            readinessToken: result.readinessToken,
            unresolved: result.unresolved,
            resolutions: result.resolutions
        )
        let manifestData = try encodeManifest(manifest)
        guard manifestData.count <= maximumManifestBytes else {
            throw HistoricalValuationRepositoryError.manifestTooLarge(
                actualBytes: manifestData.count,
                maximumBytes: maximumManifestBytes
            )
        }

        let revision = result.key.inputRevision
        return HistoricalPortfolioValuation(
            id: id,
            logicalID: logicalID(for: result.key),
            schemaVersion: result.key.schemaVersion,
            scopeID: result.key.scopeID,
            dayKey: result.key.dayKey,
            timeZoneID: result.key.timeZoneID,
            displayCurrency: result.key.displayCurrency,
            valuationPolicyVersion: result.key.valuationPolicyVersion,
            accountSetRevisionRaw: String(revision.accountSet),
            financialRevisionRaw: String(revision.financial),
            eventRevisionRaw: String(revision.events),
            evidenceRevisionRaw: String(revision.evidence),
            totalRaw: result.total.map(canonicalDecimalString),
            diagnosticPartialTotalRaw: canonicalDecimalString(result.diagnosticPartialTotal),
            stateRaw: result.state.rawValue,
            finalityRaw: result.finality.rawValue,
            qualityRaw: result.quality.rawValue,
            publicationRaw: result.publication.rawValue,
            expectedContributionCount: result.expectedContributionCount,
            resolvedContributionCount: result.resolvedContributionCount,
            manifestData: manifestData,
            generatedAt: result.generatedAt,
            publishedAt: publishedAt,
            revisionReasonCode: revisionReasonCode
        )
    }

    func decodedResult(
        maximumManifestBytes: Int = HistoricalPortfolioValuation.maximumManifestBytes
    ) throws -> HistoricalValuationResult {
        guard manifestData.count <= maximumManifestBytes else {
            throw HistoricalValuationRepositoryError.manifestTooLarge(
                actualBytes: manifestData.count,
                maximumBytes: maximumManifestBytes
            )
        }
        guard schemaVersion == Self.storageSchemaVersion else {
            throw HistoricalValuationRepositoryError.invalidSchemaVersion(schemaVersion)
        }
        guard publishedAt >= generatedAt else {
            throw HistoricalValuationRepositoryError.recordCorrupted
        }
        guard let accountSet = UInt64(accountSetRevisionRaw),
              let financial = UInt64(financialRevisionRaw),
              let events = UInt64(eventRevisionRaw),
              let evidence = UInt64(evidenceRevisionRaw),
              let diagnosticPartialTotal = Decimal(
                string: diagnosticPartialTotalRaw,
                locale: Self.posixLocale
              ),
              let state = HistoricalValuationState(rawValue: stateRaw),
              let finality = HistoricalValuationFinality(rawValue: finalityRaw),
              let quality = HistoricalValuationQuality(rawValue: qualityRaw),
              let publication = HistoricalValuationPublication(rawValue: publicationRaw) else {
            throw HistoricalValuationRepositoryError.recordCorrupted
        }
        guard !diagnosticPartialTotal.isNaN,
              totalRaw.flatMap({ Decimal(string: $0, locale: Self.posixLocale) })
                .map({ !$0.isNaN }) ?? true else {
            throw HistoricalValuationRepositoryError.recordCorrupted
        }
        guard finality == .closed else {
            throw HistoricalValuationRepositoryError.openResultCannotBePublished
        }
        guard publication == .published else {
            throw HistoricalValuationRepositoryError.unpublishedResultCannotBeStored
        }
        if let revisionReasonCode,
           revisionReasonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw HistoricalValuationRepositoryError.recordCorrupted
        }

        let manifest = try Self.decodeManifest(manifestData)
        let key = HistoricalValuationKey(
            schemaVersion: schemaVersion,
            scopeID: scopeID,
            dayKey: dayKey,
            timeZoneID: timeZoneID,
            displayCurrency: displayCurrency,
            valuationPolicyVersion: valuationPolicyVersion,
            inputRevision: .init(
                accountSet: accountSet,
                financial: financial,
                events: events,
                evidence: evidence
            )
        )
        guard Self.isValid(key: key) else {
            throw HistoricalValuationRepositoryError.invalidKey
        }
        guard logicalID == Self.logicalID(for: key) else {
            throw HistoricalValuationRepositoryError.recordCorrupted
        }
        guard Self.isValid(
            manifest: manifest,
            timeContext: HistoricalValuationTimeContext(ianaTimeZoneID: timeZoneID),
            key: key,
            quality: quality,
            resolvedContributionCount: resolvedContributionCount,
            observationUpperBound: min(generatedAt, publishedAt)
        ) else {
            throw HistoricalValuationRepositoryError.manifestSemanticallyInvalid
        }

        let result: HistoricalValuationResult
        do {
            result = try HistoricalValuationResult.validated(
                key: key,
                diagnosticPartialTotal: diagnosticPartialTotal,
                finality: finality,
                quality: quality,
                publication: publication,
                scopeReadiness: manifest.scopeReadiness,
                readinessToken: manifest.readinessToken,
                expectedContributionCount: expectedContributionCount,
                resolvedContributionCount: resolvedContributionCount,
                unresolved: manifest.unresolved,
                resolutions: manifest.resolutions,
                generatedAt: generatedAt
            )
        } catch {
            throw HistoricalValuationRepositoryError.recordCorrupted
        }
        guard result.state == state,
              result.total.map(Self.canonicalDecimalString) == totalRaw else {
            throw HistoricalValuationRepositoryError.recordCorrupted
        }
        return result
    }

    static func logicalID(for key: HistoricalValuationKey) -> String {
        let revision = key.inputRevision
        return [
            String(key.schemaVersion), key.scopeID, key.dayKey, key.timeZoneID,
            key.displayCurrency, String(key.valuationPolicyVersion),
            String(revision.accountSet), String(revision.financial),
            String(revision.events), String(revision.evidence)
        ]
        .map { "\($0.utf8.count):\($0)" }
        .joined(separator: "|")
    }

    func export() throws -> Data {
        _ = try decodedResult()
        var dict: [String: Any] = [
            "type": "HistoricalPortfolioValuation",
            "id": id.uuidString,
            "logicalID": logicalID,
            "schemaVersion": schemaVersion,
            "scopeID": scopeID,
            "dayKey": dayKey,
            "timeZoneID": timeZoneID,
            "displayCurrency": displayCurrency,
            "valuationPolicyVersion": valuationPolicyVersion,
            "accountSetRevisionRaw": accountSetRevisionRaw,
            "financialRevisionRaw": financialRevisionRaw,
            "eventRevisionRaw": eventRevisionRaw,
            "evidenceRevisionRaw": evidenceRevisionRaw,
            "diagnosticPartialTotalRaw": diagnosticPartialTotalRaw,
            "stateRaw": stateRaw,
            "finalityRaw": finalityRaw,
            "qualityRaw": qualityRaw,
            "publicationRaw": publicationRaw,
            "expectedContributionCount": expectedContributionCount,
            "resolvedContributionCount": resolvedContributionCount,
            "manifestBase64": manifestData.base64EncodedString(),
            "generatedAt": generatedAt.timeIntervalSince1970,
            "publishedAt": publishedAt.timeIntervalSince1970
        ]
        if let totalRaw { dict["totalRaw"] = totalRaw }
        if let revisionReasonCode { dict["revisionReasonCode"] = revisionReasonCode }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        // Imported through HistoricalPortfolioValuationImporter so duplicates can be retained and
        // resolved deterministically by the repository actor.
    }

    private static func encodeManifest(_ manifest: HistoricalPortfolioValuationManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(manifest)
    }

    private static func decodeManifest(_ data: Data) throws -> HistoricalPortfolioValuationManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(HistoricalPortfolioValuationManifest.self, from: data)
        } catch {
            throw HistoricalValuationRepositoryError.manifestCorrupted
        }
    }

    private static func isValid(key: HistoricalValuationKey) -> Bool {
        let scopeID = key.scopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        let currency = HistoricalValuationCurrencyCode.normalized(key.displayCurrency)
        guard !scopeID.isEmpty,
              scopeID == key.scopeID,
              currency == key.displayCurrency,
              HistoricalValuationCurrencyCode.isSupported(currency),
              key.valuationPolicyVersion > 0,
              let timeContext = HistoricalValuationTimeContext(
                ianaTimeZoneID: key.timeZoneID
              ),
              timeContext.isValid(dayKey: key.dayKey) else {
            return false
        }
        return true
    }

    private static func isValid(manifest result: HistoricalValuationResult) -> Bool {
        guard let timeContext = HistoricalValuationTimeContext(
            ianaTimeZoneID: result.key.timeZoneID
        ) else { return false }
        return isValid(
            manifest: HistoricalPortfolioValuationManifest(
                scopeReadiness: result.scopeReadiness,
                readinessToken: result.readinessToken,
                unresolved: result.unresolved,
                resolutions: result.resolutions
            ),
            timeContext: timeContext,
            key: result.key,
            quality: result.quality,
            resolvedContributionCount: result.resolvedContributionCount,
            observationUpperBound: result.generatedAt
        )
    }

    private static func isValid(
        manifest: HistoricalPortfolioValuationManifest,
        timeContext: HistoricalValuationTimeContext?,
        key: HistoricalValuationKey? = nil,
        quality: HistoricalValuationQuality? = nil,
        resolvedContributionCount: Int? = nil,
        observationUpperBound: Date? = nil
    ) -> Bool {
        guard manifest.scopeReadiness == .ready, let timeContext else { return false }
        guard manifest.unresolved.allSatisfy({
            !$0.opaqueAccountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return false }

        let unresolvedKeys = Set(manifest.unresolved.map {
            "\($0.opaqueAccountID)|\($0.dimension.rawValue)"
        })
        var positiveResolutionAccounts: Set<String> = []
        var unavailableResolutionAccounts: Set<String> = []
        var containsExact = false
        var containsFallback = false
        var containsUnavailable = false

        guard manifest.resolutions.allSatisfy({ summary in
            let optionals = [
                summary.opaqueAccountID,
                summary.sourceID,
                summary.recordID,
                summary.calendarPolicyID
            ]
            guard optionals.compactMap({ $0 }).allSatisfy({
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) else { return false }
            if let evidenceDayKey = summary.evidenceDayKey,
               !timeContext.isValid(dayKey: evidenceDayKey) {
                return false
            }
            if let observedAt = summary.observedAt,
               let observationUpperBound,
               observedAt > observationUpperBound {
                return false
            }
            if summary.kind == "provenZero" {
                guard let accountID = summary.opaqueAccountID,
                      summary.dimension == nil,
                      summary.sourceID == nil,
                      summary.recordID == nil,
                      summary.evidenceDayKey == nil,
                      summary.observedAt == nil,
                      summary.calendarPolicyID == nil else { return false }
                _ = accountID
                positiveResolutionAccounts.insert(accountID)
                containsExact = true
                return true
            }

            guard let kind = HistoricalValuationResolutionKind(rawValue: summary.kind) else {
                return false
            }
            switch kind {
            case .nativeParity:
                guard let accountID = summary.opaqueAccountID,
                      summary.dimension == .fxRate,
                      summary.sourceID == nil,
                      summary.recordID == nil,
                      summary.evidenceDayKey == nil,
                      summary.observedAt == nil,
                      summary.calendarPolicyID == nil else { return false }
                _ = accountID
                positiveResolutionAccounts.insert(accountID)
                containsExact = true
            case .exact, .previousClose, .frozenClose:
                guard let accountID = summary.opaqueAccountID,
                      summary.dimension == .fxRate || summary.dimension == .marketPrice,
                      summary.sourceID != nil,
                      summary.recordID != nil,
                      let evidenceDayKey = summary.evidenceDayKey,
                      summary.observedAt != nil,
                      summary.calendarPolicyID != nil,
                      let key else { return false }
                if kind == .previousClose {
                    guard evidenceDayKey < key.dayKey else { return false }
                    containsFallback = true
                } else {
                    guard evidenceDayKey == key.dayKey else { return false }
                    if kind == .frozenClose { containsFallback = true }
                    if kind == .exact { containsExact = true }
                }
                _ = accountID
                positiveResolutionAccounts.insert(accountID)
            case .unavailable:
                guard let accountID = summary.opaqueAccountID,
                      let dimension = summary.dimension,
                      dimension == .nativeBalance
                        || dimension == .fxRate
                        || dimension == .marketPrice,
                      summary.sourceID == nil,
                      summary.recordID == nil,
                      summary.evidenceDayKey == nil,
                      summary.observedAt == nil,
                      summary.calendarPolicyID == nil,
                      unresolvedKeys.contains("\(accountID)|\(dimension.rawValue)") else {
                    return false
                }
                containsUnavailable = true
                unavailableResolutionAccounts.insert(accountID)
            case .currentEstimate:
                // A closed publication may retain the observed record only as frozenClose.
                return false
            }
            return true
        }) else { return false }

        if let resolvedContributionCount {
            let unresolvedAccounts = Set(manifest.unresolved.map(\.opaqueAccountID))
            let fullyResolvedAccounts = positiveResolutionAccounts
                .subtracting(unavailableResolutionAccounts)
                .subtracting(unresolvedAccounts)
            guard fullyResolvedAccounts.count == resolvedContributionCount else {
                return false
            }
        }
        if let quality {
            if !manifest.unresolved.isEmpty {
                return quality == .unavailable
            }
            switch quality {
            case .estimated:
                return false
            case .exact:
                let emptyPortfolio = resolvedContributionCount == 0 && manifest.resolutions.isEmpty
                return (containsExact || emptyPortfolio) && !containsFallback && !containsUnavailable
            case .fallback:
                return containsFallback && !containsExact && !containsUnavailable
            case .unavailable:
                return false
            case .mixed:
                return containsExact && containsFallback && !containsUnavailable
            }
        }
        return true
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    private static func canonicalDecimalString(_ value: Decimal) -> String {
        var value = value
        return NSDecimalString(&value, posixLocale)
    }
}
