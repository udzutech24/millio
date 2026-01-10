//
//  RestoreView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct RestoreView: View {
    @Bindable var appState: AppState
    @Bindable var router: AppRouter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.modelContainer) private var modelContainer
    @State private var isRestoring = false
    @State private var restoreError: AppError?
    
    private var backupManager: BackupManagerProtocol? {
        guard let modelContainer = modelContainer else { return nil }
        let dataRepository = DataRepository(modelContext: modelContext, modelContainer: modelContainer)
        return BackupManager(dataRepository: dataRepository)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            if !appState.isBackupEnabled {
                Text("Резервное копирование отключено")
                    .font(.title2)
                    .bold()
                
                Text("Включите резервное копирование в настройках для восстановления данных")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                Button("Перейти в настройки") {
                    appState.lifecycle = .ready
                }
                .buttonStyle(.borderedProminent)
            } else if isRestoring {
                ProgressView()
                Text("restoring")
                    .foregroundStyle(.secondary)
            } else {
                if let backupDate = appState.lastBackupDate {
                    Text("Найдена резервная копия")
                        .font(.title2)
                        .bold()
                    
                    Text("Дата: \(backupDate.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                    
                    Button("restore") {
                        restore()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("Резервная копия не найдена")
                        .font(.title2)
                    
                    Button("Продолжить без восстановления") {
                        appState.lifecycle = .ready
                    }
                    .buttonStyle(.bordered)
                }
                
                if let error = restoreError {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .padding()
    }
    
    private func restore() {
        guard let backupManager = backupManager else {
            restoreError = .iCloudUnavailable
            return
        }
        
        isRestoring = true
        restoreError = nil
        
        Task {
            do {
                try await backupManager.restoreLatest()
                await MainActor.run {
                    isRestoring = false
                    appState.lifecycle = .ready
                }
            } catch let error as AppError {
                await MainActor.run {
                    isRestoring = false
                    restoreError = error
                    appState.lifecycle = .error(error)
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    restoreError = .unknown(error)
                    appState.lifecycle = .error(.unknown(error))
                }
            }
        }
    }
}

#Preview("With backup") {
    let appState = AppState()
    appState.lastBackupDate = Date()
    return RestoreView(
        appState: appState,
        router: AppRouter()
    )
}

#Preview("No backup") {
    RestoreView(
        appState: AppState(),
        router: AppRouter()
    )
}
