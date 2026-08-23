//
//  IncomingBackupFileIntake.swift
//  millio
//

import Foundation

/// Приём входящего файла бэкапа (Files/AirDrop) до подтверждения восстановления.
///
/// Вынесено из `IncomingBackupFileRestoreModifier`, чтобы порядок «файл пришёл раньше готовности DI»
/// проверялся тестом, а не только руками на устройстве.
@MainActor
struct IncomingBackupFileIntake {
    /// Потолок с большим запасом: реальный бэкап владельца — 134 КБ на 1673 моделях.
    /// Ограничение не про приватность, а против self-DoS: файл читается в память целиком,
    /// гигабайтный «бэкап» из Files = jetsam-kill вместо понятной ошибки.
    nonisolated static let maxFileSizeBytes: Int64 = 256 * 1024 * 1024

    enum Outcome {
        /// DI ещё не собран: URL НЕ потреблён, попытку надо повторить по готовности.
        case deferredUntilReady
        case prepared(PendingBackupFile)
        case failed(message: String)
    }

    let appState: AppState
    let backupManager: BackupManagerProtocol?

    func intake(_ url: URL) async -> Outcome {
        // Холодный старт из Files: `onOpenURL` приходит раньше, чем собран DIContainer. Потребить
        // URL здесь — значит потерять файл и показать ложное «iCloud недоступен».
        guard let backupManager else { return .deferredUntilReady }

        // Потребление ДО любого await и до любого return ниже: `RootTabView` держит шиты выписок
        // заблокированными, пока значение != nil.
        appState.pendingIncomingBackupURL = nil

        let didAccessScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Self.readFile(at: url)
            let info = try await backupManager.inspectBackupFile(data)
            return .prepared(PendingBackupFile(data: data, info: info))
        } catch {
            return .failed(message: RestoreErrorPresenter.userMessage(for: error))
        }
    }

    /// Чтение файла с проверкой размера ДО загрузки в память.
    nonisolated static func readFile(at url: URL) throws -> Data {
        let declaredSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        if let declaredSize, Int64(declaredSize) > maxFileSizeBytes {
            throw tooLargeError
        }
        let data = try Data(contentsOf: url)
        if Int64(data.count) > maxFileSizeBytes {
            throw tooLargeError
        }
        return data
    }

    /// `.restoreFailed` несёт уже локализованный текст (см. `RestoreErrorPresenter`).
    nonisolated static var tooLargeError: AppError {
        AppError.restoreFailed(
            BackupL10n.tr(
                "backup.incoming_file.too_large",
                fallback: "This file is too large to be a Millio backup."
            )
        )
    }
}
