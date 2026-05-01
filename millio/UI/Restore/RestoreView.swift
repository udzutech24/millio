//
//  RestoreView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

private enum RestoreTimeoutError: Error {
    case timedOut
}

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
    @State private var isVersionsExpanded = false
    @State private var backupLookupTimedOut = false

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
                VStack(spacing: 14) {
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
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.error)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .refreshable {
                await refreshBackupStatusIfNeeded()
            }
        }
        .confirmationDialog(
            BackupL10n.tr("backup.restore.confirm.title", fallback: "Continue Without Restoring?"),
            isPresented: $showSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button(BackupL10n.tr("backup.restore.confirm.action", fallback: "Continue Without Restoring"), role: .destructive) {
                appState.lifecycle = .ready
                dismiss()
            }
            Button(BackupL10n.tr("backup.restore.confirm.cancel", fallback: "Cancel"), role: .cancel) {}
        } message: {
            Text(BackupL10n.tr("backup.restore.confirm.message", fallback: "Local data will remain as is."))
        }
        .task {
            await refreshBackupStatusIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)

                Text(BackupL10n.tr("backup.restore.header.title", fallback: "Restore"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
            }

            Text(BackupL10n.tr("backup.restore.header.subtitle", fallback: "Select a backup. Restoring will replace your current local data."))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
    }

    private var restoringView: some View {
        FinancesGlassCard(accentColor: AppColors.brandPrimary, cornerRadius: 22) {
            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(AppColors.textPrimary)

                Text(BackupL10n.tr("backup.restore.progress.title", fallback: "Restoring Data"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(BackupL10n.tr("backup.restore.progress.subtitle", fallback: "Please wait, the database will be replaced with the selected backup."))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(22)
            .frame(maxWidth: .infinity)
        }
    }

    private func backupFoundView(version: BackupVersionInfo) -> some View {
        VStack(spacing: 12) {
            FinancesGlassCard(accentColor: AppColors.brandPrimary, cornerRadius: 22, contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
                VStack(alignment: .leading, spacing: 10) {
                    statusPill(
                        title: version.isPinned
                            ? BackupL10n.tr("backup.restore.version.pinned", fallback: "Saved Version")
                            : BackupL10n.tr("backup.restore.version.latest", fallback: "Latest Backup"),
                        icon: version.isPinned ? "pin.fill" : "clock.fill",
                        color: version.isPinned ? AppColors.toggleOnGreen : AppColors.brandPrimary
                    )

                    HStack(spacing: 10) {
                        restoreMetric(
                            title: BackupL10n.tr("backup.restore.metric.date", fallback: "Date"),
                            value: version.date.formatted(date: .abbreviated, time: .shortened)
                        )
                        restoreMetric(
                            title: BackupL10n.tr("backup.restore.metric.size", fallback: "Size"),
                            value: ByteCountFormatter.string(fromByteCount: version.size, countStyle: .file)
                        )
                    }

                    Text(BackupL10n.tr("backup.restore.warning.replace", fallback: "Local data will be completely replaced."))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            if backupVersions.count > 1 {
                FinancesGlassCard(cornerRadius: 20, contentPadding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isVersionsExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(BackupL10n.tr("backup.restore.action.pick_another", fallback: "Select Another Backup"))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                Image(systemName: isVersionsExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isVersionsExpanded {
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
                                                .font(.system(size: 13, weight: .semibold))

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                                    .font(.system(size: 13, weight: .semibold))
                                                Text(
                                                    String(
                                                        format: String(localized: "restore.version_size_format"),
                                                        ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file),
                                                        String(item.version)
                                                    )
                                                )
                                                .font(.system(size: 11, weight: .regular))
                                                .foregroundStyle(AppColors.textTertiary)
                                            }

                                            Spacer()

                                            if item.isPinned {
                                                Image(systemName: "pin.fill")
                                                    .font(.system(size: 11, weight: .semibold))
                                            }
                                        }
                                        .foregroundStyle(AppColors.textPrimary)
                                        .padding(.vertical, 10)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isRestoring)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                }
            }

            FinancesGlassCard(cornerRadius: 20, contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)) {
                SecureField(BackupL10n.tr("backup.restore.passphrase.placeholder", fallback: "Passphrase (if any)"), text: $backupPassphrase)
                    .textContentType(.password)
                    .privacySensitive()
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }

            SlideToConfirmControl(
                title: BackupL10n.tr("backup.restore.slide.title", fallback: "Restore From Backup"),
                subtitle: BackupL10n.tr("backup.restore.slide.subtitle", fallback: "Slide to replace local data"),
                loadingTitle: BackupL10n.tr("backup.restore.slide.loading.title", fallback: "Restoring data..."),
                loadingSubtitle: BackupL10n.tr("backup.restore.slide.loading.subtitle", fallback: "Don't close the app while replacing"),
                icon: "arrow.right",
                gradientColors: AppColors.financesGradient,
                isEnabled: !isRestoring,
                isLoading: isRestoring
            ) {
                restore()
            }

            Button {
                showSkipConfirmation = true
            } label: {
                Text(BackupL10n.tr("backup.restore.action.skip", fallback: "Continue Without Restoring"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .disabled(isRestoring)
        }
    }

    private var noBackupView: some View {
        VStack(spacing: 12) {
            FinancesGlassCard(accentColor: AppColors.warning, cornerRadius: 22, contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
                VStack(alignment: .leading, spacing: 8) {
                    statusPill(
                        title: backupLookupTimedOut
                            ? BackupL10n.tr("backup.restore.lookup.timedout", fallback: "Still Searching")
                            : (appState.isICloudAvailable
                                ? BackupL10n.tr("backup.restore.empty.status.not_found", fallback: "Backup Not Found")
                                : BackupL10n.tr("backup.restore.empty.title.icloud_unavailable", fallback: "iCloud is unavailable")),
                        icon: backupLookupTimedOut ? "hourglass.circle.fill" : (appState.isICloudAvailable ? "exclamationmark.circle.fill" : "icloud.slash.fill"),
                        color: AppColors.warning
                    )

                    Text(BackupExperiencePresenter.restoreEmptyStateTitle(isICloudAvailable: appState.isICloudAvailable))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)

                    Text(BackupExperiencePresenter.restoreEmptyStateMessage(isICloudAvailable: appState.isICloudAvailable))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ActionButton(
                title: BackupL10n.tr("backup.restore.action.retry", fallback: "Retry Search"),
                icon: .system("arrow.clockwise"),
                gradientColors: AppColors.financesGradient
            ) {
                Task { await refreshBackupStatusIfNeeded() }
            }

            Button {
                showSkipConfirmation = true
            } label: {
                Text(BackupL10n.tr("backup.restore.action.skip", fallback: "Continue Without Restoring"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
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
        backupLookupTimedOut = false
        restoreError = nil

        let available = await withTimeout(seconds: 8) {
            await CloudBackupStore().isAvailable()
        }
        guard let available else {
            backupLookupTimedOut = true
            restoreError = .restoreFailed("Backup lookup timed out. iCloud may still be syncing. Try again.")
            return
        }
        appState.isICloudAvailable = available

        guard appState.isICloudAvailable, let backupManager else { return }
        let versions = await withTimeout(seconds: 8) {
            await backupManager.listBackupVersions()
        }
        guard let versions else {
            backupLookupTimedOut = true
            restoreError = .restoreFailed("Backup lookup timed out. iCloud may still be syncing. Try again.")
            return
        }
        backupVersions = versions
        if selectedRecordName == nil || versions.contains(where: { $0.recordName == selectedRecordName }) == false {
            selectedRecordName = versions.first?.recordName
        }
        appState.lastBackupDate = versions.first?.date
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
        do {
            return try await withThrowingTaskGroup(of: T.self, returning: T?.self) { group in
                group.addTask {
                    await operation()
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(max(0, seconds)))
                    throw RestoreTimeoutError.timedOut
                }

                let result = try await group.next()
                group.cancelAll()
                return result
            }
        } catch is RestoreTimeoutError {
            return nil
        } catch {
            return nil
        }
    }

    @ViewBuilder
    private func statusPill(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func restoreMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
