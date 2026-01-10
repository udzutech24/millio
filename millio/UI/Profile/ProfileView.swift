//
//  ProfileView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct ProfileView: View {
    @Bindable var router: AppRouter
    @Environment(AppState.self) private var appState
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Profile header
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.white.opacity(0.8))
                        
                        Text("Профиль")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 40)
                    
                    // Settings section
                    VStack(spacing: 16) {
                        Section {
                            Toggle("Резервное копирование", isOn: Binding(
                                get: { appState.isBackupEnabled },
                                set: { newValue in
                                    appState.isBackupEnabled = newValue
                                    SettingsManager.shared.isBackupEnabled = newValue
                                    
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
                            .tint(.blue)
                            
                            if appState.isBackupEnabled {
                                if let backupDate = appState.lastBackupDate {
                                    HStack {
                                        Text("Последний backup")
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text(backupDate.formatted(date: .abbreviated, time: .shortened))
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                } else {
                                    HStack {
                                        Text("Статус")
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text(appState.isICloudAvailable ? "iCloud доступен" : "iCloud недоступен")
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                }
                            }
                        } header: {
                            Text("Настройки")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Профиль")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ProfileView(router: AppRouter())
            .environment(AppState())
    }
}
