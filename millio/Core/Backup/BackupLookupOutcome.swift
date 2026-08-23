//
//  BackupLookupOutcome.swift
//  millio
//
//  Created by Александр Сидоркин on 23.08.2026.
//

import Foundation
import CloudKit

/// Почему поиск бэкапа не дал ответа. Отделено от «бэкапов нет»: пользователь, у которого
/// облако не ответило, не должен видеть «резервная копия не найдена» и уходить в онбординг
/// поверх восстановимых данных (D8).
enum BackupLookupFailureReason: String, Equatable, Sendable {
    /// iCloud выключен, нет аккаунта или аккаунт временно недоступен.
    case iCloudUnavailable
    /// Нет сети или запрос к CloudKit не дошёл.
    case network
    /// Квота/троттлинг/сервис занят — имеет смысл повторить позже.
    case serviceBusy
    /// Всё остальное: причина в лог, пользователю — общий текст.
    case unknown

    /// Классификация без зависимости от рантайма CloudKit: разбираем `NSError` по домену и коду,
    /// поэтому исход воспроизводим в тестах.
    static func classify(_ error: Error) -> BackupLookupFailureReason {
        let nsError = error as NSError

        if nsError.domain == NSURLErrorDomain {
            return .network
        }

        guard nsError.domain == CKErrorDomain, let code = CKError.Code(rawValue: nsError.code) else {
            return .unknown
        }

        switch code {
        case .notAuthenticated, .managedAccountRestricted, .permissionFailure, .accountTemporarilyUnavailable:
            return .iCloudUnavailable
        case .networkUnavailable, .networkFailure:
            return .network
        case .requestRateLimited, .serviceUnavailable, .zoneBusy, .quotaExceeded:
            return .serviceBusy
        default:
            return .unknown
        }
    }

    var localizationKey: String {
        switch self {
        case .iCloudUnavailable:
            return "backup.restore.lookup.failure.icloud"
        case .network:
            return "backup.restore.lookup.failure.network"
        case .serviceBusy:
            return "backup.restore.lookup.failure.busy"
        case .unknown:
            return "backup.restore.lookup.failure.unknown"
        }
    }

    private var englishFallback: String {
        switch self {
        case .iCloudUnavailable:
            return "iCloud is unavailable on this device, so backups cannot be listed. Sign in to iCloud and try again."
        case .network:
            return "No connection to iCloud. Check the network and try again."
        case .serviceBusy:
            return "iCloud is busy right now. Try again in a minute."
        case .unknown:
            return "Could not get the list of backups from iCloud. Try again."
        }
    }

    var userMessage: String {
        BackupL10n.tr(localizationKey, fallback: englishFallback)
    }
}

/// Различимые исходы поиска бэкапа. До R4 UI получал `[]`/`nil` и трактовал ЛЮБОЙ исход
/// как «бэкапов нет» — ошибка облака была неотличима от пустого списка.
enum BackupLookupOutcome: Equatable, Sendable {
    case found([BackupVersionInfo])
    case empty
    case failed(BackupLookupFailureReason)
    case timedOut

    var versions: [BackupVersionInfo] {
        if case .found(let versions) = self { return versions }
        return []
    }

    /// Лукап не дал ответа (ошибка или таймаут) — данные о наличии бэкапа неизвестны.
    var isUnresolved: Bool {
        switch self {
        case .found, .empty:
            return false
        case .failed, .timedOut:
            return true
        }
    }

    /// Строка для логов: без пользовательских данных, только исход и количество.
    var diagnosticSummary: String {
        switch self {
        case .found(let versions):
            return "backup_lookup found=\(versions.count)"
        case .empty:
            return "backup_lookup empty"
        case .failed(let reason):
            return "backup_lookup failed=\(reason.rawValue)"
        case .timedOut:
            return "backup_lookup timed_out"
        }
    }
}

extension BackupManagerProtocol {
    /// Поиск версий бэкапа с ограничением по времени. «Облако молчит» — отдельный исход `.timedOut`,
    /// а не пустой список: молчание CloudKit и отсутствие копий требуют разных действий пользователя.
    func lookupBackupVersions(timeout: TimeInterval) async -> BackupLookupOutcome {
        await withTaskGroup(of: BackupLookupOutcome?.self, returning: BackupLookupOutcome.self) { group in
            group.addTask {
                await self.lookupBackupVersions()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(max(0, timeout)))
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .timedOut
        }
    }

    /// Дефолт для конформеров, у которых нет доступа к причине отказа (моки, локальный менеджер):
    /// список либо есть, либо пуст. Реальную причину даёт `BackupManager`.
    func lookupBackupVersions() async -> BackupLookupOutcome {
        let versions = await listBackupVersions()
        return versions.isEmpty ? .empty : .found(versions)
    }
}
