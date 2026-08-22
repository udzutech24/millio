//
//  MockBackupManager.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

/// Mock BackupManager для случаев, когда backup отключен
final class MockBackupManager: BackupManagerProtocol {
    func isAvailable() async -> Bool {
        false
    }
    
    func backupNow() async throws {
        // Ничего не делаем, backup отключен
    }

    func backupNow(passphrase: String?) async throws {
        // Ничего не делаем, backup отключен
    }

    func saveVersionNow(passphrase: String?) async throws {
        // Ничего не делаем, backup отключен
    }

    func exportVersion(recordName: String) async throws -> BackupTransferPayload {
        throw AppError.iCloudUnavailable
    }

    func importVersion(from data: Data) async throws -> BackupVersionInfo {
        throw AppError.iCloudUnavailable
    }
    
    func restoreLatest() async throws {
        // Ничего не делаем, backup отключен
    }

    func restoreLatest(passphrase: String?) async throws {
        // Ничего не делаем, backup отключен
    }

    func restoreVersion(recordName: String, passphrase: String?) async throws {
        // Ничего не делаем, backup отключен
    }

    func restoreVersionVerified(
        recordName: String,
        passphrase: String?,
        progress: RecoveryProgressSink?
    ) async throws -> RecoveryReceipt {
        throw AppError.iCloudUnavailable
    }

    func listBackupVersions() async -> [BackupVersionInfo] {
        []
    }

    func deleteBackupVersion(recordName: String) async throws {
        // Ничего не делаем, backup отключен
    }
    
    func lastBackupInfo() async -> BackupInfo? {
        nil
    }
}
