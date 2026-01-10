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
    
    init(
        appState: AppState,
        modelContainer: ModelContainer,
        dataRepository: DataRepositoryProtocol,
        backupManager: BackupManagerProtocol
    ) {
        self.appState = appState
        self.modelContainer = modelContainer
        self.dataRepository = dataRepository
        self.backupManager = backupManager
    }
    
    static func create(
        appState: AppState,
        modelContainer: ModelContainer
    ) -> DIContainer {
        let modelContext = modelContainer.mainContext
        let dataRepository = DataRepository(
            modelContext: modelContext,
            modelContainer: modelContainer
        )
        
        let backupManager: BackupManagerProtocol = appState.isBackupEnabled
            ? BackupManager(dataRepository: dataRepository)
            : MockBackupManager()
        
        return DIContainer(
            appState: appState,
            modelContainer: modelContainer,
            dataRepository: dataRepository,
            backupManager: backupManager
        )
    }
}
