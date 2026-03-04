import Foundation
import Testing
@testable import millio

struct RestoreCandidateTelemetryTests {
    @Test("Restore candidate skip reason maps AppError consistently")
    func testSkipReasonMapping() {
        #expect(RestoreCandidateReason.skipReason(for: .backupCorrupted) == .backupCorrupted)
        #expect(RestoreCandidateReason.skipReason(for: .incompatibleSchemaVersion) == .incompatibleSchema)
        #expect(RestoreCandidateReason.skipReason(for: .networkUnavailable) == .runtimeSkip)
    }

    @Test("Restore candidate block reason maps restoreFailed messages to stable codes")
    func testBlockReasonMappingForRestoreFailedMessages() {
        #expect(
            RestoreCandidateReason.blockReason(
                for: .restoreFailed("Backup зашифрован парольной фразой. Введите парольную фразу и повторите.")
            ) == .passphraseRequired
        )
        #expect(
            RestoreCandidateReason.blockReason(
                for: .restoreFailed("Backup зашифрован и не может быть расшифрован на этом устройстве")
            ) == .keychainUnavailable
        )
        #expect(RestoreCandidateReason.blockReason(for: .restoreFailed("Some other restore failure")) == .restoreFailed)
    }

    @Test("Restore candidate block reason maps non-restore errors to stable codes")
    func testBlockReasonMappingForOtherErrors() {
        #expect(RestoreCandidateReason.blockReason(for: .iCloudUnavailable) == .iCloudUnavailable)
        #expect(RestoreCandidateReason.blockReason(for: .networkUnavailable) == .networkUnavailable)
        #expect(RestoreCandidateReason.blockReason(for: .backupFailed("transport")) == .backupTransportFailed)
        #expect(
            RestoreCandidateReason.blockReason(
                for: .unknown(NSError(domain: "test", code: 1))
            ) == .unknownError
        )
    }
}
