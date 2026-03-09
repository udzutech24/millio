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
            BackupL10n.tr("backup.encryption.mode.device.title", fallback: "On this device")
        case .passphrase:
            BackupL10n.tr("backup.encryption.mode.passphrase.title", fallback: "Passphrase")
        }
    }

    var shortTitle: String {
        switch self {
        case .deviceKey:
            BackupL10n.tr("backup.encryption.mode.device.short", fallback: "Device")
        case .passphrase:
            BackupL10n.tr("backup.encryption.mode.passphrase.short", fallback: "Phrase")
        }
    }

    var summary: String {
        switch self {
        case .deviceKey:
            BackupL10n.tr("backup.encryption.mode.device.summary", fallback: "The key is stored in secure iOS storage on this device.")
        case .passphrase:
            BackupL10n.tr("backup.encryption.mode.passphrase.summary", fallback: "You can restore on a new device using the passphrase.")
        }
    }

    var restoreRisk: String {
        switch self {
        case .deviceKey:
            BackupL10n.tr(
                "backup.encryption.mode.device.risk",
                fallback: "After deleting the app or switching devices, restore may not be available."
            )
        case .passphrase:
            BackupL10n.tr("backup.encryption.mode.passphrase.risk", fallback: "If you lose the passphrase, restore is impossible.")
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
            title = BackupL10n.tr("backup.dashboard.title.off", fallback: "Backup is off")
            subtitle = BackupL10n.tr("backup.dashboard.subtitle.off", fallback: "Data stays on this device.")
        } else if !isICloudAvailable {
            title = BackupL10n.tr("backup.dashboard.title.need_icloud", fallback: "iCloud required")
            subtitle = BackupL10n.tr("backup.dashboard.subtitle.need_icloud", fallback: "Enable iCloud for Millio.")
        } else if let lastBackupDate {
            title = BackupL10n.tr("backup.dashboard.title.ready", fallback: "Backup is configured")
            subtitle = BackupL10n.format(
                "backup.dashboard.subtitle.last_backup_format",
                fallback: "Last backup: %@.",
                relativeBackupDate(lastBackupDate)
            )
        } else {
            title = BackupL10n.tr("backup.dashboard.title.almost", fallback: "Almost done")
            subtitle = BackupL10n.tr("backup.dashboard.subtitle.almost", fallback: "Create your first backup.")
        }

        let storageTitle: String
        let storageDetail: String
        if isBackupEnabled, isICloudAvailable {
            storageTitle = BackupL10n.tr("backup.dashboard.storage.title.icloud", fallback: "Stored in iCloud")
            storageDetail = BackupL10n.tr(
                "backup.dashboard.storage.detail.icloud",
                fallback: "Backups are saved in your private CloudKit container."
            )
        } else if isBackupEnabled {
            storageTitle = BackupL10n.tr("backup.dashboard.storage.title.unavailable", fallback: "Storage unavailable")
            storageDetail = BackupL10n.tr(
                "backup.dashboard.storage.detail.unavailable",
                fallback: "While iCloud is unavailable, new backups cannot be created."
            )
        } else {
            storageTitle = BackupL10n.tr("backup.dashboard.storage.title.local", fallback: "On-device only")
            storageDetail = BackupL10n.tr(
                "backup.dashboard.storage.detail.local",
                fallback: "While backup is off, data remains local."
            )
        }

        let trustTitle: String
        let trustDetail: String
        switch encryptionMode {
        case .deviceKey:
            trustTitle = BackupL10n.tr("backup.dashboard.trust.title.device", fallback: "Protection: device key")
            trustDetail = BackupL10n.tr(
                "backup.dashboard.trust.detail.device",
                fallback: "The key is kept in this device's Keychain. Migration may fail."
            )
        case .passphrase:
            trustTitle = BackupL10n.tr("backup.dashboard.trust.title.passphrase", fallback: "Protection: passphrase")
            trustDetail = BackupL10n.tr(
                "backup.dashboard.trust.detail.passphrase",
                fallback: "Only you know the passphrase. Millio does not store or recover it."
            )
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
        isICloudAvailable
            ? BackupL10n.tr("backup.restore.empty.title.not_found", fallback: "Backup not found")
            : BackupL10n.tr("backup.restore.empty.title.icloud_unavailable", fallback: "iCloud is unavailable")
    }

    static func restoreEmptyStateMessage(isICloudAvailable: Bool) -> String {
        if isICloudAvailable {
            return BackupL10n.tr(
                "backup.restore.empty.message.not_found",
                fallback: "No saved backups were found in your private CloudKit container for this Apple ID."
            )
        }
        return BackupL10n.tr(
            "backup.restore.empty.message.icloud_unavailable",
            fallback: "Without iCloud access, Millio cannot check backups or restore data."
        )
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
                title: BackupL10n.tr("backup.readiness.backup_enabled.title", fallback: "Backup is enabled"),
                detail: isBackupEnabled
                    ? BackupL10n.tr("backup.readiness.backup_enabled.detail.on", fallback: "Auto backup runs when the app goes to background.")
                    : BackupL10n.tr("backup.readiness.backup_enabled.detail.off", fallback: "Turn on backup."),
                isComplete: isBackupEnabled
            ),
            BackupReadinessItem(
                title: BackupL10n.tr("backup.readiness.icloud.title", fallback: "iCloud is available"),
                detail: isICloudAvailable
                    ? BackupL10n.tr("backup.readiness.icloud.detail.on", fallback: "Saving and restoring are available.")
                    : BackupL10n.tr("backup.readiness.icloud.detail.off", fallback: "Check iCloud sign-in and Millio access."),
                isComplete: isICloudAvailable
            ),
            BackupReadinessItem(
                title: BackupL10n.tr("backup.readiness.protection.title", fallback: "Protection is configured"),
                detail: encryptionMode == .passphrase
                    ? BackupL10n.tr("backup.readiness.protection.detail.passphrase", fallback: "Cross-device restore via passphrase is available.")
                    : BackupL10n.tr("backup.readiness.protection.detail.device", fallback: "Key is tied to this device."),
                isComplete: true
            ),
            BackupReadinessItem(
                title: BackupL10n.tr("backup.readiness.has_recent.title", fallback: "Recent backup exists"),
                detail: lastBackupDate != nil
                    ? BackupL10n.tr("backup.readiness.has_recent.detail.on", fallback: "A backup is ready for restore.")
                    : BackupL10n.tr("backup.readiness.has_recent.detail.off", fallback: "Create your first backup manually."),
                isComplete: lastBackupDate != nil
            ),
            BackupReadinessItem(
                title: BackupL10n.tr("backup.readiness.has_pinned.title", fallback: "Saved version exists"),
                detail: hasPinnedVersions
                    ? BackupL10n.tr("backup.readiness.has_pinned.detail.on", fallback: "At least one version is pinned.")
                    : BackupL10n.tr("backup.readiness.has_pinned.detail.off", fallback: "Pin a dedicated version when needed."),
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
