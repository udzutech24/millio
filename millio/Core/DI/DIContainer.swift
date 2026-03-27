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
    let apiClientFactory: APIClientFactory
    
    init(
        appState: AppState,
        modelContainer: ModelContainer,
        dataRepository: DataRepositoryProtocol,
        backupManager: BackupManagerProtocol,
        authService: any AuthServiceProtocol,
        apiClientFactory: APIClientFactory
    ) {
        self.appState = appState
        self.modelContainer = modelContainer
        self.dataRepository = dataRepository
        self.backupManager = backupManager
        self.authService = authService
        self.apiClientFactory = apiClientFactory
    }
    
    @MainActor
    static func create(
        appState: AppState,
        modelContainer: ModelContainer,
        backendRuntime: BackendSessionRuntime
    ) -> DIContainer {
        let runtimeEnvironment = AppRuntimeEnvironment.current()
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
        
        let disabledBackupManager: BackupManagerProtocol = MockBackupManager()
        let backupManager: BackupManagerProtocol
        if runtimeEnvironment.isAnyTesting {
            backupManager = disabledBackupManager
        } else {
            let enabledBackupManager: BackupManagerProtocol = BackupManager(dataRepository: dataRepository)
            backupManager = SwitchingBackupManager(
                appState: appState,
                enabled: enabledBackupManager,
                disabled: disabledBackupManager
            )
        }
        let apiClientFactory = APIClientFactory(runtime: backendRuntime)
        let authService: any AuthServiceProtocol = apiClientFactory.makeAuthService()
        
        return DIContainer(
            appState: appState,
            modelContainer: modelContainer,
            dataRepository: dataRepository,
            backupManager: backupManager,
            authService: authService,
            apiClientFactory: apiClientFactory
        )
    }
}
