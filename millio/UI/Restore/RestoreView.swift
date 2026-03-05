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
    @Environment(\.diContainer) private var diContainer
    @Environment(\.dismiss) private var dismiss
    @State private var isRestoring = false
    @State private var restoreError: AppError?
    @State private var showSkipConfirmation = false
    @State private var backupPassphrase: String = ""
    @State private var backupVersions: [BackupVersionInfo] = []
    @State private var selectedRecordName: String?
    
    private var backupManager: BackupManagerProtocol? {
        diContainer?.backupManager
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
                        
                        Text("Restore data")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    
                    // Content
                    if isRestoring {
                        restoringView
                    } else {
                        if let selectedVersion = selectedBackupVersion {
                            backupFoundView(version: selectedVersion)
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
            "Skip restore?",
            isPresented: $showSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button("Skip", role: .destructive) {
                appState.lifecycle = .ready
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to skip restore? Backup data will not be applied.")
        }
        .task {
            await refreshBackupStatusIfNeeded()
        }
    }
    
    // MARK: - Restoring View
    
    private var restoringView: some View {
        FinancesGlassCard {
            VStack(spacing: 24) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(AppColors.textPrimary)
                
                VStack(spacing: 8) {
                    Text("Restoring data...")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                    
                    Text("Please wait")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Backup Found View
    
    private var selectedBackupVersion: BackupVersionInfo? {
        if let selectedRecordName {
            return backupVersions.first(where: { $0.recordName == selectedRecordName })
        }
        return backupVersions.first
    }

    private func backupFoundView(version: BackupVersionInfo) -> some View {
        VStack(spacing: 24) {
            // Backup info card
            FinancesGlassCard {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text("Backup found")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(AppColors.textTertiary)
                            
                            Text(version.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        
                        if version.isPinned {
                            Text("Pinned version")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }

            if backupVersions.count > 1 {
                FinancesGlassCard(contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)) {
                    VStack(spacing: 0) {
                        ForEach(Array(backupVersions.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                FinancesRowDivider()
                            }
                            Button {
                                selectedRecordName = item.recordName
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedRecordName == item.recordName ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 14, weight: .semibold))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 14, weight: .semibold))
                                        Text(
                                            String(
                                                format: String(localized: "restore.version_size_format"),
                                                ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file),
                                                String(item.version)
                                            )
                                        )
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(AppColors.textTertiary)
                                    }
                                    Spacer()
                                    if item.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                }
                                .foregroundStyle(AppColors.textPrimary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .disabled(isRestoring)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            
            // Warning text
            Text("Restore will replace all current data with backup data")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 8) {
                Text("Passphrase (if backup is encrypted)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
                
                FinancesGlassCard(contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)) {
                    SecureField("Enter passphrase", text: $backupPassphrase)
                        .textContentType(.password)
                        .privacySensitive()
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }
            .padding(.horizontal, 24)
            
            // Action buttons
            VStack(spacing: 16) {
                ActionButton(
                    title: "Restore",
                    icon: .system("arrow.down.circle.fill"),
                    gradientColors: AppColors.incomeGradient
                ) {
                    restore()
                }
                .disabled(isRestoring)
                
                Button {
                    showSkipConfirmation = true
                } label: {
                    Text("Skip restore")
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
            FinancesGlassCard {
                VStack(spacing: 12) {
                    Text("No backup found")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                    
                    Text("Continue using the app")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            
            ActionButton(
                title: "Continue",
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
                if let selectedRecordName {
                    try await backupManager.restoreVersion(
                        recordName: selectedRecordName,
                        passphrase: passphrase.isEmpty ? nil : passphrase
                    )
                } else {
                    try await backupManager.restoreLatest(passphrase: passphrase.isEmpty ? nil : passphrase)
                }
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
        guard !isRestoring else { return }
        
        let available = await withTimeout(seconds: 3) {
            await CloudBackupStore().isAvailable()
        }
        appState.isICloudAvailable = available ?? false
        
        guard appState.isICloudAvailable, let backupManager else { return }
        let versions = await withTimeout(seconds: 3) {
            await backupManager.listBackupVersions()
        }
        if let versionsOptional = versions {
            backupVersions = versionsOptional
            selectedRecordName = versionsOptional.first?.recordName
            appState.lastBackupDate = versionsOptional.first?.date
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
