import Foundation
import SwiftData

/// Оркестратор reconciliation guest→user (Track B, B2c). Связывает чистое ядро (детектор/lineage/
/// multiset) с SwiftData-worker'ами и safety-механизмами. Идемпотентен на каждом переходе в user-скоуп
/// (митигация B1b №7): дёшево при отсутствии расхождения (детектор-скрининг первым).
/// Класс без @MainActor (создаётся в nonisolated `App.init` как @State), но `reconcile` — @MainActor:
/// координирует UI-оверлей и @ModelActor-worker'ы с главного потока, тяжёлую работу отдаёт off-main.
final class ScopeReconciliationService {

    /// - onWillMerge: вызывается ТОЛЬКО когда действительно начинается merge (после детектора+lineage) —
    ///   для показа progress-overlay. При отсутствии расхождения не вызывается (overlay не мигает).
    /// - usedFallbackOpen: guest или user открыт через no-plan fallback («partially readable») —
    ///   done НЕ фиксируем, чтобы повторить при чистом открытии (митигация B1b №6).
    @MainActor
    func reconcile(
        userContainer: ModelContainer,
        userScope: DataScope,
        guestContainer: ModelContainer,
        userStoreURL: URL?,
        guestStoreURL: URL?,
        usedFallbackOpen: Bool,
        onWillMerge: @MainActor () -> Void
    ) async -> ScopeMergeOutcome {
        let key = userScope.storeConfigurationName
        if ScopeMergeMarker.isDone(userScopeKey: key) { return .alreadyDone }

        do {
            let reader = ScopeGuestReader(modelContainer: guestContainer)
            let worker = ScopeMergeWorker(modelContainer: userContainer)
            let guestInput = try await reader.read()
            let userSnapshot = try await worker.snapshot()

            // 1. Детектор-скрининг (дёшево — только counts/watermarks).
            let signals = Self.buildSignals(guest: guestInput.snapshot, user: userSnapshot)
            guard DivergenceDetector.hasDivergence(signals) else {
                ScopeMergeMarker.markDone(userScopeKey: key, report: ScopeMergeReport())
                return .noDivergence
            }

            // 2. Lineage-check (митигация B1b №1) — защита от чужого guest.
            let decision = ScopeLineageChecker.decide(
                guestFingerprints: guestInput.snapshot.identityFingerprints,
                userFingerprints: userSnapshot.identityFingerprints,
                guestIsEmpty: guestInput.snapshot.isEmpty,
                userIsEmpty: userSnapshot.isEmpty
            )
            switch decision {
            case .noGuestData, .userEmpty:
                return .skipped
            case .foreignGuest:
                ScopeMergeMarker.markNeedsConfirmation(userScopeKey: key)
                AppLogger.log(.warning, category: "Reconciliation",
                              "Foreign guest for \(key) — merge отложен до подтверждения")
                return .deferredForeignGuest
            case .proceed:
                break
            }

            // 3. Merge. С этого момента — progress-overlay + блокировка бэкапа.
            onWillMerge()
            ScopeMergeLock.shared.begin()
            defer { ScopeMergeLock.shared.end() }

            // 3a. Автобэкап обоих сторов ДО записи (митигация B1b №7). Off-main — copy может быть тяжёлым.
            let backupURLs = [userStoreURL, guestStoreURL].compactMap { $0 }
            if !backupURLs.isEmpty {
                await Task.detached { ScopeStoreBackup.backup(storeURLs: backupURLs) }.value
            }

            // 3b. Применяем merge (single-save, sanity-abort внутри worker).
            let targets = MultisetReconciler.targets(
                guestCounts: guestInput.snapshot.transactionCountsByFingerprint,
                userCounts: userSnapshot.transactionCountsByFingerprint
            )
            let result = try await worker.apply(input: guestInput, transactionTargets: targets)

            // 3c. Снапшоты не мержим — пересобираем из событий (спека §2).
            let rebuilder = AccountSnapshotRebuilder(modelContainer: userContainer)
            _ = try? await rebuilder.rebuildAllAccounts()

            let report = ScopeMergeReport(
                accountsAdded: result.accountsAdded,
                transactionsAdded: result.transactionsAdded,
                partiallyReadable: usedFallbackOpen
            )
            if usedFallbackOpen {
                ScopeMergeMarker.storeReport(userScopeKey: key, report: report) // без done (митигация B1b №6)
            } else {
                ScopeMergeMarker.markDone(userScopeKey: key, report: report)
            }
            AppLogger.log(.info, category: "Reconciliation",
                          "Merge для \(key): +\(report.accountsAdded) счетов, +\(report.transactionsAdded) операций, partial=\(usedFallbackOpen)")
            return .merged(report)
        } catch let error as ScopeMergeError {
            // Sanity-abort: контекст не сохранён, на диске ничего не изменилось; done НЕ ставим.
            AppLogger.log(.error, category: "Reconciliation", "Sanity-abort merge \(key): \(error)")
            return .abortedSanity
        } catch {
            // Прочие ошибки — не фиксируем done, повторим при следующем переходе (идемпотентно).
            AppLogger.log(.error, category: "Reconciliation",
                          "Merge \(key) не удался (повтор при следующем логине): \(error.localizedDescription)")
            return .skipped
        }
    }

    private static func buildSignals(guest: ScopeSideSnapshot, user: ScopeSideSnapshot) -> [ModelDivergenceSignal] {
        let models = Set(guest.modelCounts.keys).union(user.modelCounts.keys)
        return models.map { model in
            ModelDivergenceSignal(
                modelName: model,
                guestCount: guest.modelCounts[model] ?? 0,
                userCount: user.modelCounts[model] ?? 0,
                guestMaxUpdatedAt: guest.modelWatermarks[model],
                userMaxUpdatedAt: user.modelWatermarks[model]
            )
        }
    }
}
