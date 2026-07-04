import Foundation

/// Чистое ядро reconciliation (Track B, B2a): детектор расхождения, lineage-check,
/// multiset-дедуп. Ни одной зависимости от SwiftData — только Sendable-значения,
/// поэтому покрывается быстрыми детерминированными unit-тестами.

// MARK: - Детектор расхождения (спека §1)

enum DivergenceDetector {
    /// Есть ли смысл запускать дорогой merge. Дёшево: только счётчики и водяные знаки.
    /// Расхождение = для любой модели `guest.count > user.count` ИЛИ `guest.maxUpdatedAt > user.maxUpdatedAt`.
    static func hasDivergence(_ signals: [ModelDivergenceSignal]) -> Bool {
        for s in signals {
            if s.guestCount > s.userCount { return true }
            if let g = s.guestMaxUpdatedAt {
                guard let u = s.userMaxUpdatedAt else { return true }
                if g > u { return true }
            }
        }
        return false
    }
}

// MARK: - Lineage-check (митигация B1b №1)

enum ScopeLineageChecker {
    /// Решает, безопасно ли авто-мержить guest в user.
    /// - guestIsEmpty/userIsEmpty — общая пустота стора (по всем моделям), не только по fingerprints.
    /// - *Fingerprints — множества СТАБИЛЬНЫХ identity-ключей (счета/карты/кредиты/инвестиции/группы/транзакции).
    ///
    /// Консервативно: если структурную родословную подтвердить нельзя (у одной из сторон нет ни одного
    /// identity-fingerprint), НЕ мержим молча — откладываем. Ложно-положительный «чужой guest» безопаснее
    /// (данные не теряются, просто остаются разделены), чем молчаливое слияние чужого профиля.
    static func decide(
        guestFingerprints: Set<ScopeFingerprint>,
        userFingerprints: Set<ScopeFingerprint>,
        guestIsEmpty: Bool,
        userIsEmpty: Bool
    ) -> LineageDecision {
        if guestIsEmpty { return .noGuestData }
        if userIsEmpty { return .userEmpty }
        if guestFingerprints.isEmpty || userFingerprints.isEmpty { return .foreignGuest }
        if guestFingerprints.isDisjoint(with: userFingerprints) { return .foreignGuest }
        return .proceed
    }
}

// MARK: - Multiset-дедуп (митигация B1b №3)

enum MultisetReconciler {
    /// Целевое число экземпляров на fingerprint = max(guest, user).
    /// НЕ схлопываем легитимные дубли bulk-импорта (у них совпадают все поля, включая createdAt),
    /// но и не удваиваем общую first-login базу (её экземпляры перекрываются, а не суммируются).
    static func targets(
        guestCounts: [ScopeFingerprint: Int],
        userCounts: [ScopeFingerprint: Int]
    ) -> [ScopeFingerprint: Int] {
        var result = guestCounts
        for (fp, u) in userCounts {
            result[fp] = max(result[fp] ?? 0, u)
        }
        return result
    }

    /// Возвращает ref-ы экземпляров к удалению из слитого набора.
    /// В каждой группе fingerprint оставляем `target` самых свежих (LWW по `updatedAt`),
    /// остальные — на удаление. Порядок при равных `updatedAt` детерминирован (индекс входа),
    /// чтобы поведение было воспроизводимо в тестах и на устройстве.
    /// Fingerprint, отсутствующий в `targets`, не трогаем (target = размер группы).
    static func instancesToDelete<Ref>(
        _ instances: [(fingerprint: ScopeFingerprint, updatedAt: Date, ref: Ref)],
        targets: [ScopeFingerprint: Int]
    ) -> [Ref] {
        var byFP: [ScopeFingerprint: [(index: Int, updatedAt: Date, ref: Ref)]] = [:]
        for (index, item) in instances.enumerated() {
            byFP[item.fingerprint, default: []].append((index, item.updatedAt, item.ref))
        }

        var toDelete: [Ref] = []
        for (fp, group) in byFP {
            let target = targets[fp] ?? group.count
            guard group.count > target else { continue }
            let ordered = group.sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.index < rhs.index
            }
            toDelete.append(contentsOf: ordered.dropFirst(target).map(\.ref))
        }
        return toDelete
    }
}
