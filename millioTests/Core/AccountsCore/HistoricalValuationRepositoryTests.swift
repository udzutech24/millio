import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Historical valuation repository", .serialized)
struct HistoricalValuationRepositoryTests {
    @Test("Closed result survives repository and store relaunch") @MainActor
    func relaunchRoundTrip() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("valuation_repository_\(UUID().uuidString).store")
        defer { Self.cleanupStore(at: storeURL) }
        let result = Self.result(total: 100)

        do {
            let container = try Self.diskContainer(storeURL: storeURL)
            let repository = HistoricalValuationRepository(modelContainer: container)
            let published = try await repository.publish(
                result,
                publishedAt: Date(timeIntervalSince1970: 1_800_000_001)
            )
            #expect(published.total == 100)
        }

        let reopened = try Self.diskContainer(storeURL: storeURL)
        let repository = HistoricalValuationRepository(modelContainer: reopened)
        let restored = try #require(try await repository.valuation(for: result.key))
        #expect(restored.total == 100)
        #expect(restored.key == result.key)
        #expect(restored.resolutions == result.resolutions)
    }

    @Test("Parallel local publish converges to one immutable physical row") @MainActor
    func parallelPublishIsIdempotent() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("valuation_parallel_\(UUID().uuidString).store")
        defer { Self.cleanupStore(at: storeURL) }
        let original = Self.result(total: 100)
        let providerRecovery = Self.result(total: 110, sourceID: "provider-recovered")

        do {
            let container = try Self.diskContainer(storeURL: storeURL)
            let repositories = [
                HistoricalValuationRepository(modelContainer: container),
                HistoricalValuationRepository(modelContainer: container),
                HistoricalValuationRepository(modelContainer: container)
            ]
            try await withThrowingTaskGroup(of: Decimal?.self) { group in
                for index in 0..<20 {
                    group.addTask {
                        let repository = repositories[index % repositories.count]
                        return (try await repository.publish(
                            original,
                            publishedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index))
                        )).total
                    }
                }
                for try await total in group { #expect(total == 100) }
            }

            // Same logical revision is immutable even if a provider later returns a new number.
            #expect(try await repositories[1].publish(
                providerRecovery,
                publishedAt: Date(timeIntervalSince1970: 1_800_000_100)
            ).total == 100)
            #expect(try await repositories[1].physicalRecordCount(for: original.key) == 1)
        }

        let reopened = try Self.diskContainer(storeURL: storeURL)
        let reopenedRepository = HistoricalValuationRepository(modelContainer: reopened)
        #expect(try await reopenedRepository.physicalRecordCount(for: original.key) == 1)
        #expect(try await reopenedRepository.valuation(for: original.key)?.total == 100)
    }

    @Test("A repair revision creates a new immutable record and retains the old close") @MainActor
    func repairRevisionRetainsOldClose() async throws {
        let container = try Self.memoryContainer()
        let repository = HistoricalValuationRepository(modelContainer: container)
        let original = Self.result(total: 100)
        let repaired = Self.result(
            total: 110,
            sourceID: "provider-repair",
            inputRevision: .init(accountSet: 1, financial: 5, events: 3, evidence: 8)
        )

        _ = try await repository.publish(
            original,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        _ = try await repository.publish(
            repaired,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_100),
            revisionReasonCode: "evidence_repair"
        )

        #expect(try await repository.valuation(for: original.key)?.total == 100)
        #expect(try await repository.valuation(for: repaired.key)?.total == 110)
        #expect(try await repository.physicalRecordCount(for: original.key) == 1)
        #expect(try await repository.physicalRecordCount(for: repaired.key) == 1)
    }

    @Test("A changed input revision requires an explicit repair reason") @MainActor
    func revisionReasonIsMandatory() async throws {
        let container = try Self.memoryContainer()
        let repository = HistoricalValuationRepository(modelContainer: container)
        let original = Self.result(total: 100)
        let changedRevision = Self.result(
            total: 110,
            inputRevision: .init(accountSet: 1, financial: 2, events: 3, evidence: 99)
        )
        _ = try await repository.publish(original, publishedAt: Self.publicationDate)

        await #expect(throws: HistoricalValuationRepositoryError.revisionReasonRequired) {
            _ = try await repository.publish(changedRevision, publishedAt: Self.publicationDate)
        }
        #expect(try await repository.valuation(for: changedRevision.key) == nil)
    }

    @Test("Duplicate imported rows have one stable winner and retain quarantined evidence") @MainActor
    func duplicateImportWinner() async throws {
        let container = try Self.memoryContainer()
        let original = Self.result(total: 100)
        let recovered = Self.result(total: 110, sourceID: "provider-recovered")
        let earlier = try HistoricalPortfolioValuation.make(
            from: original,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let later = try HistoricalPortfolioValuation.make(
            from: recovered,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_100),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        )

        let earlierDict = try Self.exportedDict(earlier)
        let laterDict = try Self.exportedDict(later)
        try HistoricalPortfolioValuationImporter.import(from: laterDict, context: container.mainContext)
        try HistoricalPortfolioValuationImporter.import(from: earlierDict, context: container.mainContext)
        try container.mainContext.save()

        let repository = HistoricalValuationRepository(modelContainer: container)
        #expect(try await repository.valuation(for: original.key)?.total == 100)
        #expect(try await repository.physicalRecordCount(for: original.key) == 2)
        #expect(try await repository.quarantinedRecordCount(for: original.key) == 1)

        let secondRead = try await repository.valuation(for: original.key)
        #expect(secondRead?.total == 100)
    }

    @Test("A corrupt winner promotes the next earliest valid duplicate") @MainActor
    func corruptWinnerPromotesValidDuplicate() async throws {
        let container = try Self.memoryContainer()
        let original = Self.result(total: 100)
        let fallback = Self.result(total: 110, sourceID: "fallback-record")
        let first = try HistoricalPortfolioValuation.make(
            from: original,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let second = try HistoricalPortfolioValuation.make(
            from: fallback,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()
        let repository = HistoricalValuationRepository(modelContainer: container)

        #expect(try await repository.valuation(for: original.key)?.total == 100)
        first.manifestData = Data("corrupt".utf8)
        try container.mainContext.save()

        #expect(try await repository.valuation(for: original.key)?.total == 110)
        #expect(try await repository.quarantinedRecordCount(for: original.key) == 1)
    }

    @Test("Corrupted and oversized manifests fail with typed errors") @MainActor
    func corruptedAndOversizedManifest() async throws {
        let oversized = Self.result(
            total: 100,
            sourceID: String(repeating: "evidence", count: 200)
        )
        // Match the typed case without coupling the assertion to JSONEncoder's exact byte count.
        do {
            _ = try HistoricalPortfolioValuation.make(
                from: oversized,
                publishedAt: Self.publicationDate,
                maximumManifestBytes: 64
            )
            Issue.record("Oversized manifest unexpectedly succeeded")
        } catch let error as HistoricalValuationRepositoryError {
            guard case .manifestTooLarge(let actual, let maximum) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(actual > maximum)
            #expect(maximum == 64)
        }

        let container = try Self.memoryContainer()
        let valid = Self.result(total: 100)
        let corrupted = try HistoricalPortfolioValuation.make(
            from: valid,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        corrupted.manifestData = Data("not-json".utf8)
        container.mainContext.insert(corrupted)
        try container.mainContext.save()

        let repository = HistoricalValuationRepository(modelContainer: container)
        await #expect(throws: HistoricalValuationRepositoryError.manifestCorrupted) {
            _ = try await repository.valuation(for: valid.key)
        }
        #expect(try await repository.quarantinedRecordCount(for: valid.key) == 1)
    }

    @Test("Interrupted restore cannot publish an authoritative close") @MainActor
    func interruptedRestoreReadiness() async throws {
        let container = try Self.memoryContainer()
        let repository = HistoricalValuationRepository(modelContainer: container)
        let incomplete = Self.incompleteRestoreResult()
        await #expect(throws: HistoricalValuationRepositoryError.scopeNotReady(
            "restore_interrupted"
        )) {
            _ = try await repository.publish(incomplete, publishedAt: Self.publicationDate)
        }
        #expect(try await repository.valuation(for: incomplete.key) == nil)
    }

    @Test("Encrypted full backup round-trip preserves close and repository identity") @MainActor
    func encryptedBackupRoundTrip() async throws {
        let registryState = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(registryState) }
        AccountsCoreFeatureRegistration.register()

        let source = try Self.memoryContainer()
        let sourceService = AccountsCoreService(modelContext: source.mainContext)
        let account = try sourceService.createAccount(
            name: "Backup account",
            kind: .cash,
            currency: "RUB",
            openingBalance: 75,
            date: Date(timeIntervalSince1970: 1_799_000_000)
        )
        _ = try sourceService.recordEvent(
            account: account,
            type: .income,
            amount: 25,
            date: Date(timeIntervalSince1970: 1_799_100_000)
        )
        let sourceEvents = try source.mainContext.fetch(FetchDescriptor<AccountEvent>())
        let sourceRevision = HistoricalValuationRevisionBuilder.build(
            accounts: [account],
            eventsByAccountID: [account.id: sourceEvents]
        )
        let result = Self.result(total: 100, inputRevision: sourceRevision)
        let sourceRepository = HistoricalValuationRepository(modelContainer: source)
        _ = try await sourceRepository.publish(result, publishedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let backup = try DataRepository.exportAllData(from: source.mainContext)
        let encrypted = try PassphraseBackupEncryption.encrypt(
            backup,
            passphrase: "phase-3v-test",
            iterations: PassphraseBackupEncryption.minIterations
        )
        let decrypted = try PassphraseBackupEncryption.decrypt(
            encrypted.encrypted,
            passphrase: "phase-3v-test",
            kdf: encrypted.kdf
        )

        let destination = try Self.memoryContainer()
        try DataRepository.importAllData(decrypted, into: destination.mainContext)
        let destinationRepository = HistoricalValuationRepository(modelContainer: destination)
        let restored = try #require(try await destinationRepository.valuation(for: result.key))
        #expect(restored.total == result.total)
        #expect(restored.key == result.key)
        #expect(try await destinationRepository.physicalRecordCount(for: result.key) == 1)
        let restoredAccount = try #require(
            destination.mainContext.fetch(FetchDescriptor<Account>()).first
        )
        let restoredEvents = try destination.mainContext.fetch(FetchDescriptor<AccountEvent>())
        let restoredRevision = HistoricalValuationRevisionBuilder.build(
            accounts: [restoredAccount],
            eventsByAccountID: [restoredAccount.id: restoredEvents]
        )
        #expect(restoredRevision == sourceRevision)
    }

    @Test("Backup exports only a validated logical winner and resets local quarantine") @MainActor
    func backupSkipsCorruptionAndLocalQuarantine() async throws {
        let registryState = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(registryState) }
        AccountsCoreFeatureRegistration.register()
        let container = try Self.memoryContainer()
        let original = Self.result(total: 100)
        let duplicate = Self.result(total: 110, sourceID: "duplicate")
        let winner = try HistoricalPortfolioValuation.make(
            from: original,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        winner.isQuarantined = true
        winner.quarantineReasonCode = "source_store_only"
        let later = try HistoricalPortfolioValuation.make(
            from: duplicate,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let corrupt = try HistoricalPortfolioValuation.make(
            from: original,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_200),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!
        )
        corrupt.manifestData = Data("corrupt".utf8)
        container.mainContext.insert(winner)
        container.mainContext.insert(later)
        container.mainContext.insert(corrupt)
        try container.mainContext.save()

        let backup = try DataRepository.exportAllData(from: container.mainContext)
        let backupJSON = try #require(
            JSONSerialization.jsonObject(with: backup) as? [String: Any]
        )
        let payloads = try #require(backupJSON["models"] as? [[String: Any]])
            .filter { $0["_type"] as? String == "HistoricalPortfolioValuation" }
        #expect(payloads.count == 1)
        #expect(payloads[0]["isQuarantined"] == nil)
        #expect(payloads[0]["quarantineReasonCode"] == nil)

        let destination = try Self.memoryContainer()
        try HistoricalPortfolioValuationImporter.import(
            from: payloads[0],
            context: destination.mainContext
        )
        try destination.mainContext.save()
        let repository = HistoricalValuationRepository(modelContainer: destination)
        #expect(try await repository.valuation(for: original.key)?.total == 100)
        #expect(try await repository.quarantinedRecordCount(for: original.key) == 0)
    }

    @Test("Corrupted-only logical key fails backup explicitly") @MainActor
    func corruptedOnlyKeyFailsBackup() throws {
        let registryState = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(registryState) }
        AccountsCoreFeatureRegistration.register()
        let container = try Self.memoryContainer()
        let result = Self.result(total: 100)
        let corrupt = try HistoricalPortfolioValuation.make(
            from: result,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        corrupt.manifestData = Data("corrupt".utf8)
        container.mainContext.insert(corrupt)
        try container.mainContext.save()

        #expect(throws: HistoricalValuationRepositoryError.manifestCorrupted) {
            _ = try DataRepository.exportAllData(from: container.mainContext)
        }
    }

    @Test("Storage rejects invalid key and semantic manifest corruption") @MainActor
    func semanticValidation() throws {
        let valid = Self.result(total: 100)
        let invalidKey = HistoricalValuationResult(
            key: .init(
                schemaVersion: HistoricalPortfolioValuation.storageSchemaVersion,
                scopeID: " ",
                dayKey: "2026-02-30",
                timeZoneID: "GMT+3",
                displayCurrency: "rub",
                valuationPolicyVersion: 0,
                inputRevision: valid.key.inputRevision
            ),
            diagnosticPartialTotal: 100,
            finality: .closed,
            quality: .exact,
            expectedContributionCount: 1,
            resolvedContributionCount: 1,
            unresolved: [],
            resolutions: [.init(kind: "nativeParity")],
            generatedAt: Date()
        )
        #expect(throws: HistoricalValuationRepositoryError.invalidKey) {
            _ = try HistoricalPortfolioValuation.make(from: invalidKey, publishedAt: Self.publicationDate)
        }

        let invalidManifest = HistoricalValuationResult(
            key: valid.key,
            diagnosticPartialTotal: 100,
            finality: .closed,
            quality: .exact,
            expectedContributionCount: 1,
            resolvedContributionCount: 1,
            unresolved: [],
            resolutions: [.init(kind: "providerInventedFallback")],
            generatedAt: Date()
        )
        #expect(throws: HistoricalValuationRepositoryError.manifestSemanticallyInvalid) {
            _ = try HistoricalPortfolioValuation.make(
                from: invalidManifest,
                publishedAt: Self.publicationDate
            )
        }

        let impossibleDimension = HistoricalValuationResult(
            key: valid.key,
            diagnosticPartialTotal: 100,
            finality: .closed,
            quality: .exact,
            expectedContributionCount: 1,
            resolvedContributionCount: 1,
            unresolved: [],
            resolutions: [.init(
                opaqueAccountID: "opaque-account",
                dimension: .events,
                kind: "exact",
                sourceID: "provider",
                recordID: "record",
                evidenceDayKey: valid.key.dayKey,
                observedAt: Date(),
                calendarPolicyID: "calendar"
            )],
            generatedAt: Date()
        )
        #expect(throws: HistoricalValuationRepositoryError.manifestSemanticallyInvalid) {
            _ = try HistoricalPortfolioValuation.make(
                from: impossibleDimension,
                publishedAt: Self.publicationDate
            )
        }

        let notANumber = HistoricalValuationResult(
            key: valid.key,
            diagnosticPartialTotal: .nan,
            finality: .closed,
            quality: .exact,
            expectedContributionCount: 0,
            resolvedContributionCount: 0,
            unresolved: [],
            resolutions: [],
            generatedAt: Date()
        )
        #expect(throws: HistoricalValuationRepositoryError.recordCorrupted) {
            _ = try HistoricalPortfolioValuation.make(
                from: notANumber,
                publishedAt: Self.publicationDate
            )
        }

        let missingProvenance = HistoricalValuationResult(
            key: valid.key,
            diagnosticPartialTotal: 100,
            finality: .closed,
            quality: .exact,
            expectedContributionCount: 1,
            resolvedContributionCount: 1,
            unresolved: [],
            resolutions: [.init(
                opaqueAccountID: "opaque-account",
                dimension: .fxRate,
                kind: "exact"
            )],
            generatedAt: Date()
        )
        #expect(throws: HistoricalValuationRepositoryError.manifestSemanticallyInvalid) {
            _ = try HistoricalPortfolioValuation.make(
                from: missingProvenance,
                publishedAt: Self.publicationDate
            )
        }

        let closedCurrentEstimate = HistoricalValuationResult(
            key: valid.key,
            diagnosticPartialTotal: 100,
            finality: .closed,
            quality: .estimated,
            expectedContributionCount: 1,
            resolvedContributionCount: 1,
            unresolved: [],
            resolutions: [.init(
                opaqueAccountID: "opaque-account",
                dimension: .fxRate,
                kind: "currentEstimate",
                sourceID: "provider",
                recordID: "record",
                evidenceDayKey: valid.key.dayKey,
                observedAt: Date(),
                calendarPolicyID: "calendar"
            )],
            generatedAt: Date()
        )
        #expect(throws: HistoricalValuationRepositoryError.manifestSemanticallyInvalid) {
            _ = try HistoricalPortfolioValuation.make(
                from: closedCurrentEstimate,
                publishedAt: Self.publicationDate
            )
        }

        let inconsistentQuality = Self.result(total: 100, sourceID: "provider")
        let fallbackEvidenceWithExactQuality = HistoricalValuationResult(
            key: inconsistentQuality.key,
            diagnosticPartialTotal: 100,
            finality: .closed,
            quality: .exact,
            expectedContributionCount: 1,
            resolvedContributionCount: 1,
            unresolved: [],
            resolutions: [.init(
                opaqueAccountID: "opaque-account",
                dimension: .fxRate,
                kind: "previousClose",
                sourceID: "provider",
                recordID: "record",
                evidenceDayKey: "2026-08-06",
                observedAt: Date(),
                calendarPolicyID: "calendar"
            )],
            generatedAt: Date()
        )
        #expect(throws: HistoricalValuationRepositoryError.manifestSemanticallyInvalid) {
            _ = try HistoricalPortfolioValuation.make(
                from: fallbackEvidenceWithExactQuality,
                publishedAt: Self.publicationDate
            )
        }

        let duplicateLogicalContribution = HistoricalValuationResult(
            key: valid.key,
            diagnosticPartialTotal: 200,
            finality: .closed,
            quality: .exact,
            expectedContributionCount: 2,
            resolvedContributionCount: 2,
            unresolved: [],
            resolutions: [
                valid.resolutions[0],
                .init(
                    opaqueAccountID: "opaque-account",
                    dimension: .marketPrice,
                    kind: "exact",
                    sourceID: "provider",
                    recordID: "market-record",
                    evidenceDayKey: valid.key.dayKey,
                    observedAt: Date(),
                    calendarPolicyID: "calendar"
                )
            ],
            generatedAt: Date()
        )
        #expect(throws: HistoricalValuationRepositoryError.manifestSemanticallyInvalid) {
            _ = try HistoricalPortfolioValuation.make(
                from: duplicateLogicalContribution,
                publishedAt: Self.publicationDate
            )
        }

        let nativeBalanceUnavailable = HistoricalValuationResult(
            key: valid.key,
            diagnosticPartialTotal: 0,
            finality: .closed,
            quality: .unavailable,
            expectedContributionCount: 1,
            resolvedContributionCount: 0,
            unresolved: [.init(
                opaqueAccountID: "opaque-account",
                dimension: .nativeBalance,
                reasonCode: "invalid_native_value"
            )],
            resolutions: [.init(
                opaqueAccountID: "opaque-account",
                dimension: .nativeBalance,
                kind: "unavailable"
            )],
            generatedAt: Date()
        )
        _ = try HistoricalPortfolioValuation.make(
            from: nativeBalanceUnavailable,
            publishedAt: Self.publicationDate
        )
    }

    @Test("Storage rejects publication and evidence that travel backwards in time")
    func temporalProvenanceValidation() throws {
        let valid = Self.result(total: 100)
        #expect(throws: HistoricalValuationRepositoryError.recordCorrupted) {
            _ = try HistoricalPortfolioValuation.make(
                from: valid,
                publishedAt: valid.generatedAt.addingTimeInterval(-1)
            )
        }

        let futureEvidence = HistoricalValuationResult(
            key: valid.key,
            diagnosticPartialTotal: 100,
            finality: .closed,
            quality: .exact,
            expectedContributionCount: 1,
            resolvedContributionCount: 1,
            unresolved: [],
            resolutions: [.init(
                opaqueAccountID: "opaque-account",
                dimension: .fxRate,
                kind: "exact",
                sourceID: "provider",
                recordID: "future-record",
                evidenceDayKey: valid.key.dayKey,
                observedAt: valid.generatedAt.addingTimeInterval(1),
                calendarPolicyID: "calendar"
            )],
            generatedAt: valid.generatedAt
        )
        #expect(throws: HistoricalValuationRepositoryError.manifestSemanticallyInvalid) {
            _ = try HistoricalPortfolioValuation.make(
                from: futureEvidence,
                publishedAt: Self.publicationDate
            )
        }

        let stored = try HistoricalPortfolioValuation.make(
            from: valid,
            publishedAt: Self.publicationDate
        )
        stored.publishedAt = stored.generatedAt.addingTimeInterval(-1)
        #expect(throws: HistoricalValuationRepositoryError.recordCorrupted) {
            _ = try stored.decodedResult()
        }
    }

    @Test("Readiness generation changes invalidate a previously computed close") @MainActor
    func readinessGenerationRace() async throws {
        let coordinator = HistoricalValuationReadinessCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }
        let container = try Self.memoryContainer()
        let repository = HistoricalValuationRepository(modelContainer: container)
        let computed = Self.result(total: 100)

        coordinator.begin(scopeID: computed.key.scopeID, operation: .revisionMigration)
        coordinator.complete(scopeID: computed.key.scopeID, operation: .revisionMigration)

        await #expect(throws: HistoricalValuationRepositoryError.scopeNotReady(
            "scope_changed_during_valuation"
        )) {
            _ = try await repository.publish(computed, publishedAt: Self.publicationDate)
        }
        #expect(try await repository.valuation(for: computed.key) == nil)
    }

    @Test("Persisted close is hidden when live scope readiness changes") @MainActor
    func persistedCloseRequiresLiveReadinessToken() async throws {
        let coordinator = HistoricalValuationReadinessCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }
        let repository = HistoricalValuationRepository(modelContainer: try Self.memoryContainer())
        let result = Self.result(total: 100)
        _ = try await repository.publish(result, publishedAt: Self.publicationDate)

        coordinator.begin(scopeID: result.key.scopeID, operation: .backfill)

        await #expect(throws: HistoricalValuationRepositoryError.scopeNotReady(
            "backfill_in_progress"
        )) {
            _ = try await repository.valuation(for: result.key)
        }
        await #expect(throws: HistoricalValuationRepositoryError.scopeNotReady(
            "backfill_in_progress"
        )) {
            _ = try await repository.publishedValuations(scopeID: result.key.scopeID)
        }
    }

    @Test("Invalid cleanup is scoped, preserves valid closes and is idempotent") @MainActor
    func invalidCleanupIsSafeAndIdempotent() async throws {
        let container = try Self.memoryContainer()
        let validResult = Self.result(total: 100)
        let valid = try HistoricalPortfolioValuation.make(
            from: validResult,
            publishedAt: Self.publicationDate
        )
        let invalid = try HistoricalPortfolioValuation.make(
            from: validResult,
            publishedAt: Self.publicationDate.addingTimeInterval(1),
            id: UUID()
        )
        invalid.manifestData = Data("invalid-manifest".utf8)
        let invalidOtherScope = try HistoricalPortfolioValuation.make(
            from: validResult,
            publishedAt: Self.publicationDate.addingTimeInterval(2),
            id: UUID()
        )
        invalidOtherScope.scopeID = "scope-user-2"
        invalidOtherScope.manifestData = Data("invalid-other-scope".utf8)
        container.mainContext.insert(valid)
        container.mainContext.insert(invalid)
        container.mainContext.insert(invalidOtherScope)
        try container.mainContext.save()
        let repository = HistoricalValuationRepository(modelContainer: container)

        let first = try await repository.deleteInvalidRecords(scopeID: validResult.key.scopeID)
        let second = try await repository.deleteInvalidRecords(scopeID: validResult.key.scopeID)

        #expect(first == .init(inspectedCount: 2, deletedCount: 1))
        #expect(second == .init(inspectedCount: 1, deletedCount: 0))
        let remaining = try container.mainContext.fetch(FetchDescriptor<HistoricalPortfolioValuation>())
        #expect(remaining.count == 2)
        #expect(remaining.contains(where: { $0.id == valid.id }))
        #expect(remaining.contains(where: { $0.id == invalidOtherScope.id }))
        #expect(!remaining.contains(where: { $0.id == invalid.id }))
    }

    @Test("Manifest cap fits measured portfolio and rejects oversized evidence")
    func measuredManifestCapacity() throws {
        func result(accountCount: Int) -> HistoricalValuationResult {
            let summaries = (0..<accountCount).flatMap { index in
                [HistoricalValuationResolutionSummary(
                    opaqueAccountID: "account-\(index)",
                    dimension: .marketPrice,
                    kind: "exact",
                    sourceID: "provider",
                    recordID: "market-record-\(index)",
                    evidenceDayKey: "2026-08-07",
                    observedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    calendarPolicyID: "exchange-calendar-v1"
                ), HistoricalValuationResolutionSummary(
                    opaqueAccountID: "account-\(index)",
                    dimension: .fxRate,
                    kind: "exact",
                    sourceID: "provider",
                    recordID: "fx-record-\(index)",
                    evidenceDayKey: "2026-08-07",
                    observedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    calendarPolicyID: "fiat-calendar-v1"
                )]
            }
            return HistoricalValuationResult(
                key: Self.result(total: 1).key,
                diagnosticPartialTotal: Decimal(accountCount),
                finality: .closed,
                quality: .exact,
                expectedContributionCount: accountCount,
                resolvedContributionCount: accountCount,
                unresolved: [],
                resolutions: summaries,
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        }

        _ = try HistoricalPortfolioValuation.make(
            from: result(accountCount: 250),
            publishedAt: Self.publicationDate
        )
        #expect(throws: HistoricalValuationRepositoryError.self) {
            _ = try HistoricalPortfolioValuation.make(
                from: result(accountCount: 2_000),
                publishedAt: Self.publicationDate
            )
        }
    }

    private static func result(
        total: Decimal,
        sourceID: String = "provider-original",
        inputRevision: HistoricalValuationInputRevision = .init(
            accountSet: 1,
            financial: 2,
            events: 3,
            evidence: 4
        )
    ) -> HistoricalValuationResult {
        let key = HistoricalValuationKey(
            schemaVersion: HistoricalPortfolioValuation.storageSchemaVersion,
            scopeID: "scope-user-1",
            dayKey: "2026-08-07",
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB",
            valuationPolicyVersion: 1,
            inputRevision: inputRevision
        )
        return HistoricalValuationResult(
            key: key,
            diagnosticPartialTotal: total,
            finality: .closed,
            quality: .exact,
            expectedContributionCount: 1,
            resolvedContributionCount: 1,
            unresolved: [],
            resolutions: [.init(
                opaqueAccountID: "opaque-account",
                dimension: .fxRate,
                kind: "exact",
                sourceID: sourceID,
                recordID: "record-1",
                evidenceDayKey: "2026-08-07",
                observedAt: Date(timeIntervalSince1970: 1_799_999_900),
                calendarPolicyID: "calendar-1"
            )],
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static let publicationDate = Date(timeIntervalSince1970: 1_800_000_500)

    private static func incompleteRestoreResult() -> HistoricalValuationResult {
        HistoricalValuationResult(
            key: HistoricalValuationKey(
                schemaVersion: HistoricalPortfolioValuation.storageSchemaVersion,
                scopeID: "scope-user-1",
                dayKey: "2026-08-07",
                timeZoneID: "Europe/Istanbul",
                displayCurrency: "RUB",
                valuationPolicyVersion: 1,
                inputRevision: .init(accountSet: 0, financial: 0, events: 0, evidence: 0)
            ),
            diagnosticPartialTotal: 0,
            finality: .closed,
            quality: .unavailable,
            scopeReadiness: .failed(reasonCode: "restore_interrupted"),
            expectedContributionCount: 0,
            resolvedContributionCount: 0,
            unresolved: [.init(
                opaqueAccountID: "scope",
                dimension: .scopeReadiness,
                reasonCode: "restore_interrupted"
            )],
            resolutions: [],
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private static func memoryContainer() throws -> ModelContainer {
        try AppMigrationPlan.makeInMemoryContainer()
    }

    private static func diskContainer(storeURL: URL) throws -> ModelContainer {
        try AppMigrationPlan.makeContainer(configuration: ModelConfiguration(
            "valuation_repository_\(UUID().uuidString)",
            url: storeURL,
            cloudKitDatabase: .none
        ))
    }

    private static func exportedDict(_ model: HistoricalPortfolioValuation) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: model.export()) as? [String: Any]
        )
    }

    private static func cleanupStore(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    }
}
