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

    private var selectedBackupVersion: BackupVersionInfo? {
        if let selectedRecordName {
            return backupVersions.first(where: { $0.recordName == selectedRecordName })
        }
        return backupVersions.first
    }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(spacing: 24) {
                    header

                    if isRestoring {
                        restoringView
                    } else if let selectedVersion = selectedBackupVersion {
                        backupFoundView(version: selectedVersion)
                    } else {
                        noBackupView
                    }

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
            .refreshable {
                await refreshBackupStatusIfNeeded()
            }
        }
        .confirmationDialog(
            "Продолжить без восстановления?",
            isPresented: $showSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button("Продолжить без восстановления", role: .destructive) {
                appState.lifecycle = .ready
                dismiss()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Текущая установка приложения останется без данных из облачной копии.")
        }
        .task {
            await refreshBackupStatusIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.white.opacity(0.95)] + AppColors.financesGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 6) {
                Text("Восстановить данные")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                Text("Выберите нужный снимок. Восстановление полностью заменит локальные данные.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 26)
    }

    private var restoringView: some View {
        FinancesGlassCard(accentColor: AppColors.brandPrimary, cornerRadius: 24) {
            VStack(spacing: 24) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(AppColors.textPrimary)

                VStack(spacing: 8) {
                    Text("Восстанавливаем данные")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Подождите, локальная база будет заменена выбранной копией.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }

    private func backupFoundView(version: BackupVersionInfo) -> some View {
        VStack(spacing: 24) {
            FinancesGlassCard(
                accentColor: AppColors.brandPrimary,
                cornerRadius: 24,
                contentPadding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    statusPill(
                        title: version.isPinned ? "Сохраненный снимок" : "Последняя копия",
                        icon: version.isPinned ? "pin.fill" : "clock.fill",
                        color: version.isPinned ? AppColors.toggleOnGreen : AppColors.brandPrimary
                    )

                    Text("Резервная копия найдена")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)

                    HStack(spacing: 12) {
                        restoreMetric(
                            title: "Дата",
                            value: version.date.formatted(date: .abbreviated, time: .shortened)
                        )
                        restoreMetric(
                            title: "Размер",
                            value: ByteCountFormatter.string(fromByteCount: version.size, countStyle: .file)
                        )
                    }
                }
            }

            if backupVersions.count > 1 {
                FinancesGlassCard(cornerRadius: 24, contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)) {
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
            }

            FinancesGlassCard(accentColor: AppColors.warning, cornerRadius: 22, contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Перед восстановлением")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Эта операция полностью заменит локальные данные на выбранный облачный снимок.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                    Text("Если копия была защищена кодовой фразой, без нее восстановление не завершится.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Кодовая фраза")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    Text("Нужна только для переносимого шифрования")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                }

                FinancesGlassCard(cornerRadius: 20, contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)) {
                    SecureField("Введите кодовую фразу", text: $backupPassphrase)
                        .textContentType(.password)
                        .privacySensitive()
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }

            VStack(spacing: 16) {
                ActionButton(
                    title: "Восстановить из этой копии",
                    icon: .system("arrow.down.circle.fill"),
                    gradientColors: AppColors.financesGradient
                ) {
                    restore()
                }
                .disabled(isRestoring)

                Button {
                    showSkipConfirmation = true
                } label: {
                    Text("Продолжить без восстановления")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .disabled(isRestoring)
            }
        }
    }

    private var noBackupView: some View {
        VStack(spacing: 24) {
            FinancesGlassCard(
                accentColor: AppColors.warning,
                cornerRadius: 24,
                contentPadding: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    statusPill(
                        title: appState.isICloudAvailable ? "Копия не найдена" : "iCloud недоступен",
                        icon: appState.isICloudAvailable ? "exclamationmark.circle.fill" : "icloud.slash.fill",
                        color: AppColors.warning
                    )

                    Text(BackupExperiencePresenter.restoreEmptyStateTitle(isICloudAvailable: appState.isICloudAvailable))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)

                    Text(BackupExperiencePresenter.restoreEmptyStateMessage(isICloudAvailable: appState.isICloudAvailable))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Если вы только что включили резервное копирование, сначала создайте первую копию в профиле.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            VStack(spacing: 12) {
                ActionButton(
                    title: "Повторить поиск",
                    icon: .system("arrow.clockwise"),
                    gradientColors: AppColors.financesGradient
                ) {
                    Task { await refreshBackupStatusIfNeeded() }
                }

                Button {
                    showSkipConfirmation = true
                } label: {
                    Text("Продолжить без восстановления")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
        }
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
        if let versions {
            backupVersions = versions
            selectedRecordName = versions.first?.recordName
            appState.lastBackupDate = versions.first?.date
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

            var result: T?
            for await value in group {
                if let value {
                    result = value
                    break
                }
            }
            group.cancelAll()
            return result
        }
    }

    @ViewBuilder
    private func statusPill(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func restoreMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
