//
//  ProfileView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Bindable var router: AppRouter
    @Environment(AppState.self) private var appState
    @Environment(\.modelContainer) private var modelContainer
    @Environment(\.modelContext) private var modelContext
    
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
                        // Subscription status
                        subscriptionStatusSection
                        
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
                                                // Проверяем доступность iCloud при включении тоггла
                                                let cloudStore = CloudBackupStore()
                                                appState.isICloudAvailable = await cloudStore.isAvailable()
                                                
                                                // Если iCloud доступен, получаем информацию о последнем backup
                                                if appState.isICloudAvailable, let container = modelContainer {
                                                    let dataRepository = DataRepository(
                                                        modelContext: modelContext,
                                                        modelContainer: container
                                                    )
                                                    let backupManager = BackupManager(dataRepository: dataRepository)
                                                    if let backupInfo = await backupManager.lastBackupInfo() {
                                                        appState.lastBackupDate = backupInfo.date
                                                    }
                                                }
                                            }
                                        } else {
                                            appState.isICloudAvailable = false
                                            appState.lastBackupDate = nil
                                        }
                                    }
                                ))
                                .tint(.blue)
                                
                                Toggle("Ежедневные напоминания", isOn: Binding(
                                    get: { appState.isDailyReminderEnabled },
                                    set: { newValue in
                                        appState.isDailyReminderEnabled = newValue
                                        SettingsManager.shared.isDailyReminderEnabled = newValue
                                        
                                        Task {
                                            await NotificationManager.shared.scheduleDailyReminder(enabled: newValue)
                                        }
                                    }
                                ))
                                .tint(.blue)
                                
                                if appState.isBackupEnabled {
                                    if let backupDate = appState.lastBackupDate {
                                        VStack(spacing: 12) {
                                            HStack {
                                                Text("Последний backup")
                                                    .foregroundStyle(AppColors.textPrimary)
                                                Spacer()
                                                Text(backupDate.formatted(date: .abbreviated, time: .shortened))
                                                    .foregroundStyle(AppColors.textTertiary)
                                            }
                                            
                                            // Кнопка восстановления, если найдена резервная копия
                                            NavigationLink {
                                                RestoreView(appState: appState, router: router)
                                            } label: {
                                                HStack {
                                                    Image(systemName: "icloud.and.arrow.down.fill")
                                                        .font(.system(size: 16, weight: .semibold))
                                                    Text("Восстановить данные")
                                                        .font(.system(size: 16, weight: .semibold))
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                        .font(.system(size: 12, weight: .semibold))
                                                }
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: AppColors.incomeGradient,
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .padding(.vertical, 12)
                                                .padding(.horizontal, 16)
                                                .background {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(.ultraThinMaterial)
                                                        .overlay {
                                                            RoundedRectangle(cornerRadius: 12)
                                                                .stroke(
                                                                    LinearGradient(
                                                                        colors: AppColors.incomeGradient,
                                                                        startPoint: .leading,
                                                                        endPoint: .trailing
                                                                    ),
                                                                    lineWidth: 1
                                                                )
                                                        }
                                                }
                                            }
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
        .task {
            // Обновляем статус подписки при открытии профиля
            await SubscriptionManager.shared.checkSubscriptionStatus()
            appState.subscriptionStatus = SubscriptionManager.shared.status
            appState.subscriptionExpirationDate = SubscriptionManager.shared.expirationDate
            appState.isTrialActive = SubscriptionManager.shared.isTrialActive
        }
    }
    
    // MARK: - Subscription Status Section
    
    private var subscriptionStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Подписка")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
                
                if appState.isPro {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.incomeGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text(appState.isTrialActive ? "Пробный период" : "PRO")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.incomeGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                } else {
                    Text("Обычная")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            
            if appState.isPro, let expirationDate = appState.subscriptionExpirationDate {
                Text("Действует до: \(formatDate(expirationDate))")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
            }
            
            Button {
                router.push(.subscription)
            } label: {
                Text(appState.isPro ? "Управление подпиской" : "Оформить PRO")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: appState.isPro ? AppColors.incomeGradient : [AppColors.textPrimary.opacity(0.3)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .padding(.horizontal, 24)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        ProfileView(router: AppRouter())
            .environment(AppState())
    }
}
