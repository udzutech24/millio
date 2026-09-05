//
//  AppliedPlannedNoticeStore.swift
//  millio
//
//  Журнал плановых операций, применённых автоматически и ещё не показанных пользователю.
//  Фаза 0 плана plans/2026-09-05__planned-operations-applied-notice.md.
//  Только информирование: балансовой арифметики здесь нет и быть не должно.
//

import Foundation

// MARK: - AppliedPlannedEntry

/// Одна применённая плановая операция в непоказанной сводке.
struct AppliedPlannedEntry: Codable, Identifiable, Equatable {

    /// Каким путём операция применилась. Влияет только на подачу в UI
    /// (проценты по вкладу помечаются как информационные).
    enum Kind: String, Codable {
        case scheduled
        case recurring
        case depositInterest
    }

    let id: UUID
    let title: String
    let accountName: String

    /// Знак задаёт направление: доход > 0, расход < 0. Нетто-итоги сводки считаются простым
    /// сложением, поэтому вызывающая сторона обязана передавать расход отрицательным —
    /// отдельного поля направления нет намеренно, чтобы знак и итог не могли разойтись.
    let amount: Decimal

    let currencyCode: String
    let appliedAt: Date
    let kind: Kind

    init(
        id: UUID = UUID(),
        title: String,
        accountName: String,
        amount: Decimal,
        currencyCode: String,
        appliedAt: Date,
        kind: Kind
    ) {
        self.id = id
        self.title = title
        self.accountName = accountName
        self.amount = amount
        self.currencyCode = currencyCode
        self.appliedAt = appliedAt
        self.kind = kind
    }
}

// MARK: - AppliedPlannedDigest

/// Сводка непоказанных применений: агрегат хранится ОТДЕЛЬНО от списка деталей.
///
/// Потолок `detailsCap` обрезает только `details`. `totalCount`, `totalsByCurrency` и счётчики
/// накапливаются на каждом `accumulate` и остаются точными при любом числе применений: иначе при
/// 300 применённых операциях сводка соврала бы пользователю «применилось 50».
struct AppliedPlannedDigest: Codable, Equatable {

    /// Потолок хранимых деталей. Ограничивает размер записи в UserDefaults, но не агрегат.
    static let detailsCap = 50

    private(set) var totalCount: Int
    private(set) var totalsByCurrency: [String: Decimal]
    private(set) var incomeCount: Int
    private(set) var expenseCount: Int
    private(set) var details: [AppliedPlannedEntry]

    init(
        totalCount: Int = 0,
        totalsByCurrency: [String: Decimal] = [:],
        incomeCount: Int = 0,
        expenseCount: Int = 0,
        details: [AppliedPlannedEntry] = []
    ) {
        self.totalCount = totalCount
        self.totalsByCurrency = totalsByCurrency
        self.incomeCount = incomeCount
        self.expenseCount = expenseCount
        self.details = details
    }

    var isEmpty: Bool { totalCount == 0 }

    /// Сколько применений не попало в `details` — для строки «и ещё N».
    var truncatedCount: Int { max(0, totalCount - details.count) }

    /// Учитывает запись в агрегате; в детали кладёт, только пока не выбран потолок.
    /// Сверх потолка отбрасываются поздние записи — список остаётся хронологически связным
    /// с начала, а «и ещё N» замыкает его в конце.
    mutating func accumulate(_ entry: AppliedPlannedEntry) {
        totalCount += 1
        totalsByCurrency[entry.currencyCode, default: 0] += entry.amount
        if entry.amount > 0 {
            incomeCount += 1
        } else if entry.amount < 0 {
            expenseCount += 1
        }
        if details.count < Self.detailsCap {
            details.append(entry)
        }
    }
}

// MARK: - AppliedPlannedNoticeStore

/// Копилка применённых плановых операций между их применением и показом сводки пользователю.
@MainActor
final class AppliedPlannedNoticeStore {

    /// Префикс per-scope ключа. Журнал разделён по scope по той же причине, что и чекпойнт
    /// авто-применения: гостевая сессия не должна ни видеть, ни гасить сводку владельца.
    static let storageKeyPrefix = "cashflow.appliedPlannedNotice.v1."

    private let defaults: UserDefaults
    private let storageKey: String

    /// `scopeIdentifier` — `DataScope.storeConfigurationName` открытого стора, ровно та же строка,
    /// что у чекпойнта в `CashflowScheduledService`. Прокидывается явно: `AppState.activeScopeKey`
    /// дефолтится в guest и на холодном старте может не получить реальный scope.
    init(defaults: UserDefaults, scopeIdentifier: String) {
        self.defaults = defaults
        self.storageKey = Self.storageKeyPrefix + scopeIdentifier
    }

    var hasPending: Bool { !loadDigest().isEmpty }

    func append(_ entry: AppliedPlannedEntry) {
        var digest = loadDigest()
        digest.accumulate(entry)
        save(digest)
    }

    /// Читает сводку и очищает журнал: повторный вызов вернёт `nil`, поэтому одна и та же
    /// сводка не покажется дважды.
    func takeDigest() -> AppliedPlannedDigest? {
        let digest = loadDigest()
        defaults.removeObject(forKey: storageKey)
        return digest.isEmpty ? nil : digest
    }

    // MARK: - Storage

    private func loadDigest() -> AppliedPlannedDigest {
        guard let data = defaults.data(forKey: storageKey) else { return AppliedPlannedDigest() }
        guard let digest = try? JSONDecoder().decode(AppliedPlannedDigest.self, from: data) else {
            // Битую или несовместимую запись показать всё равно нечем, а оставить — значит
            // занять ключ навсегда. Чистим: сводка просто не покажется один раз.
            defaults.removeObject(forKey: storageKey)
            return AppliedPlannedDigest()
        }
        return digest
    }

    private func save(_ digest: AppliedPlannedDigest) {
        guard let data = try? JSONEncoder().encode(digest) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
