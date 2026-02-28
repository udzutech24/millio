import Foundation
import Testing
@testable import millio

@MainActor
struct BackupMonitorTests {
    @Test("BackupMonitor sets lastBackupError when iCloud is unavailable")
    func testBackupMonitorICloudUnavailable() async {
        let monitor = BackupMonitor(backupManager: MockBackupManager())
        
        await monitor.updateStatus()
        
        #expect(monitor.lastBackupError == .iCloudUnavailable)
        #expect(monitor.isBackupInProgress == false)
        #expect(monitor.lastBackupDate == nil)
        #expect(monitor.backupSize == nil)
    }
}

