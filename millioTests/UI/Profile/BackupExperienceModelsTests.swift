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

        #expect(content.title == BackupL10n.tr("backup.dashboard.title.almost", fallback: "Almost done"))
        #expect(content.storageTitle == BackupL10n.tr("backup.dashboard.storage.title.icloud", fallback: "Stored in iCloud"))
        #expect(content.trustTitle == BackupL10n.tr("backup.dashboard.trust.title.passphrase", fallback: "Protection: passphrase"))
        #expect(content.trustDetail.contains("Millio"))
        #expect(content.readiness.contains(where: { $0.title == BackupL10n.tr("backup.readiness.has_recent.title", fallback: "Recent backup exists") && $0.isComplete == false }))
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

        #expect(content.title == BackupL10n.tr("backup.dashboard.title.off", fallback: "Backup is off"))
        #expect(content.subtitle == BackupL10n.tr("backup.dashboard.subtitle.off", fallback: "Data stays on this device."))
        #expect(content.storageTitle == BackupL10n.tr("backup.dashboard.storage.title.local", fallback: "On-device only"))
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
        #expect(content.title.count <= 24)
        #expect(content.subtitle.contains("iCloud"))
        #expect(content.storageTitle == BackupL10n.tr("backup.dashboard.storage.title.unavailable", fallback: "Storage unavailable"))
    }
}
