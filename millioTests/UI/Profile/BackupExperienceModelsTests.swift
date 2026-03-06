import Foundation
import Testing
@testable import millio

struct BackupExperienceModelsTests {
    @Test("Dashboard copy explains CloudKit storage and passphrase trust model")
    func testDashboardCopyForPortableMode() {
        let content = BackupExperiencePresenter.dashboard(
            isBackupEnabled: true,
            isICloudAvailable: true,
            lastBackupDate: nil,
            encryptionMode: .passphrase,
            hasPinnedVersions: false
        )

        #expect(content.storageTitle == "Хранение: приватная база iCloud")
        #expect(content.trustTitle == "Защита: кодовая фраза")
        #expect(content.trustDetail.contains("не хранит вашу кодовую фразу"))
        #expect(content.readiness.contains(where: { $0.title == "Есть актуальная копия" && $0.isComplete == false }))
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

        #expect(content.title == "Резервное копирование выключено")
        #expect(content.storageTitle == "Хранение: только на устройстве")
        #expect(content.readiness.first?.isComplete == false)
    }

    @Test("Restore empty state changes reason depending on iCloud availability")
    func testRestoreEmptyStateCopy() {
        #expect(BackupExperiencePresenter.restoreEmptyStateTitle(isICloudAvailable: true) == "Резервная копия не найдена")
        #expect(BackupExperiencePresenter.restoreEmptyStateTitle(isICloudAvailable: false) == "iCloud сейчас недоступен")
    }
}
