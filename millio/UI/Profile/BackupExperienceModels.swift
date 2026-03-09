//
//  BackupExperienceModels.swift
//  millio
//
//  Created by Codex on 06.03.2026.
//

import Foundation

enum BackupEncryptionMode: String, CaseIterable, Identifiable {
    case deviceKey
    case passphrase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deviceKey:
            "На этом устройстве"
        case .passphrase:
            "Кодовая фраза"
        }
    }

    var shortTitle: String {
        switch self {
        case .deviceKey:
            "Устройство"
        case .passphrase:
            "Фраза"
        }
    }

    var summary: String {
        switch self {
        case .deviceKey:
            "Ключ хранится в защищенном хранилище iOS на этом устройстве."
        case .passphrase:
            "Копию можно восстановить на новом устройстве по кодовой фразе."
        }
    }

    var restoreRisk: String {
        switch self {
        case .deviceKey:
            "После удаления приложения или смены устройства восстановление может быть недоступно."
        case .passphrase:
            "Если потерять кодовую фразу, восстановление будет невозможно."
        }
    }
}

struct BackupReadinessItem: Equatable, Identifiable {
    let title: String
    let detail: String
    let isComplete: Bool

    var id: String { title }
}

struct BackupDashboardContent: Equatable {
    let title: String
    let subtitle: String
    let storageTitle: String
    let storageDetail: String
    let trustTitle: String
    let trustDetail: String
    let readiness: [BackupReadinessItem]
}

enum BackupExperiencePresenter {
    static func dashboard(
        isBackupEnabled: Bool,
        isICloudAvailable: Bool,
        lastBackupDate: Date?,
        encryptionMode: BackupEncryptionMode,
        hasPinnedVersions: Bool
    ) -> BackupDashboardContent {
        let title: String
        let subtitle: String

        if !isBackupEnabled {
            title = "Резервное копирование выключено"
            subtitle = "Данные остаются на устройстве."
        } else if !isICloudAvailable {
            title = "Нужен iCloud"
            subtitle = "Включите iCloud для Millio."
        } else if let lastBackupDate {
            title = "Копирование настроено"
            subtitle = "Последняя копия: \(relativeBackupDate(lastBackupDate))."
        } else {
            title = "Почти готово"
            subtitle = "Осталось создать первую копию."
        }

        let storageTitle: String
        let storageDetail: String
        if isBackupEnabled, isICloudAvailable {
            storageTitle = "Хранение в iCloud"
            storageDetail = "Копии лежат в вашем приватном CloudKit-контейнере."
        } else if isBackupEnabled {
            storageTitle = "Хранение недоступно"
            storageDetail = "Пока iCloud недоступен, новые копии не создаются."
        } else {
            storageTitle = "Только на устройстве"
            storageDetail = "Пока копирование выключено, данные остаются локально."
        }

        let trustTitle: String
        let trustDetail: String
        switch encryptionMode {
        case .deviceKey:
            trustTitle = "Защита: ключ на устройстве"
            trustDetail = "Ключ хранится в Keychain этого устройства. Перенос может не сработать."
        case .passphrase:
            trustTitle = "Защита: кодовая фраза"
            trustDetail = "Фраза известна только вам. Millio ее не хранит и не восстанавливает."
        }

        return BackupDashboardContent(
            title: title,
            subtitle: subtitle,
            storageTitle: storageTitle,
            storageDetail: storageDetail,
            trustTitle: trustTitle,
            trustDetail: trustDetail,
            readiness: readiness(
                isBackupEnabled: isBackupEnabled,
                isICloudAvailable: isICloudAvailable,
                lastBackupDate: lastBackupDate,
                encryptionMode: encryptionMode,
                hasPinnedVersions: hasPinnedVersions
            )
        )
    }

    static func restoreEmptyStateTitle(isICloudAvailable: Bool) -> String {
        isICloudAvailable ? "Резервная копия не найдена" : "iCloud сейчас недоступен"
    }

    static func restoreEmptyStateMessage(isICloudAvailable: Bool) -> String {
        if isICloudAvailable {
            return "Мы не нашли сохраненные копии в вашем приватном CloudKit контейнере для этого Apple ID."
        }
        return "Без доступа к iCloud Millio не сможет проверить наличие резервных копий и восстановить данные."
    }

    private static func readiness(
        isBackupEnabled: Bool,
        isICloudAvailable: Bool,
        lastBackupDate: Date?,
        encryptionMode: BackupEncryptionMode,
        hasPinnedVersions: Bool
    ) -> [BackupReadinessItem] {
        [
            BackupReadinessItem(
                title: "Резервное копирование включено",
                detail: isBackupEnabled ? "Автокопия создается при уходе в фон." : "Нужно включить резервное копирование.",
                isComplete: isBackupEnabled
            ),
            BackupReadinessItem(
                title: "iCloud доступен",
                detail: isICloudAvailable ? "Можно сохранять и восстанавливать." : "Проверьте вход в iCloud и доступ Millio.",
                isComplete: isICloudAvailable
            ),
            BackupReadinessItem(
                title: "Защита настроена",
                detail: encryptionMode == .passphrase ? "Есть перенос по кодовой фразе." : "Ключ привязан к устройству.",
                isComplete: true
            ),
            BackupReadinessItem(
                title: "Есть актуальная копия",
                detail: lastBackupDate != nil ? "Есть копия для восстановления." : "Создайте первую копию вручную.",
                isComplete: lastBackupDate != nil
            ),
            BackupReadinessItem(
                title: "Есть сохраненная версия",
                detail: hasPinnedVersions ? "Хотя бы одна версия закреплена." : "При необходимости сохраните отдельную версию.",
                isComplete: hasPinnedVersions
            )
        ]
    }

    private static func relativeBackupDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
