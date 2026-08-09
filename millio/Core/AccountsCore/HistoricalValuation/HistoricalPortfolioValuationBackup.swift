import Foundation
import SwiftData

/// Full encrypted snapshot backup importer. Reconciliation excludes this type: guest closes are
/// scoped evidence and must be rebuilt under the destination `DataScope.storeConfigurationName`.
///
/// Quarantine is deliberately local repository metadata. A portable backup contains only
/// validated logical winners and imports each as an active candidate; the destination repository
/// deterministically deduplicates against rows already present in that store.
struct HistoricalPortfolioValuationImporter: ModelImporter {
    static func importType() -> String { "HistoricalPortfolioValuation" }

    static func `import`(from data: [String: Any], context: ModelContext) throws {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let logicalID = data["logicalID"] as? String,
              let schemaVersion = data["schemaVersion"] as? Int,
              let scopeID = data["scopeID"] as? String,
              let dayKey = data["dayKey"] as? String,
              let timeZoneID = data["timeZoneID"] as? String,
              let displayCurrency = data["displayCurrency"] as? String,
              let valuationPolicyVersion = data["valuationPolicyVersion"] as? Int,
              let accountSetRevisionRaw = data["accountSetRevisionRaw"] as? String,
              let financialRevisionRaw = data["financialRevisionRaw"] as? String,
              let eventRevisionRaw = data["eventRevisionRaw"] as? String,
              let evidenceRevisionRaw = data["evidenceRevisionRaw"] as? String,
              let diagnosticPartialTotalRaw = data["diagnosticPartialTotalRaw"] as? String,
              let stateRaw = data["stateRaw"] as? String,
              let finalityRaw = data["finalityRaw"] as? String,
              let qualityRaw = data["qualityRaw"] as? String,
              let publicationRaw = data["publicationRaw"] as? String,
              let expectedContributionCount = data["expectedContributionCount"] as? Int,
              let resolvedContributionCount = data["resolvedContributionCount"] as? Int,
              let manifestBase64 = data["manifestBase64"] as? String,
              let manifestData = Data(base64Encoded: manifestBase64),
              let generatedAtInterval = data["generatedAt"] as? TimeInterval,
              let publishedAtInterval = data["publishedAt"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }

        let idDescriptor = FetchDescriptor<HistoricalPortfolioValuation>(
            predicate: #Predicate { $0.id == id }
        )
        if try context.fetch(idDescriptor).first != nil { return }

        let row = HistoricalPortfolioValuation(
            id: id,
            logicalID: logicalID,
            schemaVersion: schemaVersion,
            scopeID: scopeID,
            dayKey: dayKey,
            timeZoneID: timeZoneID,
            displayCurrency: displayCurrency,
            valuationPolicyVersion: valuationPolicyVersion,
            accountSetRevisionRaw: accountSetRevisionRaw,
            financialRevisionRaw: financialRevisionRaw,
            eventRevisionRaw: eventRevisionRaw,
            evidenceRevisionRaw: evidenceRevisionRaw,
            totalRaw: data["totalRaw"] as? String,
            diagnosticPartialTotalRaw: diagnosticPartialTotalRaw,
            stateRaw: stateRaw,
            finalityRaw: finalityRaw,
            qualityRaw: qualityRaw,
            publicationRaw: publicationRaw,
            expectedContributionCount: expectedContributionCount,
            resolvedContributionCount: resolvedContributionCount,
            manifestData: manifestData,
            generatedAt: Date(timeIntervalSince1970: generatedAtInterval),
            publishedAt: Date(timeIntervalSince1970: publishedAtInterval),
            revisionReasonCode: data["revisionReasonCode"] as? String,
            isQuarantined: false,
            quarantineReasonCode: nil
        )
        do {
            _ = try row.decodedResult()
        } catch {
            throw AppError.backupCorrupted
        }
        context.insert(row)
    }
}

enum HistoricalPortfolioValuationBackupExporter {
    /// Returns one validated immutable winner per logical key. Corrupt physical rows and local
    /// quarantine markers are diagnostic state, not portable financial evidence.
    static func export(from context: ModelContext) throws -> [[String: Any]] {
        let rows = try context.fetch(FetchDescriptor<HistoricalPortfolioValuation>())
        let grouped = Dictionary(grouping: rows, by: \.logicalID)

        return try grouped.keys.sorted().map { logicalID in
            var firstFailure: Error?
            let valid = grouped[logicalID, default: []].compactMap { row -> HistoricalPortfolioValuation? in
                do {
                    _ = try row.decodedResult()
                    return row
                } catch {
                    if firstFailure == nil { firstFailure = error }
                    return nil
                }
            }
            let winner = valid.min { lhs, rhs in
                if lhs.publishedAt != rhs.publishedAt {
                    return lhs.publishedAt < rhs.publishedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            guard let winner else {
                throw firstFailure ?? HistoricalValuationRepositoryError.recordCorrupted
            }

            var payload = try BackupJSON.decodeExportedDict(
                winner.export(),
                typeName: "HistoricalPortfolioValuation"
            )
            payload["_type"] = "HistoricalPortfolioValuation"
            return payload
        }
    }
}
