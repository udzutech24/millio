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
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Profile header
                    VStack(spacing: 12) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(AppColors.textSecondary)
                        
                        Text("Профиль")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .padding(.top, 40)
                    
                    // Settings section
                    VStack(spacing: 24) {
                        // Backup settings
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
                                                .foregroundStyle(AppColors.textPrimary)
                                            Spacer()
                                            Text(backupDate.formatted(date: .abbreviated, time: .shortened))
                                                .foregroundStyle(AppColors.textTertiary)
                                        }
                                    } else {
                                        HStack {
                                            Text("Статус")
                                                .foregroundStyle(AppColors.textPrimary)
                                            Spacer()
                                            Text(appState.isICloudAvailable ? "iCloud доступен" : "iCloud недоступен")
                                                .foregroundStyle(AppColors.textTertiary)
                                        }
                                    }
                                }
                            } header: {
                                Text("Настройки")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
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
                        
                        // Language selection
                        VStack(spacing: 16) {
                            Section {
                                NavigationLink {
                                    LanguageSelectionView(selectedLanguage: Binding(
                                        get: { appState.selectedLanguage },
                                        set: { appState.selectedLanguage = $0 }
                                    ))
                                } label: {
                                    HStack {
                                        Text("Язык")
                                            .foregroundStyle(AppColors.textPrimary)
                                        Spacer()
                                        Text(appState.selectedLanguage.displayName)
                                            .foregroundStyle(AppColors.textTertiary)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(AppColors.textTertiary)
                                    }
                                }
                            } header: {
                                Text("Язык и регион")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
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
                        
                        // App info
                        VStack(spacing: 16) {
                            Section {
                                HStack {
                                    Text("Версия")
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    Text(appVersion)
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            } header: {
                                Text("О приложении")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.textSecondary)
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
