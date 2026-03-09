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

        #expect(content.title == "Почти готово")
        #expect(content.storageTitle == "Хранение в iCloud")
        #expect(content.trustTitle == "Защита: кодовая фраза")
        #expect(content.trustDetail.contains("Millio ее не хранит"))
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
        #expect(content.subtitle == "Данные остаются на устройстве.")
        #expect(content.storageTitle == "Только на устройстве")
        #expect(content.readiness.first?.isComplete == false)
    }

    @Test("Restore empty state changes reason depending on iCloud availability")
    func testRestoreEmptyStateCopy() {
        #expect(BackupExperiencePresenter.restoreEmptyStateTitle(isICloudAvailable: true) == "Резервная копия не найдена")
        #expect(BackupExperiencePresenter.restoreEmptyStateTitle(isICloudAvailable: false) == "iCloud сейчас недоступен")
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
        #expect(content.storageTitle == "Хранение недоступно")
    }
}
