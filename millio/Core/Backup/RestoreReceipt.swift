//
//  RestoreReceipt.swift
//  millio
//
//  Created by Александр Сидоркин on 22.08.2026.
//

import Foundation

/// Причина, по которой восстановление НЕ подтверждено пересчётом стора.
/// Бросается из деструктивной фазы restore до публикации успеха (R2).
enum RestoreVerificationFailure: Error, Equatable {
    /// В бэкапе ноль моделей — восстанавливать нечего, «успех» был бы неотличим от пустого экрана.
    case emptyBackup
    /// Импорт отработал без ошибки, но стор остался пустым.
    case emptyStoreAfterImport
    /// Типы, которые были в бэкапе, но не появились в сторе ни одной записью.
    case missingModelTypes([String])

    var localizationKey: String {
        switch self {
        case .emptyBackup:
            return "backup.restore.verification.empty_backup"
        case .emptyStoreAfterImport:
            return "backup.restore.verification.empty_store"
        case .missingModelTypes:
            return "backup.restore.verification.missing_types"
        }
    }

    private var englishFallback: String {
        switch self {
        case .emptyBackup:
            return "The backup contains no data, so there is nothing to restore"
        case .emptyStoreAfterImport:
            return "Restore finished but no data was written — the previous state has been rolled back"
        case .missingModelTypes:
            return "Some data from the backup was not restored"
        }
    }

    var userMessage: String {
        let base = BackupL10n.tr(localizationKey, fallback: englishFallback)
        guard case .missingModelTypes(let types) = self, !types.isEmpty else { return base }
        return "\(base): \(types.joined(separator: ", "))"
    }

    var appError: AppError {
        .restoreFailed(userMessage)
    }
}

/// Подтверждение восстановления: сколько моделей обещал бэкап и сколько реально оказалось в сторе.
/// Без него «успех» = «импорт не бросил ошибку», что и давало молча пустой экран после restore.
struct RestoreReceipt: Equatable {
    let expectedModelCount: Int
    let importedModelCount: Int
    let expectedByType: [String: Int]
    let importedByType: [String: Int]

    /// Типы из бэкапа, полностью отсутствующие в сторе после импорта.
    var missingTypes: [String] {
        expectedByType
            .filter { $0.value > 0 && (importedByType[$0.key] ?? 0) == 0 }
            .keys
            .sorted()
    }

    /// Импорт МОЖЕТ законно сократить число записей: `DataIntegrityCleaner.dedupeAll` схлопывает
    /// дубли (Card/Credit/Investment/FinanceGroup/категории). Поэтому строгое равенство счётчиков —
    /// не критерий успеха; критерий — данные записаны и ни один тип не потерян целиком.
    var reducedByDeduplication: Int {
        max(0, expectedModelCount - importedModelCount)
    }

    var verificationFailure: RestoreVerificationFailure? {
        if expectedModelCount == 0 { return .emptyBackup }
        if importedModelCount == 0 { return .emptyStoreAfterImport }
        let missing = missingTypes
        if !missing.isEmpty { return .missingModelTypes(missing) }
        return nil
    }

    var isVerified: Bool { verificationFailure == nil }

    /// Строка для логов и Crashlytics — без пользовательских данных, только счётчики.
    var diagnosticSummary: String {
        let status = isVerified ? "verified" : "unverified"
        return "restore_receipt \(status) expected=\(expectedModelCount) imported=\(importedModelCount) types=\(expectedByType.count) missing=\(missingTypes.count) deduped=\(reducedByDeduplication)"
    }
}

/// Пересчёт моделей в снимке формата backup (`{"models": [{"_type": ...}]}`) — единственный источник
/// цифр для `RestoreReceipt`. Оба входа (бэкап и повторный экспорт стора) имеют один и тот же формат.
enum RestoreModelCensus {
    static func counts(in backupData: Data) throws -> (total: Int, byType: [String: Int]) {
        guard
            let json = try? JSONSerialization.jsonObject(with: backupData) as? [String: Any],
            let models = json["models"] as? [[String: Any]]
        else {
            throw AppError.backupCorrupted
        }

        var byType: [String: Int] = [:]
        for model in models {
            guard let typeName = model["_type"] as? String else { throw AppError.backupCorrupted }
            byType[typeName, default: 0] += 1
        }
        return (models.count, byType)
    }

    static func makeReceipt(expectedBackup: Data, actualStoreExport: Data) throws -> RestoreReceipt {
        let expected = try counts(in: expectedBackup)
        let actual = try counts(in: actualStoreExport)
        return RestoreReceipt(
            expectedModelCount: expected.total,
            importedModelCount: actual.total,
            expectedByType: expected.byType,
            importedByType: actual.byType
        )
    }
}
