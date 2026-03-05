//
//  BackupManagementView.swift
//  millio
//
//  Created by Александр Сидоркин on 30.01.2026.
//

import SwiftUI

private enum BackupEncryptionMode: String, CaseIterable, Identifiable {
    case deviceKey
    case passphrase
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .deviceKey: "On device"
        case .passphrase: "Passphrase"
        }
    }
    
    var description: String {
        switch self {
        case .deviceKey:
            "Key is stored in iOS Keychain. Restore may be unavailable after reinstall or on a new device."
        case .passphrase:
            "Creates a portable backup. A passphrase is required for restore."
        }
    }
}

struct BackupManagementView: View {
    @Bindable var router: AppRouter
    @Environment(AppState.self) private var appState
    @Environment(\.diContainer) private var diContainer
    
    @State private var isBusy = false
    @State private var backupError: AppError?
    @State private var passphrase: String = ""
    @State private var passphraseConfirmation: String = ""
    @State private var isPassphraseVisible: Bool = false
    @State private var encryptionMode: BackupEncryptionMode = .deviceKey
    @State private var backupVersions: [BackupVersionInfo] = []
    @State private var deletingRecordName: String?
    
    private var backupManager: BackupManagerProtocol? {
        diContainer?.backupManager
    }
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    header
                    
                    settingsCard
                    
                    statusCard
                    
                    actionsCard

                    versionsCard
                    
