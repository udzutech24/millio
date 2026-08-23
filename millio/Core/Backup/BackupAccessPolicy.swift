//
//  BackupAccessPolicy.swift
//  millio
//

import Foundation

/// Кто вправе работать с облачными копиями (R10).
///
/// CloudKit Private DB привязана к iCloud-аккаунту УСТРОЙСТВА, а не к аккаунту Millio. Поэтому
/// в гостевом сторе облако честно отдаёт копии владельца устройства: список версий виден без
/// входа, а восстановление кладёт чужие финансовые данные в гостевой стор (и после логина они
/// уезжают в reconciliation guest→user). Единственный ключ доступа — авторизованный scope данных.
///
/// Проверка живёт на уровне сервиса (`SwitchingBackupManager`), а не только в UI: экранов,
/// дергающих `BackupManagerProtocol`, несколько, и каждый следующий заново открыл бы дыру.
enum BackupAccessPolicy {
    /// `scopeKey` — `DataScope.storeConfigurationName` активного стора (`AppState.activeScopeKey`).
    /// Именно стор-назначение, а не флаг авторизации: важно, куда физически лягут данные.
    static func isCloudAccessAllowed(scopeKey: String) -> Bool {
        scopeKey != DataScope.guest.storeConfigurationName
    }

    static var denialError: AppError { .backupRequiresSignIn }
}
