//
//  millioApp.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct millioApp: App {
    @State private var appState = AppState()
    @State private var diContainer: DIContainer?
    @State private var lifecycleUseCase: AppLifecycleUseCase?
    
    var sharedModelContainer: ModelContainer? = {
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
            AppLogger.log(.error, category: "App", "Failed to create ModelContainer: \(error.localizedDescription)")
            // Fallback: создаем in-memory контейнер
            do {
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                AppLogger.log(.error, category: "App", "Failed to create fallback ModelContainer: \(error.localizedDescription)")
                // Последний fallback - пустая схема
                do {
                    return try ModelContainer(for: Schema([]), configurations: [])
                } catch {
                    return nil
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            if let container = sharedModelContainer {
                RootViewResolver(appState: appState)
                    .preferredColorScheme(.dark)
                    .environment(appState)
                    .environment(\.modelContainer, container)
                    .environment(\.diContainer, diContainer)
                    .environment(\.locale, appState.selectedLanguage.locale ?? Locale.current)
                    .task {
                        await initializeApp(container: container)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                        triggerBackgroundBackup()
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
        .modelContainer(sharedModelContainer ?? (try! ModelContainer(for: Schema([]), configurations: [])))
    }
    
    private func initializeApp(container: ModelContainer) async {
        // Используем DIContainer для создания зависимостей
        let container = DIContainer.create(
            appState: appState,
            modelContainer: container
        )
        self.diContainer = container
        
        // Создаем UseCase через DI Container
        let useCase = AppLifecycleUseCase(
            appState: appState,
            backupManager: container.backupManager
        )
        
        self.lifecycleUseCase = useCase
        await useCase.initialize()
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
}
