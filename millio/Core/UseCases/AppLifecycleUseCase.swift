//
//  AppLifecycleUseCase.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import OSLog

@MainActor
protocol AppLifecycleUseCaseProtocol {
    func initialize() async
    func checkOnboardingStatus() -> Bool
    func checkRestoreNeeded() async -> Bool
}

@MainActor
final class AppLifecycleUseCase: AppLifecycleUseCaseProtocol {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "AppLifecycleUseCase")
    private let appState: AppState
    private let backupManager: BackupManagerProtocol
    private let onboardingKey = "hasCompletedOnboarding"
    
    init(appState: AppState, backupManager: BackupManagerProtocol) {
        self.appState = appState
        self.backupManager = backupManager
    }
    
    func initialize() async {
        let overallStart = DispatchTime.now()
        logger.info("Initializing app...")

        // Определяем следующий шаг
        let lifecycleStart = DispatchTime.now()
        if !checkOnboardingStatus() {
            appState.lifecycle = .onboarding
        } else {
            // Не показываем экран восстановления автоматически
            // Пользователь может перейти к нему из настроек
            appState.lifecycle = .ready
        }
        logger.info("Lifecycle decision finished in \(Double(DispatchTime.now().uptimeNanoseconds - lifecycleStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        
        logger.info("App initialized in \(Double(DispatchTime.now().uptimeNanoseconds - overallStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms, lifecycle: \(String(describing: self.appState.lifecycle))")
        
        // Проверяем iCloud только если backup включен (в фоне, не блокируя lifecycle)
        if appState.isBackupEnabled {
            let backupManager = self.backupManager
            Task.detached {
                let iCloudStart = DispatchTime.now()
                let result = await withTimeout(seconds: 3, operation: {
                    async let available = backupManager.isAvailable()
                    async let info = backupManager.lastBackupInfo()
                    return await (available, info)
                })
                
                let available = result?.0 ?? false
                let info = result?.1 ?? nil
                
                await MainActor.run {
                    self.appState.isICloudAvailable = available
                    self.appState.lastBackupDate = info?.date
                }
                
                self.logger.info("iCloud status refresh finished in \(Double(DispatchTime.now().uptimeNanoseconds - iCloudStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
            }
        } else {
            appState.isICloudAvailable = false
            appState.lastBackupDate = nil
        }
    }
    
    func checkOnboardingStatus() -> Bool {
        UserDefaults.standard.bool(forKey: onboardingKey)
    }
    
    func checkRestoreNeeded() async -> Bool {
        // Проверяем, есть ли backup в iCloud, но нет локальных данных
        // Это упрощённая логика, можно расширить
        let hasBackup = await self.backupManager.lastBackupInfo() != nil
        // В реальности нужно проверить наличие локальных данных
        return hasBackup
    }
    
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }
}
