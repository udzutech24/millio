//
//  BackupManagementView.swift
//  millio
//
//  Created by Александр Сидоркин on 30.01.2026.
//

import SwiftUI

private enum BackupEncryptionMode: String, CaseIterable, Identifiable {
    case none
    case deviceKey
    case passphrase
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .none: "Не шифровать"
        case .deviceKey: "На устройстве"
        case .passphrase: "Парольная фраза"
        }
    }
    
    var description: String {
        switch self {
        case .none:
            "Подходит, если вы доверяете iCloud и устройству."
        case .deviceKey:
            "Ключ хранится в iOS Keychain. После переустановки/на новом устройстве восстановление может быть невозможно."
        case .passphrase:
            "Создание переносимого backup. Для восстановления нужна парольная фраза."
        }
    }
}

struct BackupManagementView: View {
    @Bindable var router: AppRouter
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.modelContainer) private var modelContainer
    
    @State private var isBusy = false
    @State private var backupError: AppError?
    @State private var passphrase: String = ""
    @State private var encryptionMode: BackupEncryptionMode = .none
    
    private var backupManager: BackupManagerProtocol? {
        guard let container = modelContainer else { return nil }
        let dataRepository = DataRepository(modelContext: modelContext, modelContainer: container)
        return BackupManager(dataRepository: dataRepository)
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
            encryptionMode = isDeviceKeyEnabled ? .deviceKey : .none
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
            
            Text("Резервное копирование")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
    
    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Настройки")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            
            Toggle("Включить backup", isOn: Binding(
                get: { appState.isBackupEnabled },
                set: { newValue in
                    appState.isBackupEnabled = newValue
                    SettingsManager.shared.isBackupEnabled = newValue
                    
                    if !newValue {
                        appState.isICloudAvailable = false
                        appState.lastBackupDate = nil
                    }
                    
                    Task { await refreshStatusIfNeeded() }
                }
            ))
            .tint(.blue)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Шифрование")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Picker("Шифрование", selection: $encryptionMode) {
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
            .onChange(of: encryptionMode) { _, newValue in
                switch newValue {
                case .none:
                    SettingsManager.shared.isEncryptionEnabled = false
                case .deviceKey:
                    SettingsManager.shared.isEncryptionEnabled = true
                case .passphrase:
                    SettingsManager.shared.isEncryptionEnabled = false
                }
            }
            
            if encryptionMode == .passphrase {
                SecureField("Парольная фраза для создания backup", text: $passphrase)
                    .textContentType(.password)
                    .privacySensitive()
                    .disabled(!appState.isBackupEnabled || isBusy)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
    }
    
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Статус")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            
            HStack {
                Text("iCloud")
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text(appState.isBackupEnabled ? (appState.isICloudAvailable ? "доступен" : "недоступен") : "выключен")
                    .foregroundStyle(AppColors.textTertiary)
            }
            
            HStack {
                Text("Последний backup")
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                if let date = appState.lastBackupDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(AppColors.textTertiary)
                } else {
                    Text("нет")
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            
            Button {
                Task { await refreshStatusIfNeeded(force: true) }
            } label: {
                HStack {
                    Text("Обновить статус")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(AppColors.textSecondary)
                .padding(.vertical, 6)
            }
            .disabled(isBusy)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        }
    }
    
    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Действия")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            
            ActionButton(
                title: isBusy ? "Создание backup..." : "Создать backup сейчас",
                icon: "icloud.and.arrow.up.fill",
                gradientColors: AppColors.incomeGradient
            ) {
                Task { await createBackupNow() }
            }
            .disabled(!appState.isBackupEnabled || isBusy)
            
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
            .disabled(isBusy)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
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
        if let backupInfo = await backupManager.lastBackupInfo() {
            appState.lastBackupDate = backupInfo.date
        }
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
            case .none, .deviceKey:
                try await backupManager.backupNow()
            }
            await refreshStatusIfNeeded(force: true)
        } catch let appError as AppError {
            backupError = appError
        } catch {
            backupError = .unknown(error)
        }
    }
}
