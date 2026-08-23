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
    /// Таймаут лукапа: молчание облака должно стать различимым исходом, а не бесконечным спиннером.
    private static let lookupTimeoutSeconds: TimeInterval = 8
    @State private var isRestoring = false
    @State private var isLookingUpBackups = false
    @State private var restoreError: AppError?
    @State private var showSkipConfirmation = false
    @State private var backupPassphrase: String = ""
    @State private var isPassphraseExpanded = false
    /// Исход последнего поиска бэкапа. До R4 здесь жил просто список версий, и ошибка облака
    /// была неотличима от «копий нет» (D8).
    @State private var lookupOutcome: BackupLookupOutcome = .empty
    @State private var selectedRecordName: String?
    @State private var isVersionsExpanded = false
    @State private var isImportingFile = false

    private var backupVersions: [BackupVersionInfo] { lookupOutcome.versions }

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
                        lookupStateView
                    }

                    if let error = restoreError {
                        Text(RestoreErrorPresenter.userMessage(for: error))
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

            if showSkipConfirmation {
                skipConfirmationOverlay
            }
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

    private var skipConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()

            FinancesGlassCard(accentColor: AppColors.error, cornerRadius: 24) {
                VStack(spacing: 18) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(AppColors.error)

                    VStack(spacing: 8) {
                        Text(BackupL10n.tr("backup.restore.skip.title", fallback: "Data Not Restored"))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(BackupL10n.tr(
                            "backup.restore.skip.message",
                            fallback: "Local data is not available. The app will open empty. You can restore later in Profile → Backup as long as your backup exists in iCloud."
                        ))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 10) {
                        Button {
                            showSkipConfirmation = false
                        } label: {
                            Text(BackupL10n.tr("backup.restore.skip.cancel", fallback: "Go Back and Restore"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            showSkipConfirmation = false
                            appState.lifecycle = .ready
                            dismiss()
                        } label: {
                            Text(BackupL10n.tr("backup.restore.skip.confirm", fallback: "Continue Without Data"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.error)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(22)
            }
            .padding(.horizontal, 28)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showSkipConfirmation)
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
                                                        format: L("restore.version_size_format"),
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
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isPassphraseExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: backupPassphrase.isEmpty ? "lock" : "lock.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(backupPassphrase.isEmpty ? AppColors.textTertiary : AppColors.brandPrimary)
                            Text(backupPassphrase.isEmpty
                                ? BackupL10n.tr("backup.restore.passphrase.toggle", fallback: "Protected with passphrase?")
                                : BackupL10n.tr("backup.restore.passphrase.toggle.set", fallback: "Passphrase entered")
                            )
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Image(systemName: isPassphraseExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isPassphraseExpanded {
                        FinancesRowDivider(leadingPadding: 14)

                        SecureField(BackupL10n.tr("backup.restore.passphrase.placeholder", fallback: "Enter passphrase"), text: $backupPassphrase)
                            .textContentType(.password)
                            .privacySensitive()
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                }
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

            restoreFromFileButton

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

    /// Единственный экран для исходов «версии не выбраны»: пусто / ошибка / таймаут.
    /// Тексты и иконка приходят из `BackupExperiencePresenter`, чтобы различие исходов
    /// проверялось тестом, а не глазами.
    private var lookupStateView: some View {
        let presentation = BackupExperiencePresenter.restoreLookupPresentation(
            outcome: lookupOutcome,
            isICloudAvailable: appState.isICloudAvailable
        )

        return VStack(spacing: AppSpacing.m) {
            FinancesGlassCard(accentColor: AppColors.warning, cornerRadius: 22, contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    statusPill(
                        title: presentation.statusTitle,
                        icon: presentation.statusIcon,
                        color: AppColors.warning
                    )

                    Text(presentation.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)

                    Text(presentation.message)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if presentation.showsRetry {
                ActionButton(
                    title: BackupL10n.tr("backup.restore.action.retry", fallback: "Retry Search"),
                    icon: .system("arrow.clockwise"),
                    gradientColors: AppColors.financesGradient
                ) {
                    Task { await refreshBackupStatusIfNeeded() }
                }
                .disabled(isLookingUpBackups)
            }

            restoreFromFileButton

            Button {
                showSkipConfirmation = true
            } label: {
                Text(BackupL10n.tr("backup.restore.action.skip", fallback: "Continue Without Restoring"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.s)
            }
        }
    }

    /// Точка входа «файл → данные» на пустой базе: до этого импорт файла жил только в Профиле,
    /// недоступном, пока пользователь не прошёл экран восстановления.
    /// Сам разбор и подтверждение перезаписи выполняет общий `incomingBackupFileRestore` в корне
    /// сцены — здесь только выбор файла, чтобы путь восстановления был один.
    private var restoreFromFileButton: some View {
        Button {
            isImportingFile = true
        } label: {
            Text(BackupL10n.tr("backup.restore.from_file.action", fallback: "Restore from File"))
                .font(.millioSubheadline)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.m)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.textSecondary.opacity(0.4), lineWidth: 1)
                )
        }
        .disabled(isRestoring)
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: BackupFileFormat.importerContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                appState.pendingIncomingBackupURL = url
            case .failure(let error):
                restoreError = .backupFailed(error.localizedDescription)
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
        guard !isRestoring, !isLookingUpBackups else { return }
        isLookingUpBackups = true
        restoreError = nil
        defer { isLookingUpBackups = false }

        let available = await withTimeout(seconds: Self.lookupTimeoutSeconds) {
            await CloudBackupStore().isAvailable()
        }
        guard let available else {
            applyLookupOutcome(.timedOut)
            return
        }
        appState.isICloudAvailable = available

        guard available, let backupManager else {
            // Не «копий нет»: без доступа к iCloud список вообще не запрашивался.
            applyLookupOutcome(.failed(.iCloudUnavailable))
            return
        }

        applyLookupOutcome(await backupManager.lookupBackupVersions(timeout: Self.lookupTimeoutSeconds))
    }

    @MainActor
    private func applyLookupOutcome(_ outcome: BackupLookupOutcome) {
        lookupOutcome = outcome
        AppLogger.log(.info, category: "Restore", "RestoreView: \(outcome.diagnosticSummary)")

        let versions = outcome.versions
        if selectedRecordName == nil || versions.contains(where: { $0.recordName == selectedRecordName }) == false {
            selectedRecordName = versions.first?.recordName
        }
        // Дату последней копии перетирать нечем, если лукап не дал ответа: неизвестность
        // не должна выглядеть как «копий нет».
        if outcome.isUnresolved == false {
            appState.lastBackupDate = versions.first?.date
        }
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
