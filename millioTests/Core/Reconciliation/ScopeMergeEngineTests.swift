import Foundation
import Testing
@testable import millio

/// B2a: чистое ядро reconciliation (детектор / lineage / multiset) — без SwiftData.
struct ScopeMergeEngineTests {

    // MARK: - DivergenceDetector

    @Test func detector_noDivergence_whenCountsAndWatermarksEqual() {
        let signals = [
            ModelDivergenceSignal(modelName: "Tx", guestCount: 10, userCount: 10,
                                  guestMaxUpdatedAt: Date(timeIntervalSince1970: 100),
                                  userMaxUpdatedAt: Date(timeIntervalSince1970: 100))
        ]
        #expect(DivergenceDetector.hasDivergence(signals) == false)
    }

    @Test func detector_divergence_whenGuestHasMoreRows() {
        let signals = [
            ModelDivergenceSignal(modelName: "Tx", guestCount: 12, userCount: 10,
                                  guestMaxUpdatedAt: nil, userMaxUpdatedAt: nil)
        ]
        #expect(DivergenceDetector.hasDivergence(signals) == true)
    }

    @Test func detector_divergence_whenGuestWatermarkNewer() {
        let signals = [
            ModelDivergenceSignal(modelName: "Card", guestCount: 5, userCount: 5,
                                  guestMaxUpdatedAt: Date(timeIntervalSince1970: 200),
                                  userMaxUpdatedAt: Date(timeIntervalSince1970: 100))
        ]
        #expect(DivergenceDetector.hasDivergence(signals) == true)
    }

    @Test func detector_divergence_whenUserHasNoWatermarkButGuestDoes() {
        let signals = [
            ModelDivergenceSignal(modelName: "Card", guestCount: 1, userCount: 1,
                                  guestMaxUpdatedAt: Date(timeIntervalSince1970: 50),
                                  userMaxUpdatedAt: nil)
        ]
        #expect(DivergenceDetector.hasDivergence(signals) == true)
    }

    @Test func detector_noDivergence_whenUserAheadOfGuest() {
        // user новее/больше — расхождения «в сторону guest» нет, merge не нужен.
        let signals = [
            ModelDivergenceSignal(modelName: "Tx", guestCount: 8, userCount: 10,
                                  guestMaxUpdatedAt: Date(timeIntervalSince1970: 100),
                                  userMaxUpdatedAt: Date(timeIntervalSince1970: 300))
        ]
        #expect(DivergenceDetector.hasDivergence(signals) == false)
    }

    // MARK: - ScopeLineageChecker

    @Test func lineage_proceed_whenSharedIdentity() {
        let d = ScopeLineageChecker.decide(
            guestFingerprints: ["acc|1", "acc|2", "tx|new"],
            userFingerprints: ["acc|1", "acc|2"],
            guestIsEmpty: false, userIsEmpty: false
        )
        #expect(d == .proceed)
    }

    @Test func lineage_foreignGuest_whenDisjoint() {
        let d = ScopeLineageChecker.decide(
            guestFingerprints: ["acc|A", "acc|B"],
            userFingerprints: ["acc|X", "acc|Y"],
            guestIsEmpty: false, userIsEmpty: false
        )
        #expect(d == .foreignGuest)
    }

    @Test func lineage_noGuestData_whenGuestEmpty() {
        let d = ScopeLineageChecker.decide(
            guestFingerprints: [], userFingerprints: ["acc|1"],
            guestIsEmpty: true, userIsEmpty: false
        )
        #expect(d == .noGuestData)
    }

    @Test func lineage_userEmpty_blocksAutoMerge() {
        // Защита от чужого guest: в пустой user-стор молча не заливаем.
        let d = ScopeLineageChecker.decide(
            guestFingerprints: ["acc|1"], userFingerprints: [],
            guestIsEmpty: false, userIsEmpty: true
        )
        #expect(d == .userEmpty)
    }

    @Test func lineage_foreignGuest_whenNoStructuralIdentityOnEitherSide() {
        // Оба непусты, но identity-fingerprints нет (только keyless-модели) — родословную не подтвердить.
        let d = ScopeLineageChecker.decide(
            guestFingerprints: [], userFingerprints: [],
            guestIsEmpty: false, userIsEmpty: false
        )
        #expect(d == .foreignGuest)
    }

    // MARK: - MultisetReconciler.targets

    @Test func targets_takeMaxPerFingerprint() {
        let t = MultisetReconciler.targets(
            guestCounts: ["base": 1, "bulk": 3, "guestOnly": 2],
            userCounts: ["base": 1, "bulk": 1, "userOnly": 4]
        )
        #expect(t["base"] == 1)        // общая база не удваивается
        #expect(t["bulk"] == 3)        // легитимные дубли bulk-импорта сохраняются
        #expect(t["guestOnly"] == 2)   // дельта guest
        #expect(t["userOnly"] == 4)    // user-only не теряется
    }

    // MARK: - MultisetReconciler.instancesToDelete

    @Test func delete_collapsesDuplicatedBaseToTargetOne() {
        // База продублирована импортом: user(1) + guest(1) = 2 экземпляра, target=1 → удалить 1 (старейший).
        let instances: [(fingerprint: ScopeFingerprint, updatedAt: Date, ref: Int)] = [
            ("base", Date(timeIntervalSince1970: 100), 1),  // старый (user-оригинал)
            ("base", Date(timeIntervalSince1970: 200), 2)   // новый (guest-правка)
        ]
        let del = MultisetReconciler.instancesToDelete(instances, targets: ["base": 1])
        #expect(del == [1]) // LWW: оставляем новый (ref 2), удаляем старый (ref 1)
    }

    @Test func delete_preservesLegitBulkDuplicates() {
        // 3 идентичных bulk-транзакции, target=3 → не удаляем ничего.
        let instances: [(fingerprint: ScopeFingerprint, updatedAt: Date, ref: Int)] = [
            ("bulk", Date(timeIntervalSince1970: 100), 1),
            ("bulk", Date(timeIntervalSince1970: 100), 2),
            ("bulk", Date(timeIntervalSince1970: 100), 3)
        ]
        let del = MultisetReconciler.instancesToDelete(instances, targets: ["bulk": 3])
        #expect(del.isEmpty)
    }

    @Test func delete_deterministicOnEqualUpdatedAt() {
        // 4 экземпляра одинакового updatedAt, target=2 → удаляем 2 последних по индексу входа (детерминизм).
        let instances: [(fingerprint: ScopeFingerprint, updatedAt: Date, ref: Int)] = [
            ("fp", Date(timeIntervalSince1970: 100), 10),
            ("fp", Date(timeIntervalSince1970: 100), 20),
            ("fp", Date(timeIntervalSince1970: 100), 30),
            ("fp", Date(timeIntervalSince1970: 100), 40)
        ]
        let del = MultisetReconciler.instancesToDelete(instances, targets: ["fp": 2]).sorted()
        #expect(del == [30, 40])
    }

    @Test func delete_untouchedWhenFingerprintMissingFromTargets() {
        let instances: [(fingerprint: ScopeFingerprint, updatedAt: Date, ref: Int)] = [
            ("unknown", Date(timeIntervalSince1970: 100), 1),
            ("unknown", Date(timeIntervalSince1970: 100), 2)
        ]
        let del = MultisetReconciler.instancesToDelete(instances, targets: [:])
        #expect(del.isEmpty)
    }
}
