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
    @Environment(\.dismiss) private var dismiss
    @State private var isRestoring = false
    @State private var restoreError: AppError?
    @State private var showSkipConfirmation = false
    @State private var backupPassphrase: String = ""
    
    private var backupManager: BackupManagerProtocol? {
        guard let modelContainer = modelContainer else { return nil }
        let dataRepository = DataRepository(modelContext: modelContext, modelContainer: modelContainer)
        return BackupManager(dataRepository: dataRepository)
    }
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "icloud.and.arrow.down.fill")
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.incomeGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Восстановление данных")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    
                    // Content
                    if !appState.isBackupEnabled {
                        backupDisabledView
                    } else if isRestoring {
                        restoringView
                    } else {
                        if let backupDate = appState.lastBackupDate {
                            backupFoundView(backupDate: backupDate)
                        } else {
                            noBackupView
                        }
                    }
                    
                    // Error message
                    if let error = restoreError {
                        Text(error.localizedDescription)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .confirmationDialog(
            "Пропустить восстановление?",
            isPresented: $showSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button("Пропустить", role: .destructive) {
                appState.lifecycle = .ready
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы уверены, что хотите пропустить восстановление? Все данные из резервной копии будут потеряны.")
        }
        .task {
            await refreshBackupStatusIfNeeded()
        }
    }
    
    // MARK: - Backup Disabled View
    
    private var backupDisabledView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text("Резервное копирование отключено")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text("Включите резервное копирование в настройках для восстановления данных")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            
            ActionButton(
                title: "Продолжить",
                icon: .system("arrow.right"),
                gradientColors: AppColors.incomeGradient
            ) {
                appState.lifecycle = .ready
                dismiss()
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Restoring View
    
    private var restoringView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            
            Text("Восстановление данных...")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text("Пожалуйста, подождите")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Backup Found View
    
    private func backupFoundView(backupDate: Date) -> some View {
        VStack(spacing: 24) {
            // Backup info card
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text("Найдена резервная копия")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                        
                        Text(backupDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.incomeGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    }
            }
            
            // Warning text
            Text("Восстановление заменит все текущие данные данными из резервной копии")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 8) {
                Text("Парольная фраза (если backup был зашифрован)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                
                SecureField("Введите парольную фразу", text: $backupPassphrase)
                    .textContentType(.password)
                    .privacySensitive()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
            }
            .padding(.horizontal, 24)
            
            // Action buttons
            VStack(spacing: 16) {
                ActionButton(
                    title: "Восстановить",
                icon: .system("arrow.down.circle.fill"),
                    gradientColors: AppColors.incomeGradient
                ) {
                    restore()
                }
                .disabled(isRestoring)
                
                Button {
                    showSkipConfirmation = true
                } label: {
                    Text("Пропустить восстановление")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .disabled(isRestoring)
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - No Backup View
    
    private var noBackupView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Text("Резервная копия не найдена")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text("Продолжите работу с приложением")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            
            ActionButton(
                title: "Продолжить",
                icon: .system("arrow.right"),
                gradientColors: AppColors.incomeGradient
            ) {
                appState.lifecycle = .ready
                dismiss()
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Restore Logic
    
    private func restore() {
        guard let backupManager = backupManager else {
            restoreError = .iCloudUnavailable
            return
        }
        
        isRestoring = true
        restoreError = nil
        
        Task {
            do {
                let passphrase = backupPassphrase.trimmingCharacters(in: .whitespacesAndNewlines)
                try await backupManager.restoreLatest(passphrase: passphrase.isEmpty ? nil : passphrase)
                await MainActor.run {
                    isRestoring = false
                    appState.lifecycle = .ready
                    dismiss()
                }
            } catch let error as AppError {
                await MainActor.run {
                    isRestoring = false
                    restoreError = error
                }
            } catch {
                await MainActor.run {
                    isRestoring = false
                    restoreError = .unknown(error)
                }
            }
        }
    }
    
    @MainActor
    private func refreshBackupStatusIfNeeded() async {
        guard appState.isBackupEnabled, !isRestoring else { return }
        
        let available = await withTimeout(seconds: 3) {
            await CloudBackupStore().isAvailable()
        }
        appState.isICloudAvailable = available ?? false
        
        guard appState.isICloudAvailable, let backupManager else { return }
        let info = await withTimeout(seconds: 3) {
            await backupManager.lastBackupInfo()
        }
        if let infoOptional = info, let info = infoOptional {
            appState.lastBackupDate = info.date
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            
            var result: T? = nil
            for await value in group {
                if let value = value {
                    result = value
                    break
                }
            }
            group.cancelAll()
            return result
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
