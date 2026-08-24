//
//  BackupExperienceModels.swift
//  millio
//
//  Created by Codex on 06.03.2026.
//

import CoreGraphics
import Foundation

enum BackupEncryptionMode: String, CaseIterable, Identifiable {
    case deviceKey
    case passphrase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deviceKey:
            BackupL10n.tr("backup.encryption.mode.device.title", fallback: "This iPhone only")
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
            BackupL10n.tr("backup.encryption.mode.device.summary", fallback: "Fastest setup. Restore is intended for this device only")
        case .passphrase:
            BackupL10n.tr("backup.encryption.mode.passphrase.summary", fallback: "Best for real backup. Use the same passphrase on a new device")
        }
    }

    var restoreRisk: String {
        switch self {
        case .deviceKey:
            BackupL10n.tr(
                "backup.encryption.mode.device.risk",
                fallback: "If you delete the app or move to another device, restore may fail"
            )
        case .passphrase:
            BackupL10n.tr("backup.encryption.mode.passphrase.risk", fallback: "Keep the passphrase somewhere safe. Millio cannot recover it")
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

enum BackupStatusRefreshPolicy {
    // Skip network work only when the screen already has a usable versions list.
    // Note: we do NOT skip when backup is disabled — users must be able to see
    // and restore existing backups even if the backup feature is currently off.
    static func shouldSkipManagementRefresh(
        force: Bool,
        isBackupEnabled: Bool,
        isICloudAvailable: Bool,
        lastBackupDate: Date?,
        loadedVersionCount: Int
    ) -> Bool {
        guard !force else { return false }
        return isICloudAvailable && lastBackupDate != nil && loadedVersionCount > 0
    }
}

enum BackupManagementLayout {
    // Narrow screens and long localized strings need a single-column layout.
    static func shouldStackMetrics(availableWidth: CGFloat) -> Bool {
        availableWidth < 360
    }

    static func shouldStackActionButtons(availableWidth: CGFloat) -> Bool {
        availableWidth < 390
    }
}

/// Что показать на экране восстановления, когда версия для восстановления не выбрана.
struct RestoreLookupPresentation: Equatable {
    let statusTitle: String
    let statusIcon: String
    let title: String
    let message: String
    let showsRetry: Bool
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
            title = BackupL10n.tr("backup.dashboard.title.off", fallback: "Your data is only local")
            subtitle = BackupL10n.tr("backup.dashboard.subtitle.off", fallback: "Turn on backup to keep a recovery copy in iCloud")
        } else if !isICloudAvailable {
            title = BackupL10n.tr("backup.dashboard.title.need_icloud", fallback: "Waiting for iCloud")
            subtitle = BackupL10n.tr("backup.dashboard.subtitle.need_icloud", fallback: "Check iCloud sign-in and allow Millio to use it")
        } else if let lastBackupDate {
            title = BackupL10n.tr("backup.dashboard.title.ready", fallback: "Backup is ready")
            subtitle = BackupL10n.format(
                "backup.dashboard.subtitle.last_backup_format",
                fallback: "Last backup %@. Millio also refreshes backup automatically while you use the app.",
                relativeBackupDate(lastBackupDate)
            )
        } else {
            title = BackupL10n.tr("backup.dashboard.title.almost", fallback: "Create your first backup")
            subtitle = BackupL10n.tr("backup.dashboard.subtitle.almost", fallback: "Save one backup now so restore is ready if anything goes wrong")
        }

        let storageTitle: String
        let storageDetail: String
        if isBackupEnabled, isICloudAvailable {
            storageTitle = BackupL10n.tr("backup.dashboard.storage.title.icloud", fallback: "Saved in iCloud")
            storageDetail = BackupL10n.tr(
                "backup.dashboard.storage.detail.icloud",
                fallback: "Backups are kept in your private iCloud space, not in a public Millio database"
            )
        } else if isBackupEnabled {
            storageTitle = BackupL10n.tr("backup.dashboard.storage.title.unavailable", fallback: "iCloud unavailable")
            storageDetail = BackupL10n.tr(
                "backup.dashboard.storage.detail.unavailable",
                fallback: "Until iCloud responds, Millio cannot create or restore backups"
            )
        } else {
            storageTitle = BackupL10n.tr("backup.dashboard.storage.title.local", fallback: "Only on this device")
            storageDetail = BackupL10n.tr(
                "backup.dashboard.storage.detail.local",
                fallback: "If the app is deleted, your local data may be lost"
            )
        }

        let trustTitle: String
        let trustDetail: String
        switch encryptionMode {
        case .deviceKey:
            trustTitle = BackupL10n.tr("backup.dashboard.trust.title.device", fallback: "Protection: this iPhone only")
            trustDetail = BackupL10n.tr(
                "backup.dashboard.trust.detail.device",
                fallback: "Quickest option, but not the safest choice for reinstall or a new device"
            )
        case .passphrase:
            trustTitle = BackupL10n.tr("backup.dashboard.trust.title.passphrase", fallback: "Protection: passphrase")
            trustDetail = BackupL10n.tr(
                "backup.dashboard.trust.detail.passphrase",
                fallback: "Recommended. The same passphrase lets you restore on another device"
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

    /// Состояние экрана восстановления по исходу поиска бэкапа. «Копий нет» и «облако не ответило» —
    /// разные экраны: во втором случае данные могут существовать, и уход в онбординг опасен (D8).
    static func restoreLookupPresentation(
        outcome: BackupLookupOutcome,
        isICloudAvailable: Bool
    ) -> RestoreLookupPresentation {
        switch outcome {
        case .timedOut:
            return RestoreLookupPresentation(
                statusTitle: BackupL10n.tr("backup.restore.lookup.timedout", fallback: "Still Searching"),
                statusIcon: "hourglass.circle.fill",
                title: BackupL10n.tr("backup.restore.lookup.timedout.title", fallback: "iCloud did not respond"),
                message: BackupL10n.tr(
                    "backup.restore.lookup.timedout.message",
                    fallback: "The backup list did not arrive in time. iCloud may still be syncing — try again."
                ),
                showsRetry: true
            )
        case .failed(let reason):
            return RestoreLookupPresentation(
                statusTitle: BackupL10n.tr("backup.restore.lookup.failed.status", fallback: "Search Failed"),
                statusIcon: "exclamationmark.icloud.fill",
                title: BackupL10n.tr("backup.restore.lookup.failed.title", fallback: "Could not check backups"),
                message: reason.userMessage,
                showsRetry: true
            )
        case .empty, .found:
            return RestoreLookupPresentation(
                statusTitle: isICloudAvailable
                    ? BackupL10n.tr("backup.restore.empty.status.not_found", fallback: "Backup Not Found")
                    : BackupL10n.tr("backup.restore.empty.title.icloud_unavailable", fallback: "iCloud is unavailable"),
                statusIcon: isICloudAvailable ? "exclamationmark.circle.fill" : "icloud.slash.fill",
                title: restoreEmptyStateTitle(isICloudAvailable: isICloudAvailable),
                message: restoreEmptyStateMessage(isICloudAvailable: isICloudAvailable),
                showsRetry: true
            )
        }
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
                fallback: "No saved backups were found in the private CloudKit container for the current iCloud account"
            )
        }
        return BackupL10n.tr(
            "backup.restore.empty.message.icloud_unavailable",
            fallback: "Without iCloud access, Millio cannot check backups or restore data"
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
                    ? BackupL10n.tr("backup.readiness.backup_enabled.detail.on", fallback: "Millio can create and refresh backups")
                    : BackupL10n.tr("backup.readiness.backup_enabled.detail.off", fallback: "Turn backup on"),
                isComplete: isBackupEnabled
            ),
            BackupReadinessItem(
                title: BackupL10n.tr("backup.readiness.icloud.title", fallback: "iCloud is available"),
                detail: isICloudAvailable
                    ? BackupL10n.tr("backup.readiness.icloud.detail.on", fallback: "Saving and restore are available now")
                    : BackupL10n.tr("backup.readiness.icloud.detail.off", fallback: "Check iCloud sign-in and Millio access"),
                isComplete: isICloudAvailable
            ),
            BackupReadinessItem(
                title: BackupL10n.tr("backup.readiness.protection.title", fallback: "Recovery method is chosen"),
                detail: encryptionMode == .passphrase
                    ? BackupL10n.tr("backup.readiness.protection.detail.passphrase", fallback: "Portable restore with your passphrase")
                    : BackupL10n.tr("backup.readiness.protection.detail.device", fallback: "Restore is tied to this iPhone"),
                isComplete: true
            ),
            BackupReadinessItem(
                title: BackupL10n.tr("backup.readiness.has_recent.title", fallback: "A backup exists"),
                detail: lastBackupDate != nil
                    ? BackupL10n.tr("backup.readiness.has_recent.detail.on", fallback: "You already have something to restore from")
                    : BackupL10n.tr("backup.readiness.has_recent.detail.off", fallback: "Create your first backup now"),
                isComplete: lastBackupDate != nil
            ),
            BackupReadinessItem(
                title: BackupL10n.tr("backup.readiness.has_pinned.title", fallback: "Manual version exists"),
                detail: hasPinnedVersions
                    ? BackupL10n.tr("backup.readiness.has_pinned.detail.on", fallback: "You saved a version that stays until you delete it")
                    : BackupL10n.tr("backup.readiness.has_pinned.detail.off", fallback: "Save one before a risky change or update"),
                isComplete: hasPinnedVersions
            )
        ]
    }

    private static func relativeBackupDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = AppLocalization.currentAppLocale
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
