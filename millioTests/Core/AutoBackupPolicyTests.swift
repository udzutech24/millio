import Foundation
import Testing
@testable import millio

struct AutoBackupPolicyTests {
    @Test("Auto backup runs when no previous backup exists")
    func testShouldRunWithoutPreviousBackup() {
        let policy = AutoBackupPolicy.everyThreeDays
        #expect(policy.shouldRun(lastBackupDate: nil, now: Date(timeIntervalSince1970: 10)) == true)
    }

    @Test("Auto backup waits full three-day interval")
    func testShouldWaitThreeDaysBetweenRuns() {
        let policy = AutoBackupPolicy.everyThreeDays
        let lastBackupDate = Date(timeIntervalSince1970: 0)

        #expect(policy.shouldRun(lastBackupDate: lastBackupDate, now: Date(timeIntervalSince1970: 3 * 24 * 60 * 60 - 1)) == false)
        #expect(policy.shouldRun(lastBackupDate: lastBackupDate, now: Date(timeIntervalSince1970: 3 * 24 * 60 * 60)) == true)
    }
}
