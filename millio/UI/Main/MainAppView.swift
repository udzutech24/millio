//
//  MainAppView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct MainAppView: View {
    @Bindable var router: AppRouter
    @Environment(AppState.self) private var appState
    
    var body: some View {
        NavigationStack(path: $router.navigationPath) {
            List {
                Section {
                    Toggle("Резервное копирование", isOn: Binding(
                        get: { appState.isBackupEnabled },
                        set: { newValue in
                            appState.isBackupEnabled = newValue
                            SettingsManager.shared.isBackupEnabled = newValue
                            
                            // Если backup включен, проверяем iCloud
                            if newValue {
                                Task {
                                    // Можно добавить проверку iCloud здесь
                                }
                            } else {
                                appState.isICloudAvailable = false
                                appState.lastBackupDate = nil
                            }
                        }
                    ))
                    
                    if appState.isBackupEnabled {
                        if let backupDate = appState.lastBackupDate {
                            HStack {
                                Text("Последний backup")
                                Spacer()
                                Text(backupDate.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            HStack {
                                Text("Статус")
                                Spacer()
                                Text(appState.isICloudAvailable ? "iCloud доступен" : "iCloud недоступен")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Настройки")
                }
                
                Section {
                    Text("Главный экран")
                        .font(.title2)
                        .padding(.vertical, 8)
                    
                    Text("Ядро приложения готово к работе")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Millio")
        }
    }
}

#Preview {
    MainAppView(router: AppRouter())
        .environment(AppState())
}
