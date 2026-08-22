import Foundation

enum RecoveryStage: String, CaseIterable, Sendable {
    case searching
    case downloading
    case validating
    case importing
    case verifying
    case finishing

    var progress: Double {
        switch self {
        case .searching: 0.08
        case .downloading: 0.24
        case .validating: 0.42
        case .importing: 0.64
        case .verifying: 0.84
        case .finishing: 1
        }
    }
}

struct RecoveryScopeToken: Equatable, Sendable {
    enum Kind: String, Sendable {
        case authenticated
        case guest
    }

    let kind: Kind
    let generation: UInt
}

struct RecoveryReceipt: Equatable, Sendable {
    let id: UUID
    let backupDate: Date?
    let expectedModelCount: Int
    let localModelCountBefore: Int
    let importedModelCount: Int
    let localModelCountAfter: Int
    let duration: TimeInterval

    var isVerified: Bool {
        importedModelCount == expectedModelCount && localModelCountAfter >= importedModelCount
    }
}

enum RecoveryFailure: Error, Equatable, Sendable {
    case invalidScope
    case scopeChanged
    case localCountUnavailable
    case localDataPresent(count: Int)
    case noBackup
    case timedOut(stage: RecoveryStage)
    case verificationMismatch(expected: Int, actual: Int)
    case rollbackFailed
    case cancelled
    case underlying(message: String)
}

enum RecoveryCoordinatorState: Equatable, Sendable {
    case idle
    case searching
    case awaitingConfirmation(BackupVersionInfo)
    case running(RecoveryStage)
    case succeeded(RecoveryReceipt)
    case failed(RecoveryFailure)
    case cancelled
}

typealias RecoveryProgressSink = @Sendable (RecoveryStage) async -> Void

struct BackupManagerSendableBox: @unchecked Sendable {
    let value: BackupManagerProtocol
}
