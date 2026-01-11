//
//  AppLifecycleUseCase.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import OSLog

protocol AppLifecycleUseCaseProtocol {
    func initialize() async
    func checkOnboardingStatus() -> Bool
    func checkRestoreNeeded() async -> Bool
}

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
        logger.info("Initializing app...")
        
        // Проверяем iCloud только если backup включен
        if appState.isBackupEnabled {
            appState.isICloudAvailable = await withTimeout(seconds: 3, operation: {
                await self.backupManager.isAvailable()
            }) ?? false
            
            // Получаем информацию о последнем backup с таймаутом
            let backupInfoResult = await withTimeout(seconds: 3, operation: {
                await self.backupManager.lastBackupInfo()
            })
            if let backupInfoOptional = backupInfoResult, let backupInfo = backupInfoOptional {
                appState.lastBackupDate = backupInfo.date
            }
        } else {
            appState.isICloudAvailable = false
            appState.lastBackupDate = nil
        }
        
        // Определяем следующий шаг
        if !checkOnboardingStatus() {
            appState.lifecycle = .onboarding
        } else {
            // Не показываем экран восстановления автоматически
            // Пользователь может перейти к нему из настроек
            appState.lifecycle = .ready
        }
        
        logger.info("App initialized, lifecycle: \(String(describing: self.appState.lifecycle))")
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            
            var result: T? = nil
            for await value in group {
                if let value = value {
                    result = value
                    break
                }
            }
            group.cancelAll()
            return result
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