                    if let backupError {
                        Text(backupError.localizedDescription)
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
        .onAppear {
            let isDeviceKeyEnabled = SettingsManager.shared.isEncryptionEnabled
            encryptionMode = isDeviceKeyEnabled ? .deviceKey : .passphrase
            Task { await refreshStatusIfNeeded() }
        }
    }
    
    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "icloud.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: AppColors.incomeGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Backup")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
    
    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Settings")
            
            FinancesGlassCard {
                VStack(spacing: 0) {
                    // Backup Toggle
                    HStack {
                        Text("Enable backup")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { appState.isBackupEnabled },
                            set: { newValue in
                                appState.isBackupEnabled = newValue
                                SettingsManager.shared.isBackupEnabled = newValue
                                
                                if !newValue {
                                    appState.isICloudAvailable = false
                                    appState.lastBackupDate = nil
                                    backupVersions = []
                                }
                                
                                Task { await refreshStatusIfNeeded() }
                            }
                        ))
                        .tint(AppColors.toggleOnGreen)
                        .labelsHidden()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    // Encryption Settings
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Encryption")
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                        }
                        
                        Picker("Encryption", selection: $encryptionMode) {
                            ForEach(BackupEncryptionMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(!appState.isBackupEnabled || isBusy)
                        
                        Text(encryptionMode.description)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .onChange(of: encryptionMode) { _, newValue in
                        switch newValue {
                        case .deviceKey:
                            SettingsManager.shared.isEncryptionEnabled = true
                        case .passphrase:
                            SettingsManager.shared.isEncryptionEnabled = false
                        }
                    }
                    
                    if encryptionMode == .passphrase {
                        FinancesRowDivider()
                        
                        HStack {
                            if isPassphraseVisible {
                                TextField("Passphrase", text: $passphrase)
                                    .foregroundStyle(AppColors.textPrimary)
                            } else {
                                SecureField("Passphrase", text: $passphrase)
                                    .textContentType(.password)
                                    .privacySensitive()
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                            
                            Button {
                                isPassphraseVisible.toggle()
                            } label: {
                                Image(systemName: isPassphraseVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                        .disabled(!appState.isBackupEnabled || isBusy)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        
                        FinancesRowDivider()
                        
                        SecureField("Confirm passphrase", text: $passphraseConfirmation)
                            .textContentType(.password)
                            .privacySensitive()
                            .disabled(!appState.isBackupEnabled || isBusy)
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
    
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Status")
            
            FinancesGlassCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("iCloud")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(appState.isBackupEnabled ? (appState.isICloudAvailable ? "available" : "unavailable") : "off")
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    HStack {
                        Text("Last backup")
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        if let date = appState.lastBackupDate {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(AppColors.textTertiary)
                        } else {
                            Text("none")
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    
                    FinancesRowDivider()
                    
                    Button {
                        Task { await refreshStatusIfNeeded(force: true) }
                    } label: {
                        HStack {
                            Text("Refresh status")
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }
        }
    }
    
    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Actions")
            
            let trimmedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedConfirmation = passphraseConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)
            let isPassphraseValid = encryptionMode != .passphrase || (!trimmedPassphrase.isEmpty && trimmedPassphrase == trimmedConfirmation)
            let canCreateBackup = appState.isBackupEnabled && !isBusy && deletingRecordName == nil && isPassphraseValid
            
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Button {
                        Task { await createBackupNow() }
                    } label: {
                        HStack {
                            Image(systemName: "icloud.and.arrow.up.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text(isBusy ? "Creating backup..." : "Create backup now")
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            if isBusy {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        .foregroundStyle(canCreateBackup ? AppColors.textPrimary : AppColors.textTertiary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreateBackup)

                    FinancesRowDivider()

                    Button {
                        Task { await savePinnedVersionNow() }
                    } label: {
                        HStack {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text(isBusy ? "Saving version..." : "Save as version")
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            if isBusy {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        .foregroundStyle(canCreateBackup ? AppColors.textPrimary : AppColors.textTertiary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreateBackup)
                    
                    if encryptionMode == .passphrase, appState.isBackupEnabled {
                        if trimmedPassphrase.isEmpty {
                            FinancesRowDivider()
                            
                            Text("Enter a passphrase, otherwise this backup cannot be restored.")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(AppColors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                        } else if trimmedPassphrase != trimmedConfirmation {
                            FinancesRowDivider()
                            
                            Text("Passphrases do not match")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(AppColors.error)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                        }
                    }
                    
                    FinancesRowDivider()
                    
                    NavigationLink {
                        RestoreView(appState: appState, router: router)
                    } label: {
                        HStack {
                            Image(systemName: "icloud.and.arrow.down.fill")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Restore data")
                                .font(.system(size: 16, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }
            }
        }
    }

    private var versionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Backup versions")

            FinancesGlassCard {
                if backupVersions.isEmpty {
                    Text("No saved versions yet")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(backupVersions.enumerated()), id: \.element.id) { index, version in
                            if index > 0 {
                                FinancesRowDivider()
                            }
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(version.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text(
                                        String(
                                            format: String(localized: "restore.version_size_format"),
                                            ByteCountFormatter.string(fromByteCount: version.size, countStyle: .file),
                                            String(version.version)
                                        )
                                    )
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                                Spacer()
                                if version.isPinned {
                                    Text("Pinned")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(AppColors.toggleOnGreen.opacity(0.25))
                                        .clipShape(Capsule())
                                }
                                Button(role: .destructive) {
                                    Task { await deleteVersion(recordName: version.recordName) }
                                } label: {
                                    if deletingRecordName == version.recordName {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "trash")
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(isBusy || deletingRecordName != nil)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    private func refreshStatusIfNeeded(force: Bool = false) async {
        guard appState.isBackupEnabled else { return }
        if !force, appState.isICloudAvailable, appState.lastBackupDate != nil { return }
        
        backupError = nil
        
        let cloudStore = CloudBackupStore()
        appState.isICloudAvailable = await cloudStore.isAvailable()
        
        guard appState.isICloudAvailable, let backupManager else { return }
        backupVersions = await backupManager.listBackupVersions()
        appState.lastBackupDate = backupVersions.first?.date
    }
    
    @MainActor
    private func createBackupNow() async {
        guard let backupManager else {
            backupError = .iCloudUnavailable
            return
        }
        
        isBusy = true
        backupError = nil
        defer { isBusy = false }
        
        do {
            let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
            switch encryptionMode {
            case .passphrase:
                try await backupManager.backupNow(passphrase: trimmed.isEmpty ? nil : trimmed)
            case .deviceKey:
                try await backupManager.backupNow()
            }
            await refreshStatusIfNeeded(force: true)
        } catch let appError as AppError {
            backupError = appError
        } catch {
            backupError = .unknown(error)
        }
    }

    @MainActor
    private func savePinnedVersionNow() async {
        guard let backupManager else {
            backupError = .iCloudUnavailable
            return
        }

        isBusy = true
        backupError = nil
        defer { isBusy = false }

        do {
            let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
            try await backupManager.saveVersionNow(passphrase: encryptionMode == .passphrase ? (trimmed.isEmpty ? nil : trimmed) : nil)
            await refreshStatusIfNeeded(force: true)
        } catch let appError as AppError {
            backupError = appError
        } catch {
            backupError = .unknown(error)
        }
    }

    @MainActor
    private func deleteVersion(recordName: String) async {
        guard let backupManager else {
            backupError = .iCloudUnavailable
            return
        }
        deletingRecordName = recordName
        backupError = nil
        defer { deletingRecordName = nil }

        do {
            try await backupManager.deleteBackupVersion(recordName: recordName)
            await refreshStatusIfNeeded(force: true)
        } catch let appError as AppError {
            backupError = appError
        } catch {
            backupError = .unknown(error)
        }
    }
}
