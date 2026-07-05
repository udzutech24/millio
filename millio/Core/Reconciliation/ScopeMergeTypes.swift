import Foundation

/// Значимые типы для reconciliation данных guest↔user (Track B).
/// Отделены от SwiftData-слоя намеренно: ядро алгоритмов (детектор/lineage/multiset)
/// работает на плоских Sendable-значениях и покрывается чистыми unit-тестами без in-memory
/// контейнера; SwiftData-адаптеры (fetch/insert/delete) живут в worker'е (B2b).

/// Стабильный между сторами отпечаток логической сущности.
/// Для моделей с бизнес-ключом = их `*UniqueID`; для keyless-моделей = канонический
/// снимок `export()` без волатильных полей (см. `ScopeFingerprintBuilder`).
typealias ScopeFingerprint = String

/// Сигнал расхождения по одной модели (двухсигнальный детектор, спека §1).
struct ModelDivergenceSignal: Sendable, Equatable {
    let modelName: String
    let guestCount: Int
    let userCount: Int
    /// Водяной знак контента: наибольший `updatedAt` среди сущностей модели (nil — модели нет/поле отсутствует).
    let guestMaxUpdatedAt: Date?
    let userMaxUpdatedAt: Date?
}

/// Решение lineage-check перед авто-merge (митигация B1b №1: защита от чужого guest на шаренном устройстве).
enum LineageDecision: Sendable, Equatable {
    /// Общая родословная (есть пересечение стабильных fingerprints) — мержим.
    case proceed
    /// guest пуст — мержить нечего.
    case noGuestData
    /// user-стор пуст — авто-merge запрещён: невозможно подтвердить, что guest принадлежит этому пользователю.
    case userEmpty
    /// Оба непусты, но пересечения identity-fingerprints нет — вероятно чужой guest. Откладываем с флагом подтверждения.
    case foreignGuest
}

/// Итог reconciliation для одного перехода guest→user.
enum ScopeMergeOutcome: Sendable, Equatable {
    /// Merge выполнен, данные слиты. Несёт сводку для UI.
    case merged(ScopeMergeReport)
    /// Расхождения нет — user уже актуален (детектор-скрининг, дёшево).
    case noDivergence
    /// Уже выполнено ранее (done-маркер) — идемпотентный ретрай пропущен.
    case alreadyDone
    /// Отложено lineage-check'ом (чужой guest / нет родословной) — требует подтверждения владельца.
    case deferredForeignGuest
    /// Пропущено (user пуст / guest отсутствует / нет контейнера).
    case skipped
    /// Прервано sanity-abort'ом (merged > guest+user) — на диск ничего не записано.
    case abortedSanity
}

/// По-модельные счётчики добавленных сущностей (для сводки пользователю и done-маркера).
struct ScopeMergeReport: Sendable, Equatable, Codable {
    /// Сколько легаси-счетов (Card/Credit/Investment/FinanceAccount) и core-`Account` добавлено суммарно.
    var accountsAdded: Int = 0
    /// Сколько операций (CashflowTransaction + core AccountEvent) добавлено суммарно.
    var transactionsAdded: Int = 0
    /// Опционально — партиально-читаемый стор (V4 no-plan fallback): done-маркер НЕ ставить (митигация B1b №6).
    var partiallyReadable: Bool = false
}
