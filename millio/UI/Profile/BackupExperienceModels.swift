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
            subtitle = "Данные остаются локально на устройстве, автоматические копии не создаются."
        } else if !isICloudAvailable {
            title = "Резервное копирование требует iCloud"
            subtitle = "Включите iCloud для Millio, чтобы копии сохранялись в вашем облачном аккаунте."
        } else if let lastBackupDate {
            title = "Резервное копирование настроено"
            subtitle = "Последняя копия создана \(relativeBackupDate(lastBackupDate))."
        } else {
            title = "Резервное копирование почти готово"
            subtitle = "Защита уже настроена. Осталось создать первую копию."
        }

        let storageTitle: String
        let storageDetail: String
        if isBackupEnabled, isICloudAvailable {
            storageTitle = "Хранение: приватная база iCloud"
            storageDetail = "Снимки сохраняются в вашем private CloudKit container. Они привязаны к вашему Apple ID, а не к публичному хранилищу Millio."
        } else if isBackupEnabled {
            storageTitle = "Хранение недоступно"
            storageDetail = "Пока iCloud недоступен, новые облачные копии не будут создаваться."
        } else {
            storageTitle = "Хранение: только на устройстве"
            storageDetail = "Пока резервное копирование выключено, данные хранятся локально в SwiftData на этом устройстве."
        }

        let trustTitle: String
        let trustDetail: String
        switch encryptionMode {
        case .deviceKey:
            trustTitle = "Защита: ключ на устройстве"
            trustDetail = "Копия шифруется, а ключ остается в iOS Keychain на этом устройстве. Это удобно, но перенос на новое устройство может не сработать."
        case .passphrase:
            trustTitle = "Защита: кодовая фраза"
            trustDetail = "Копия шифруется до отправки в iCloud. Millio не хранит вашу кодовую фразу и не сможет восстановить ее за вас."
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
                detail: isBackupEnabled ? "Автоматическая копия будет создаваться при уходе приложения в фон." : "Включите резервное копирование, чтобы Millio начал создавать копии.",
                isComplete: isBackupEnabled
            ),
            BackupReadinessItem(
                title: "iCloud доступен",
                detail: isICloudAvailable ? "CloudKit Private Database доступна для сохранения и восстановления." : "Проверьте вход в iCloud и доступ Millio к облаку.",
                isComplete: isICloudAvailable
            ),
            BackupReadinessItem(
                title: "Защита настроена",
                detail: encryptionMode.summary + " " + encryptionMode.restoreRisk,
                isComplete: true
            ),
            BackupReadinessItem(
                title: "Есть актуальная копия",
                detail: lastBackupDate != nil ? "Можно восстановить состояние из последней облачной копии." : "Создайте первую копию вручную, чтобы убедиться, что восстановление будет доступно.",
                isComplete: lastBackupDate != nil
            ),
            BackupReadinessItem(
                title: "Сохраненные копии",
                detail: hasPinnedVersions ? "Есть хотя бы одна закрепленная копия, которая не удаляется автоматически." : "При необходимости сохраните дополнительную копию как версию.",
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
