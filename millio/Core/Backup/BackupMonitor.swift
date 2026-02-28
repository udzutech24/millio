//
//  BackupMonitor.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import Combine

/// Мониторинг состояния backup
@MainActor
protocol BackupMonitorProtocol: ObservableObject {
    var lastBackupDate: Date? { get }
    var backupSize: Int64? { get }
    var isBackupInProgress: Bool { get }
    var lastBackupError: AppError? { get }
    
    func updateStatus() async
}

@MainActor
final class BackupMonitor: BackupMonitorProtocol {
    @Published var lastBackupDate: Date?
    @Published var backupSize: Int64?
    @Published var isBackupInProgress: Bool = false
    @Published var lastBackupError: AppError?
    
    private let backupManager: BackupManagerProtocol
    
    init(backupManager: BackupManagerProtocol) {
        self.backupManager = backupManager
    }
    
    func updateStatus() async {
        isBackupInProgress = true
        defer { isBackupInProgress = false }
        
        if !(await backupManager.isAvailable()) {
            lastBackupDate = nil
            backupSize = nil
            lastBackupError = .iCloudUnavailable
            return
        }
        
        if let info = await backupManager.lastBackupInfo() {
            lastBackupDate = info.date
            backupSize = info.size
            lastBackupError = nil
        } else {
            lastBackupDate = nil
            backupSize = nil
            lastBackupError = nil
        }
    }
}
