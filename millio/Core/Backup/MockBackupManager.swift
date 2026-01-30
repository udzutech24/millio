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
    
    func restoreLatest() async throws {
        // Ничего не делаем, backup отключен
    }

    func restoreLatest(passphrase: String?) async throws {
        // Ничего не делаем, backup отключен
    }
    
    func lastBackupInfo() async -> BackupInfo? {
        nil
    }
}
