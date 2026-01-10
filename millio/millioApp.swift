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
    @State private var lifecycleUseCase: AppLifecycleUseCase?
    @State private var backupManager: BackupManager?
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootViewResolver(appState: appState)
                .preferredColorScheme(.dark)
                .environment(appState)
                .environment(\.modelContainer, sharedModelContainer)
                .task {
                    await initializeApp()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                    triggerBackgroundBackup()
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func initializeApp() async {
        let modelContext = sharedModelContainer.mainContext
        let dataRepository = DataRepository(modelContext: modelContext, modelContainer: sharedModelContainer)
        
        // Создаём BackupManager только если backup включен
        let manager: BackupManagerProtocol?
        if appState.isBackupEnabled {
            manager = BackupManager(dataRepository: dataRepository)
            self.backupManager = manager as? BackupManager
        } else {
            manager = nil
            self.backupManager = nil
        }
        
        // Используем mock или nil для BackupManager, если backup отключен
        let useCase = AppLifecycleUseCase(
            appState: appState,
            backupManager: manager ?? MockBackupManager()
        )
        
        self.lifecycleUseCase = useCase
        await useCase.initialize()
    }
    
    private func triggerBackgroundBackup() {
        // Backup только если включен в настройках
        guard appState.isBackupEnabled,
              let backupManager = backupManager else { return }
        
        Task {
            do {
                try await backupManager.backupNow()
            } catch {
                // Логируем, но не блокируем приложение
                AppLogger.log(.error, category: "App", "Background backup failed: \(error.localizedDescription)")
            }
        }
    }
}
