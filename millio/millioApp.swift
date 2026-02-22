//
//  millioApp.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData
import UIKit
import FirebaseCore
import OSLog

@main
struct millioApp: App {
    @UIApplicationDelegateAdaptor(FirebaseAppDelegate.self) private var firebaseDelegate
    @State private var appState = AppState()
    @State private var diContainer: DIContainer?
    @State private var lifecycleUseCase: AppLifecycleUseCase?
    @State private var isBiometricUnlockInProgress = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "App")
    
    var sharedModelContainer: ModelContainer? = {
        // Регистрируем фичи ДО создания схемы
        CurrencyFeatureRegistration.register()
        CardFeatureRegistration.register()
        CashbackFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        FinanceFeatureRegistration.register()
        CashflowFeatureRegistration.register()
        
        let schema = AppSchema.create()
        
        // Убеждаемся, что директория Application Support существует
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            do {
                try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                AppLogger.log(.error, category: "App", "Failed to create Application Support directory: \(error.localizedDescription)")
            }
        }
        
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            AppLogger.log(.error, category: "App", "Failed to create ModelContainer: \(error)")
            // Fallback: создаем in-memory контейнер
            do {
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                AppLogger.log(.error, category: "App", "Failed to create fallback ModelContainer: \(error)")
                // Последний fallback - пустая схема
                do {
                    return try ModelContainer(for: Schema([]), configurations: [])
                } catch {
                    AppLogger.log(.error, category: "App", "Failed to create empty schema ModelContainer: \(error)")
                    return nil
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            if let container = sharedModelContainer {
                ZStack {
                    RootViewResolver(appState: appState)
                        .zIndex(0)

                    if appState.isAppLocked && appState.lifecycle == .ready {
                        AppLockScreenView {
                            await unlockWithBiometricsIfEnabled()
                        }
                        .zIndex(1)
                    }
                }
                .preferredColorScheme(.dark)
                .environment(appState)
                .modelContainer(container)
                .environment(\.diContainer, diContainer)
                .environment(\.locale, appState.selectedLanguage.locale ?? Locale.current)
                .task {
                    await initializeApp(container: container)

                    // Восстанавливаем расписание уведомлений, если они включены
                    if appState.isDailyReminderEnabled {
                        await NotificationManager.shared.scheduleDailyReminder(enabled: true)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    triggerBackgroundBackup()
                    if appState.isAppLockEnabled {
                        appState.isAppLocked = true
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    Task { @MainActor in
                        // Обновляем статус подписки при возврате из фона
                        await SubscriptionManager.shared.checkSubscriptionStatus()
                        appState.subscriptionStatus = SubscriptionManager.shared.status
                        appState.subscriptionExpirationDate = SubscriptionManager.shared.expirationDate
                        appState.isTrialActive = SubscriptionManager.shared.isTrialActive

                        if appState.isAppLockEnabled {
                            appState.isAppLocked = true
                            _ = await unlockWithBiometricsIfEnabled()
                        }
                    }
                }
            } else {
                ErrorView(
                    error: .unknown(NSError(
                        domain: "App",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Не удалось инициализировать хранилище данных"]
                    )),
                    appState: appState,
                    router: AppRouter()
                )
                .preferredColorScheme(.dark)
                .environment(appState)
            }
        }
    }
    
    @MainActor
    private func initializeApp(container: ModelContainer) async {
        let start = DispatchTime.now()

        if appState.isAppLockEnabled && !AppLockPinStore.shared.hasPin() {
            appState.isAppLockEnabled = false
            appState.isBiometricUnlockEnabled = false
            appState.isAppLocked = false
        } else if appState.isAppLockEnabled {
            appState.isAppLocked = true
        }

        // Фичи уже зарегистрированы при создании ModelContainer
        
        // Используем DIContainer для создания зависимостей
        let diStart = DispatchTime.now()
        let container = DIContainer.create(
            appState: appState,
            modelContainer: container
        )
        self.diContainer = container
        logger.info("DIContainer.create finished in \(Double(DispatchTime.now().uptimeNanoseconds - diStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        
        // Создаем UseCase через DI Container
        let useCase = AppLifecycleUseCase(
            appState: appState,
            backupManager: container.backupManager
        )
        
        self.lifecycleUseCase = useCase
        let initStart = DispatchTime.now()
        await useCase.initialize()
        logger.info("AppLifecycleUseCase.initialize finished in \(Double(DispatchTime.now().uptimeNanoseconds - initStart.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        logger.info("initializeApp finished in \(Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000, privacy: .public) ms")
        
        Task { @MainActor in
            await SubscriptionManager.shared.checkSubscriptionStatus()
            appState.subscriptionStatus = SubscriptionManager.shared.status
            appState.subscriptionExpirationDate = SubscriptionManager.shared.expirationDate
            appState.isTrialActive = SubscriptionManager.shared.isTrialActive

            if appState.isAppLockEnabled {
                _ = await unlockWithBiometricsIfEnabled()
            }
        }
    }
    
    private func triggerBackgroundBackup() {
        // Backup только если включен в настройках и DIContainer доступен
        guard appState.isBackupEnabled,
              let diContainer = diContainer else { return }
        
        Task {
            do {
                try await diContainer.backupManager.backupNow()
            } catch {
                // Логируем, но не блокируем приложение
                AppLogger.log(.error, category: "App", "Background backup failed: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func unlockWithBiometricsIfEnabled() async -> Bool {
        guard appState.isAppLockEnabled, appState.isBiometricUnlockEnabled, !isBiometricUnlockInProgress else {
            return false
        }
        isBiometricUnlockInProgress = true
        defer { isBiometricUnlockInProgress = false }
        let success = await AppLockBiometricAuth.authenticate(reason: "Разблокируйте доступ к данным приложения")
        if success {
            appState.isAppLocked = false
        }
        return success
    }
}
