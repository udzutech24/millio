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
    private static let defaultMinimumLaunchDurationSeconds: TimeInterval = 2.2
    private let appState: AppState
    private let backupManager: BackupManagerProtocol
    private let splashPreferences: LaunchSplashPreferences
    private let calendar: Calendar
    private let nowProvider: () -> Date
    private let onboardingKey = "hasCompletedOnboarding"
    private let minimumLaunchDurationNanoseconds: UInt64
    
    init(
        appState: AppState,
        backupManager: BackupManagerProtocol,
        splashPreferences: LaunchSplashPreferences = SettingsManager.shared,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init,
        minimumLaunchDuration: TimeInterval? = nil
    ) {
        self.appState = appState
        self.backupManager = backupManager
        self.splashPreferences = splashPreferences
        self.calendar = calendar
        self.nowProvider = nowProvider
        let isRunningTests = AppRuntimeEnvironment.current().isAnyTesting
        let resolvedDuration = minimumLaunchDuration ?? (isRunningTests ? 0 : Self.defaultMinimumLaunchDurationSeconds)
        self.minimumLaunchDurationNanoseconds = UInt64(max(0, resolvedDuration) * 1_000_000_000)
    }
    
    func initialize() async {
        let overallStart = DispatchTime.now()
        logger.info("Initializing app...")

        // Определяем следующий шаг, но применяем его только после минимальной выдержки splash.
        let lifecycleStart = DispatchTime.now()
        let nextLifecycle: AppLifecycleState
        let hasCompletedOnboarding = checkOnboardingStatus()
        let lastSeenVersion = SettingsManager.shared.lastSeenAppVersion
        SettingsManager.shared.applyQuickSetupBannerSuppressionIfNeeded(
            hasCompletedOnboarding: hasCompletedOnboarding,
            lastSeenVersion: lastSeenVersion
        )
        SettingsManager.shared.lastSeenAppVersion = currentAppVersionString()
        if !hasCompletedOnboarding {
            nextLifecycle = .onboarding
        } else {
            // Не показываем экран восстановления автоматически
            // Пользователь может перейти к нему из настроек
            nextLifecycle = .ready
        }
        let now = nowProvider()
        if shouldShowLaunchSplash(now: now) {
            await enforceMinimumLaunchDuration(since: overallStart)
            splashPreferences.lastLaunchSplashShownAt = now
        }
        appState.lifecycle = nextLifecycle

        logger.info(
            "Lifecycle decision finished in \(Double(DispatchTime.now().uptimeNanoseconds - lifecycleStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms"
        )
        
        logger.info(
            "App initialized in \(Double(DispatchTime.now().uptimeNanoseconds - overallStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms, lifecycle: \(String(describing: self.appState.lifecycle))"
        )
        
        // Проверяем iCloud всегда: после reinstall toggle в UserDefaults мог сброситься,
        // но recovery данные в CloudKit все еще существуют и должны быть обнаружены.
        let backupManager = self.backupManager
        Task.detached {
            let iCloudStart = DispatchTime.now()
            let result = await withTimeout(seconds: 5, operation: {
                let available = await backupManager.isAvailable()
                let info = available ? await backupManager.lastBackupInfo() : nil
                return (available, info)
            })

            let available = result?.0 ?? false
            let info = result?.1 ?? nil

            await MainActor.run {
                self.appState.isICloudAvailable = available
                self.appState.lastBackupDate = info?.date
            }

            self.logger.info("iCloud status refresh finished in \(Double(DispatchTime.now().uptimeNanoseconds - iCloudStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        }
    }

    private func enforceMinimumLaunchDuration(since start: DispatchTime) async {
        guard minimumLaunchDurationNanoseconds > 0 else { return }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        guard elapsedNanoseconds < minimumLaunchDurationNanoseconds else { return }

        let remaining = minimumLaunchDurationNanoseconds - elapsedNanoseconds
        do {
            try await Task.sleep(nanoseconds: remaining)
        } catch {
            logger.error("Minimum launch delay interrupted: \(error.localizedDescription)")
        }
    }

    private func shouldShowLaunchSplash(now: Date) -> Bool {
        switch splashPreferences.launchSplashDisplayMode {
        case .always:
            return true
        case .disabled:
            return false
        case .oncePerDay:
            guard let lastShownAt = splashPreferences.lastLaunchSplashShownAt else { return true }
            return !calendar.isDate(lastShownAt, inSameDayAs: now)
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

    private func currentAppVersionString() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        if version == build {
            return version
        }
        return "\(version) (\(build))"
    }
}
