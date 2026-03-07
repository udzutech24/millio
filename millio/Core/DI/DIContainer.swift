//
//  DIContainer.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Dependency Injection Container для ядра приложения
final class DIContainer {
    let appState: AppState
    let modelContainer: ModelContainer
    let dataRepository: DataRepositoryProtocol
    let backupManager: BackupManagerProtocol
    let authService: any AuthServiceProtocol
    
    init(
        appState: AppState,
        modelContainer: ModelContainer,
        dataRepository: DataRepositoryProtocol,
        backupManager: BackupManagerProtocol,
        authService: any AuthServiceProtocol
    ) {
        self.appState = appState
        self.modelContainer = modelContainer
        self.dataRepository = dataRepository
        self.backupManager = backupManager
        self.authService = authService
    }
    
    @MainActor
    static func create(
        appState: AppState,
        modelContainer: ModelContainer
    ) -> DIContainer {
        let modelContext = modelContainer.mainContext
        do {
            try DataIntegrityCleaner.runIfNeeded(modelContext: modelContext)
        } catch {
            AppLogger.log(.error, category: "Integrity", "Data integrity cleanup failed: \(error.localizedDescription)")
        }
        let dataRepository = DataRepository(
            modelContext: modelContext,
            modelContainer: modelContainer
        )
        
        let enabledBackupManager: BackupManagerProtocol = BackupManager(dataRepository: dataRepository)
        let disabledBackupManager: BackupManagerProtocol = MockBackupManager()
        let backupManager: BackupManagerProtocol = SwitchingBackupManager(
            appState: appState,
            enabled: enabledBackupManager,
            disabled: disabledBackupManager
        )
        let authService: any AuthServiceProtocol
        do {
            let authConfiguration = try AuthConfiguration.live()
            authService = AuthService(apiClient: AuthAPIClient(configuration: authConfiguration))
        } catch {
            AppLogger.log(.error, category: "Auth", "Failed to initialize auth service: \(error.localizedDescription)")
            authService = UnconfiguredAuthService()
        }
        
        return DIContainer(
            appState: appState,
            modelContainer: modelContainer,
            dataRepository: dataRepository,
            backupManager: backupManager,
            authService: authService
        )
    }
}
