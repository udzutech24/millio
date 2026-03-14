import Foundation
import Testing
@testable import millio

struct BackupExperienceModelsTests {
    @Test("Dashboard copy stays concise for iCloud and passphrase mode")
    func testDashboardCopyForPortableMode() {
        let content = BackupExperiencePresenter.dashboard(
            isBackupEnabled: true,
            isICloudAvailable: true,
            lastBackupDate: nil,
            encryptionMode: .passphrase,
            hasPinnedVersions: false
        )

        #expect(content.title == BackupL10n.tr("backup.dashboard.title.almost", fallback: "Create your first backup"))
        #expect(content.storageTitle == BackupL10n.tr("backup.dashboard.storage.title.icloud", fallback: "Saved in iCloud"))
        #expect(content.trustTitle == BackupL10n.tr("backup.dashboard.trust.title.passphrase", fallback: "Protection: passphrase"))
        #expect(content.trustDetail.isEmpty == false)
        #expect(content.readiness.contains(where: { $0.title == BackupL10n.tr("backup.readiness.has_recent.title", fallback: "A backup exists") && $0.isComplete == false }))
    }

    @Test("Dashboard copy explains local-only state when backup is disabled")
    func testDashboardCopyWhenBackupDisabled() {
        let content = BackupExperiencePresenter.dashboard(
            isBackupEnabled: false,
            isICloudAvailable: false,
            lastBackupDate: nil,
            encryptionMode: .deviceKey,
            hasPinnedVersions: false
        )

        #expect(content.title == BackupL10n.tr("backup.dashboard.title.off", fallback: "Your data is only local"))
        #expect(content.subtitle == BackupL10n.tr("backup.dashboard.subtitle.off", fallback: "Turn on backup to keep a recovery copy in iCloud"))
        #expect(content.storageTitle == BackupL10n.tr("backup.dashboard.storage.title.local", fallback: "Only on this device"))
        #expect(content.readiness.first?.isComplete == false)
    }

    @Test("Restore empty state changes reason depending on iCloud availability")
    func testRestoreEmptyStateCopy() {
        #expect(BackupExperiencePresenter.restoreEmptyStateTitle(isICloudAvailable: true) == BackupL10n.tr("backup.restore.empty.title.not_found", fallback: "Backup not found"))
        #expect(BackupExperiencePresenter.restoreEmptyStateTitle(isICloudAvailable: false) == BackupL10n.tr("backup.restore.empty.title.icloud_unavailable", fallback: "iCloud is unavailable"))
    }

    @Test("Dashboard keeps compact checklist and short action-oriented copy")
    func testDashboardCompactContract() {
        let content = BackupExperiencePresenter.dashboard(
            isBackupEnabled: true,
            isICloudAvailable: false,
            lastBackupDate: nil,
            encryptionMode: .deviceKey,
            hasPinnedVersions: false
        )

        #expect(content.readiness.count == 5)
        #expect(content.title.count <= 28)
        #expect(content.subtitle.contains("iCloud"))
        #expect(content.storageTitle == BackupL10n.tr("backup.dashboard.storage.title.unavailable", fallback: "iCloud unavailable"))
    }

    @Test("Management refresh does not skip when screen state lost loaded versions")
    func testManagementRefreshRequiresLoadedVersions() {
        #expect(
            BackupStatusRefreshPolicy.shouldSkipManagementRefresh(
                force: false,
                isBackupEnabled: true,
                isICloudAvailable: true,
                lastBackupDate: Date(),
                loadedVersionCount: 0
            ) == false
        )
    }

    @Test("Management refresh skips only when backup screen already has loaded versions")
    func testManagementRefreshSkipsWithWarmState() {
        #expect(
            BackupStatusRefreshPolicy.shouldSkipManagementRefresh(
                force: false,
                isBackupEnabled: true,
                isICloudAvailable: true,
                lastBackupDate: Date(),
                loadedVersionCount: 2
            ) == true
        )
    }

    @Test("Backup layout stacks metric tiles on narrow screens")
    func testBackupLayoutStacksMetricsOnNarrowScreens() {
        #expect(BackupManagementLayout.shouldStackMetrics(availableWidth: 359) == true)
        #expect(BackupManagementLayout.shouldStackMetrics(availableWidth: 360) == false)
    }

    @Test("Backup layout stacks compact actions before content can overflow")
    func testBackupLayoutStacksActionsOnCompactWidths() {
        #expect(BackupManagementLayout.shouldStackActionButtons(availableWidth: 389) == true)
        #expect(BackupManagementLayout.shouldStackActionButtons(availableWidth: 390) == false)
    }
}
