//
//  BackupManagementView.swift
//  millio
//
//  Created by Александр Сидоркин on 30.01.2026.
//

import Security
import SwiftUI
import UniformTypeIdentifiers

struct BackupManagementView: View {
    @Bindable var router: AppRouter
    @Environment(AppState.self) private var appState
    @Environment(\.diContainer) private var diContainer

    @State private var isBusy = false
    @State private var backupError: AppError?
    @State private var passphrase: String = ""
    @State private var passphraseConfirmation: String = ""
    @State private var isPassphraseVisible = false
    @State private var isPassphraseConfirmed = false
    @State private var isPassphraseEditorExpanded = true
    @State private var isProtectionExpanded = BackupProtectionDisclosureStore.load()
    @State private var isHydratingStoredPassphrase = false
    @State private var hydratedStoredPassphrase: String?
    @State private var encryptionMode: BackupEncryptionMode = .deviceKey
    @State private var isAutoBackupOptionsExpanded = false
    @State private var isActionsExpanded = false
    @State private var backupVersions: [BackupVersionInfo] = []
    @State private var deletingRecordName: String?
    @State private var isVersionsExpanded = false
    @State private var selectedRestoreRecordName: String?
    @State private var showRestoreConfirmation = false
    @State private var showRestoreSuccessPrompt = false
    @State private var isImportingVersion = false
    @State private var isExportingVersion = false
    @State private var exportDocument: BackupTransferFileDocument?
    @State private var exportFilename = "millio-backup.milliobackup"
    @FocusState private var focusedField: PassphraseField?

    private enum PassphraseField {
        case passphrase
        case confirmation
    }

    private var backupManager: BackupManagerProtocol? {
        diContainer?.backupManager
    }

    private var dashboardContent: BackupDashboardContent {
        BackupExperiencePresenter.dashboard(
            isBackupEnabled: appState.isBackupEnabled,
            isICloudAvailable: appState.isICloudAvailable,
            lastBackupDate: appState.lastBackupDate,
            encryptionMode: encryptionMode,
            hasPinnedVersions: backupVersions.contains(where: \.isPinned)
        )
    }

    private var trimmedPassphrase: String {
        passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedConfirmation: String {
        passphraseConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isPassphraseValid: Bool {
        encryptionMode != .passphrase || (!trimmedPassphrase.isEmpty && trimmedPassphrase == trimmedConfirmation)
    }

    private var isPassphraseReadyForBackup: Bool {
        encryptionMode != .passphrase || (isPassphraseValid && isPassphraseConfirmed)
    }

    private var hasConfirmedPassphrase: Bool {
        isPassphraseConfirmed && !trimmedPassphrase.isEmpty
    }

    private var isProtectionConfigured: Bool {
        encryptionMode == .deviceKey || hasConfirmedPassphrase
    }

    private var isBackupOperational: Bool {
        appState.isBackupEnabled && appState.isICloudAvailable
    }

    private var canCreateBackup: Bool {
        isBackupOperational && !isBusy && deletingRecordName == nil && isPassphraseReadyForBackup
    }

    private var canRestoreSelectedVersion: Bool {
        appState.isICloudAvailable
            && selectedRestoreRecordName != nil
            && !isBusy
            && deletingRecordName == nil
            && (encryptionMode != .passphrase || !trimmedPassphrase.isEmpty)
    }

    private var canExportSelectedVersion: Bool {
        isBackupOperational
            && selectedRestoreRecordName != nil
            && !isBusy
            && deletingRecordName == nil
    }

    private var canImportVersion: Bool {
        isBackupOperational
            && !isBusy
            && deletingRecordName == nil
    }

    private var selectedRestoreVersion: BackupVersionInfo? {
        guard let selectedRestoreRecordName else { return nil }
        return backupVersions.first(where: { $0.recordName == selectedRestoreRecordName })
    }

    private var maxManualVersionCount: Int { 4 }

    private var pinnedVersionsCount: Int {
        backupVersions.filter(\.isPinned).count
    }

    private var hasReachedPinnedVersionLimit: Bool {
        pinnedVersionsCount >= maxManualVersionCount
    }

    private var oldestPinnedVersion: BackupVersionInfo? {
        backupVersions
            .filter(\.isPinned)
            .min(by: { $0.date < $1.date })
    }

    private var preferredMode: BackupEncryptionMode {
        .passphrase
    }

    private var primaryStatusLine: String {
        if !appState.isBackupEnabled {
            return BackupL10n.tr("backup.statusline.off", fallback: "Turn on backup to keep a recovery copy in iCloud")
        }
        if !appState.isICloudAvailable {
            return BackupL10n.tr("backup.statusline.icloud", fallback: "Millio is ready, but iCloud is not responding yet")
        }
        if backupVersions.isEmpty {
            return BackupL10n.tr("backup.statusline.first", fallback: "Create your first backup now")
        }
        return BackupL10n.tr("backup.statusline.ready", fallback: "Everything is ready for restore")
    }

    private var protectionHeadline: String {
        encryptionMode == .passphrase
            ? BackupL10n.tr("backup.protection.headline.passphrase", fallback: "Best for moving to a new device")
            : BackupL10n.tr("backup.protection.headline.device", fallback: "Fastest, but limited to this iPhone")
    }

    private var protectionCollapsedSummary: String {
        switch encryptionMode {
        case .deviceKey:
            return BackupL10n.tr("backup.protection.summary.device", fallback: "Device-only protection is selected")
        case .passphrase:
            return hasConfirmedPassphrase
                ? BackupL10n.tr("backup.protection.summary.passphrase", fallback: "Passphrase is saved and ready for restore")
                : BackupL10n.tr("backup.protection.summary.passphrase_pending", fallback: "Finish passphrase setup to use portable restore")
        }
    }

    private var passphraseHelperText: String {
        hasConfirmedPassphrase && !isPassphraseEditorExpanded
            ? BackupL10n.tr("backup.passphrase.helper.saved", fallback: "Saved locally for convenience, keep your own copy somewhere safe")
            : BackupL10n.tr("backup.passphrase.helper.edit", fallback: "Choose a phrase you can type again later on another device")
    }

    private var createButtonTitle: String {
        backupVersions.isEmpty
            ? BackupL10n.tr("backup.actions.create.primary.first", fallback: "Create first backup")
            : BackupL10n.tr("backup.actions.create.primary.next", fallback: "Save new backup")
    }

    private var restoreButtonTitle: String {
        selectedRestoreVersion == nil
            ? BackupL10n.tr("backup.actions.restore.primary.select", fallback: "Choose a backup to restore")
            : BackupL10n.tr("backup.actions.restore.primary.go", fallback: "Restore selected backup")
    }

    private var createSliderSubtitle: String {
        if isBusy {
            return BackupL10n.tr("backup.actions.create.subtitle.busy", fallback: "Another backup operation is already running")
        }
        if hasReachedPinnedVersionLimit {
            return BackupL10n.format(
                "backup.actions.create.subtitle.limit",
                fallback: "Maximum of %lld manual versions reached, delete one old version to save a new one",
                maxManualVersionCount
            )
        }
        if !isBackupOperational {
            return BackupL10n.tr("backup.actions.create.subtitle.requirements", fallback: "Turn on backup and iCloud first")
        }
        return BackupL10n.tr("backup.actions.create.subtitle.safety", fallback: "Creates a saved version that stays until you delete it")
    }

    private var restoreSliderSubtitle: String {
        guard let selectedRestoreVersion else {
            return BackupL10n.tr("backup.actions.restore.subtitle.select_first", fallback: "Select a version in the list below first")
        }
        return selectedRestoreVersion.date.formatted(date: .abbreviated, time: .shortened)
    }

    private var primaryActionHint: String? {
        guard appState.isBackupEnabled else {
            return BackupL10n.tr("backup.hint.enable_backup", fallback: "Enable backup")
        }
        guard appState.isICloudAvailable else {
            return BackupL10n.tr("backup.hint.enable_icloud", fallback: "iCloud access is required")
        }
        guard encryptionMode != .passphrase || !trimmedPassphrase.isEmpty else {
            return BackupL10n.tr("backup.hint.enter_passphrase", fallback: "Enter a passphrase")
        }
        guard encryptionMode != .passphrase || trimmedPassphrase == trimmedConfirmation else {
            return BackupL10n.tr("backup.hint.passphrase_mismatch", fallback: "Passphrases do not match")
        }
        guard encryptionMode != .passphrase || isPassphraseConfirmed else {
            return BackupL10n.tr("backup.hint.confirm_passphrase", fallback: "Tap Done to confirm the passphrase")
        }
        guard selectedRestoreRecordName != nil else {
            return BackupL10n.tr("backup.hint.select_restore_version", fallback: "Select a version to restore")
        }
        return nil
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width - 40, 0)

            ZStack {
                GradientBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        header
                        overviewCard(availableWidth: availableWidth)
                        protectionCard
                        actionsCard(availableWidth: availableWidth)
                        versionsCard

                        if let backupError {
                            Text(backupError.localizedDescription)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(AppColors.error)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.immediately)
                .dismissKeyboardOnTap()
                .refreshable {
                    await refreshStatusIfNeeded(force: true)
                }
            }
        }
        .alert(
            BackupL10n.tr("backup.restore.confirm.title", fallback: "Restore this version?"),
            isPresented: $showRestoreConfirmation
        ) {
            Button(BackupL10n.tr("backup.restore.confirm.action", fallback: "Yes, restore"), role: .destructive) {
                Task { await restoreSelectedVersion() }
            }
            Button(BackupL10n.tr("common.cancel", fallback: "Cancel"), role: .cancel) {}
        } message: {
            Text(BackupL10n.tr("backup.restore.confirm.message", fallback: "Current local data will be fully replaced by the selected backup"))
        }
        .alert(
            BackupL10n.tr("backup.restore.success.title", fallback: "Data restored"),
            isPresented: $showRestoreSuccessPrompt
        ) {
            Button(BackupL10n.tr("common.done", fallback: "OK"), role: .cancel) {
                router.selectedTab = .finances
                router.popToRoot()
            }
        } message: {
            Text(BackupL10n.tr("backup.restore.success.message", fallback: "Your data has been restored and will appear in the app shortly"))
        }
        .fileExporter(
            isPresented: $isExportingVersion,
            document: exportDocument,
            contentType: .millioBackup,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                backupError = .backupFailed(error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $isImportingVersion,
            allowedContentTypes: BackupTransferFileDocument.readableContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await importBackupFile(from: url) }
            case .failure(let error):
                backupError = .backupFailed(error.localizedDescription)
            }
        }
        .onAppear {
            let isDeviceKeyEnabled = SettingsManager.shared.isEncryptionEnabled
            encryptionMode = isDeviceKeyEnabled ? .deviceKey : .passphrase

            let didHydrateStoredPassphrase = hydrateStoredPassphrase()
            if !didHydrateStoredPassphrase {
                isPassphraseEditorExpanded = true
            } else if !BackupProtectionDisclosureStore.hasStoredPreference {
                collapseProtectionIfConfigured()
            }

            Task { await refreshStatusIfNeeded() }

            if let url = appState.pendingIncomingBackupURL {
                appState.pendingIncomingBackupURL = nil
                Task { await importBackupFile(from: url) }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                if encryptionMode == .passphrase {
                    Button(BackupL10n.tr("common.done", fallback: "Done")) {
                        confirmPassphraseIfPossible()
                    }
                }
            }
        }
        .onChange(of: passphrase) { _, _ in
            guard !shouldIgnorePassphraseStateChange() else { return }
            isPassphraseConfirmed = false
            isPassphraseEditorExpanded = true
        }
        .onChange(of: passphraseConfirmation) { _, _ in
            guard !shouldIgnorePassphraseStateChange() else { return }
            isPassphraseConfirmed = false
            isPassphraseEditorExpanded = true
        }
        .onChange(of: appState.pendingIncomingBackupURL) { _, url in
            guard let url else { return }
            appState.pendingIncomingBackupURL = nil
            Task { await importBackupFile(from: url) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(BackupL10n.tr("backup.screen.title", fallback: "Backup"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
            Text(BackupL10n.tr("backup.screen.subtitle", fallback: "Protect your data, restore it quickly, and keep manual versions before risky changes"))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
    }

    private func overviewCard(availableWidth: CGFloat) -> some View {
        FinancesGlassCard(
            accentColor: AppColors.brandPrimary,
            cornerRadius: 22,
            contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        statusPill(
                            title: isBackupOperational
                                ? BackupL10n.tr("backup.status.on", fallback: "On")
                                : (appState.isBackupEnabled
                                    ? BackupL10n.tr("backup.status.not_ready", fallback: "Not ready")
                                    : BackupL10n.tr("backup.status.off", fallback: "Off")),
                            icon: isBackupOperational ? "checkmark.circle.fill" : (appState.isBackupEnabled ? "icloud.slash.fill" : "pause.circle.fill"),
                            color: isBackupOperational ? AppColors.toggleOnGreen : AppColors.warning
                        )

                        Text(dashboardContent.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(dashboardContent.subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Toggle("", isOn: Binding(
                        get: { appState.isBackupEnabled },
                        set: { newValue in
                            appState.isBackupEnabled = newValue
                            SettingsManager.shared.isBackupEnabled = newValue

                            if newValue {
                                appState.isAutoBackupEnabled = true
                                SettingsManager.shared.isAutoBackupEnabled = true
                            } else {
                                appState.isICloudAvailable = false
                                appState.lastBackupDate = nil
                                backupVersions = []
                                isVersionsExpanded = false
                                selectedRestoreRecordName = nil
                            }

                            Task { await refreshStatusIfNeeded(force: true) }
                        }
                    ))
                    .tint(AppColors.toggleOnGreen)
                    .labelsHidden()
                    .disabled(isBusy)
                }

                if BackupManagementLayout.shouldStackMetrics(availableWidth: availableWidth) {
                    VStack(spacing: 10) {
                        storageMetricTile
                        lastBackupMetricTile
                    }
                } else {
                    HStack(spacing: 10) {
                        storageMetricTile
                        lastBackupMetricTile
                    }
                }

                Text(primaryStatusLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                autoBackupToggleRow
            }
        }
    }

    private var protectionCard: some View {
        FinancesGlassCard(accentColor: AppColors.financesGradient.first ?? .cyan, cornerRadius: 22) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.toggleOnGreen)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(dashboardContent.trustTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            if isProtectionExpanded || !isProtectionConfigured {
                                Text(protectionHeadline)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppColors.brandPrimary)
                                Text(dashboardContent.trustDetail)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 8)

                        if isProtectionConfigured {
                            Button {
                                isProtectionExpanded.toggle()
                                BackupProtectionDisclosureStore.save(isProtectionExpanded)
                            } label: {
                                Image(systemName: isProtectionExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppColors.textTertiary)
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !isProtectionExpanded && isProtectionConfigured {
                        Text(protectionCollapsedSummary)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(BackupEncryptionMode.allCases) { mode in
                                protectionModeRow(mode: mode)
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
                .onChange(of: encryptionMode) { _, newValue in
                    switch newValue {
                    case .deviceKey:
                        SettingsManager.shared.isEncryptionEnabled = true
                        focusedField = nil
                        collapseProtectionIfConfigured()
                    case .passphrase:
                        SettingsManager.shared.isEncryptionEnabled = false
                        if !hydrateStoredPassphrase() {
                            isPassphraseEditorExpanded = true
                            isProtectionExpanded = true
                            BackupProtectionDisclosureStore.save(true)
                        }
                    }
                }

                if encryptionMode == .passphrase && isProtectionExpanded {
                    FinancesRowDivider()

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(BackupL10n.tr("backup.passphrase.section.title", fallback: "Your passphrase"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(
                                    hasConfirmedPassphrase && !isPassphraseEditorExpanded
                                        ? BackupL10n.tr("backup.passphrase.section.subtitle.confirmed", fallback: "Ready for backup and restore")
                                        : BackupL10n.tr("backup.passphrase.section.subtitle.input", fallback: "Create it once, then reuse it")
                                )
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            if hasConfirmedPassphrase {
                                Button(BackupL10n.tr("backup.passphrase.edit", fallback: "Edit")) {
                                    isPassphraseEditorExpanded = true
                                    focusedField = .passphrase
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.brandPrimary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                        Text(passphraseHelperText)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 8)

                        if hasConfirmedPassphrase && !isPassphraseEditorExpanded {
                            passphraseCollapsedSummary
                                .padding(.horizontal, 14)
                                .padding(.bottom, 12)
                        } else {
                            HStack(spacing: 12) {
                                Image(systemName: "key.fill")
                                    .foregroundStyle(AppColors.textTertiary)

                                Group {
                                    if isPassphraseVisible {
                                        TextField(BackupL10n.tr("backup.passphrase.placeholder", fallback: "Passphrase"), text: $passphrase)
                                    } else {
                                        SecureField(BackupL10n.tr("backup.passphrase.placeholder", fallback: "Passphrase"), text: $passphrase)
                                            .textContentType(.newPassword)
                                            .privacySensitive()
                                    }
                                }
                                .foregroundStyle(AppColors.textPrimary)
                                .focused($focusedField, equals: .passphrase)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .confirmation
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
                            .padding(.horizontal, 14)

                            FinancesRowDivider(leadingPadding: 14)

                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundStyle(AppColors.textTertiary)
                                SecureField(BackupL10n.tr("backup.passphrase.confirm_placeholder", fallback: "Repeat passphrase"), text: $passphraseConfirmation)
                                    .textContentType(.newPassword)
                                    .privacySensitive()
                                    .disabled(!appState.isBackupEnabled || isBusy)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .focused($focusedField, equals: .confirmation)
                                    .submitLabel(.done)
                                    .onSubmit {
                                        confirmPassphraseIfPossible()
                                    }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)

                            HStack(spacing: 10) {
                                Button {
                                    confirmPassphraseIfPossible()
                                } label: {
                                    Text(BackupL10n.tr("backup.passphrase.save", fallback: "Save passphrase"))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(Color.white.opacity(0.08))
                                        )
                                }
                                .buttonStyle(.plain)

                                if !trimmedPassphrase.isEmpty || !trimmedConfirmation.isEmpty {
                                    Text(
                                        isPassphraseValid
                                            ? BackupL10n.tr("backup.passphrase.hint.valid", fallback: "Looks good, this will be used for backup and restore")
                                            : BackupL10n.tr("backup.passphrase.hint.invalid", fallback: "Both fields should match")
                                    )
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(isPassphraseValid ? AppColors.textSecondary : AppColors.error)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                        }
                    }
                }
            }
        }
    }

    private func actionsCard(availableWidth: CGFloat) -> some View {
        FinancesGlassCard(accentColor: AppColors.brandPrimary, cornerRadius: 22, contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isActionsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(BackupL10n.tr("backup.actions.title", fallback: "Backup actions"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)

                        Spacer()

                        Image(systemName: isActionsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isActionsExpanded {
                    primaryActionButton(
                        title: createButtonTitle,
                        subtitle: createSliderSubtitle,
                        icon: "arrow.clockwise.circle.fill",
                        isEnabled: canCreateBackup || hasReachedPinnedVersionLimit
                    ) {
                        Task { await createBackupNow() }
                    }

                    if appState.isAutoBackupEnabled {
                        Text(BackupL10n.tr("backup.actions.auto_schedule.note", fallback: "One automatic backup is refreshed every 24 hours"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if BackupManagementLayout.shouldStackActionButtons(availableWidth: availableWidth) {
                        VStack(spacing: 10) {
                            exportActionButton
                            importActionButton
                        }
                    } else {
                        HStack(spacing: 10) {
                            exportActionButton
                            importActionButton
                        }
                    }

                    if let primaryActionHint {
                        Text(primaryActionHint)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(primaryActionHint == BackupL10n.tr("backup.hint.passphrase_mismatch", fallback: "Passphrases do not match") ? AppColors.error : AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if hasReachedPinnedVersionLimit, let oldestPinnedVersion {
                        subtleCallout(
                            title: BackupL10n.format(
                                "backup.limit.reached.title",
                                fallback: "Maximum of %lld manual versions reached",
                                maxManualVersionCount
                            ),
                            text: BackupL10n.tr("backup.limit.reached.message", fallback: "Delete one manual version and try again")
                        )

                        compactActionButton(
                            title: BackupL10n.tr("backup.limit.reached.action.delete_oldest", fallback: "Delete oldest version"),
                            icon: "trash",
                            isEnabled: deletingRecordName == nil && !isBusy
                        ) {
                            Task { await deleteVersion(recordName: oldestPinnedVersion.recordName) }
                        }
                    }
                }
            }
        }
    }

    private var versionsCard: some View {
        FinancesGlassCard(cornerRadius: 20, contentPadding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVersionsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BackupL10n.tr("backup.versions.title", fallback: "Versions"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(backupVersions.isEmpty
                                ? BackupL10n.tr("backup.versions.empty.short", fallback: "Nothing saved yet")
                                : BackupL10n.format("backup.versions.count_format", fallback: "%lld", backupVersions.count)
                            )
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: isVersionsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isVersionsExpanded {
                    if backupVersions.isEmpty {
                        Text(BackupL10n.tr("backup.versions.empty.full", fallback: "Create your first backup above, the daily automatic copy will also appear here"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(backupVersions.enumerated()), id: \.element.id) { index, version in
                                if index > 0 {
                                    FinancesRowDivider()
                                }

                                let isSelected = selectedRestoreRecordName == version.recordName

                                VStack(spacing: 0) {
                                    HStack(spacing: 10) {
                                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(AppColors.brandPrimary)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(version.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(AppColors.textPrimary)

                                            Text(
                                                String(
                                                    format: String(localized: "restore.version_size_format"),
                                                    ByteCountFormatter.string(fromByteCount: version.size, countStyle: .file),
                                                    String(version.version)
                                                )
                                            )
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundStyle(AppColors.textTertiary)
                                        }

                                        Spacer()

                                        Text(
                                            version.isPinned
                                                ? BackupL10n.tr("backup.versions.pinned", fallback: "Saved")
                                                : BackupL10n.tr("backup.versions.auto", fallback: "Auto")
                                        )
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background((version.isPinned ? AppColors.toggleOnGreen : AppColors.brandPrimary).opacity(0.25))
                                        .clipShape(Capsule())

                                        Button(role: .destructive) {
                                            Task { await deleteVersion(recordName: version.recordName) }
                                        } label: {
                                            if deletingRecordName == version.recordName {
                                                ProgressView()
                                                    .scaleEffect(0.75)
                                            } else {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 13, weight: .semibold))
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(isBusy || deletingRecordName != nil)
                                    }
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            selectedRestoreRecordName = version.recordName
                                        }
                                    }

                                    if isSelected {
                                        compactActionButton(
                                            title: BackupL10n.tr("backup.restore.action.short", fallback: "Restore this version"),
                                            icon: "arrow.down.circle.fill",
                                            isEnabled: canRestoreSelectedVersion
                                        ) {
                                            showRestoreConfirmation = true
                                        }
                                        .padding(.bottom, 8)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    @MainActor
    private func refreshStatusIfNeeded(force: Bool = false) async {
        guard BackupStatusRefreshPolicy.shouldSkipManagementRefresh(
            force: force,
            isBackupEnabled: appState.isBackupEnabled,
            isICloudAvailable: appState.isICloudAvailable,
            lastBackupDate: appState.lastBackupDate,
            loadedVersionCount: backupVersions.count
        ) == false else {
            return
        }

        backupError = nil

        let cloudStore = CloudBackupStore()
        appState.isICloudAvailable = await cloudStore.isAvailable()

        guard appState.isICloudAvailable, let backupManager else { return }
        backupVersions = await backupManager.listBackupVersions()
        appState.lastBackupDate = backupVersions.first?.date

        if selectedRestoreRecordName == nil || backupVersions.contains(where: { $0.recordName == selectedRestoreRecordName }) == false {
            selectedRestoreRecordName = backupVersions.first?.recordName
        }

        if !backupVersions.isEmpty && !isVersionsExpanded {
            withAnimation(.easeInOut(duration: 0.2)) {
                isVersionsExpanded = true
            }
        }
    }

    @MainActor
    private func createBackupNow() async {
        guard let backupManager else {
            backupError = .iCloudUnavailable
            return
        }
        guard hasReachedPinnedVersionLimit == false else {
            isActionsExpanded = true
            isVersionsExpanded = true
            backupError = .backupFailed(
                BackupL10n.format(
                    "backup.actions.create.subtitle.limit",
                    fallback: "Maximum of %lld manual versions reached, delete one old version to save a new one",
                    maxManualVersionCount
                )
            )
            return
        }

        isBusy = true
        backupError = nil
        defer { isBusy = false }

        do {
            focusedField = nil
            switch encryptionMode {
            case .passphrase:
                try await backupManager.saveVersionNow(passphrase: trimmedPassphrase.isEmpty ? nil : trimmedPassphrase)
            case .deviceKey:
                try await backupManager.saveVersionNow(passphrase: nil)
            }
            await refreshStatusIfNeeded(force: true)
        } catch let appError as AppError {
            backupError = appError
        } catch {
            backupError = .unknown(error)
        }
    }

    @MainActor
    private func restoreSelectedVersion() async {
        guard let backupManager, let selectedRestoreRecordName else {
            backupError = .restoreFailed(BackupL10n.tr("backup.hint.select_restore_version", fallback: "Select a version to restore"))
            return
        }

        isBusy = true
        backupError = nil
        defer { isBusy = false }

        do {
            focusedField = nil
            let passphraseToUse = trimmedPassphrase.isEmpty ? nil : trimmedPassphrase
            try await backupManager.restoreVersion(recordName: selectedRestoreRecordName, passphrase: passphraseToUse)
            await refreshStatusIfNeeded(force: true)
            showRestoreSuccessPrompt = true
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

    @MainActor
    private func exportSelectedVersion() async {
        guard let backupManager, let selectedRestoreRecordName else {
            backupError = .backupFailed(BackupL10n.tr("backup.hint.select_restore_version", fallback: "Select a version to restore"))
            return
        }

        isBusy = true
        backupError = nil

        do {
            let payload = try await backupManager.exportVersion(recordName: selectedRestoreRecordName)
            exportDocument = BackupTransferFileDocument(data: payload.data)
            exportFilename = payload.fileName
            isBusy = false
            isExportingVersion = true
        } catch let appError as AppError {
            isBusy = false
            backupError = appError
        } catch {
            isBusy = false
            backupError = .unknown(error)
        }
    }

    @MainActor
    private func importBackupFile(from url: URL) async {
        guard let backupManager else {
            backupError = .iCloudUnavailable
            return
        }

        isBusy = true
        backupError = nil
        defer { isBusy = false }

        let didAccessScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let importedVersion = try await backupManager.importVersion(from: data)
            selectedRestoreRecordName = importedVersion.recordName
            isVersionsExpanded = true
            await refreshStatusIfNeeded(force: true)
        } catch let appError as AppError {
            backupError = appError
        } catch {
            backupError = .backupFailed(error.localizedDescription)
        }
    }

    private func formattedBackupDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(AppLocalization.currentAppLocale)
        )
    }

    @discardableResult
    private func hydrateStoredPassphrase() -> Bool {
        guard let stored = BackupPassphraseStore.load(), !stored.isEmpty else {
            hydratedStoredPassphrase = nil
            return false
        }

        isHydratingStoredPassphrase = true
        hydratedStoredPassphrase = stored
        passphrase = stored
        passphraseConfirmation = stored
        isPassphraseConfirmed = true
        isPassphraseEditorExpanded = false
        Task { @MainActor in
            hydratedStoredPassphrase = nil
            isHydratingStoredPassphrase = false
        }
        return true
    }

    private func confirmPassphraseIfPossible() {
        guard isPassphraseValid else { return }
        isPassphraseConfirmed = true
        isPassphraseEditorExpanded = false
        focusedField = nil
        _ = BackupPassphraseStore.save(trimmedPassphrase)
        collapseProtectionIfConfigured()
    }

    private func shouldIgnorePassphraseStateChange() -> Bool {
        if isHydratingStoredPassphrase {
            return true
        }

        guard let hydratedStoredPassphrase else {
            return false
        }

        return passphrase == hydratedStoredPassphrase && passphraseConfirmation == hydratedStoredPassphrase
    }

    private func collapseProtectionIfConfigured() {
        guard isProtectionConfigured else { return }
        isProtectionExpanded = false
        BackupProtectionDisclosureStore.save(false)
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
    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.localizedUppercase)
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

    private var storageMetricTile: some View {
        metricTile(
            title: BackupL10n.tr("backup.metrics.storage", fallback: "Where"),
            value: appState.isBackupEnabled
                ? (appState.isICloudAvailable
                    ? BackupL10n.tr("backup.storage.icloud", fallback: "iCloud")
                    : BackupL10n.tr("backup.storage.unavailable", fallback: "Unavailable"))
                : BackupL10n.tr("backup.storage.local", fallback: "Local")
        )
    }

    private var lastBackupMetricTile: some View {
        metricTile(
            title: BackupL10n.tr("backup.metrics.last", fallback: "Last"),
            value: formattedBackupDate(appState.lastBackupDate) ?? BackupL10n.tr("backup.metrics.last.none", fallback: "None yet")
        )
    }

    private var autoBackupToggleRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(BackupL10n.tr("backup.auto_toggle.title", fallback: "Daily auto backup"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isAutoBackupOptionsExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isAutoBackupOptionsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }

                if isAutoBackupOptionsExpanded {
                    Text(
                        BackupL10n.tr(
                            "backup.auto_toggle.subtitle",
                            fallback: "Keeps one auto backup per day and replaces the previous one"
                        )
                    )
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Toggle(
                "",
                isOn: Binding(
                    get: { appState.isAutoBackupEnabled },
                    set: { newValue in
                        appState.isAutoBackupEnabled = newValue
                        SettingsManager.shared.isAutoBackupEnabled = newValue
                    }
                )
            )
            .tint(AppColors.toggleOnGreen)
            .labelsHidden()
            .disabled(!appState.isBackupEnabled || isBusy)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func subtleCallout(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func protectionModeRow(mode: BackupEncryptionMode) -> some View {
        let isSelected = encryptionMode == mode
        Button {
            encryptionMode = mode
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? AppColors.brandPrimary : AppColors.textTertiary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(mode.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)

                        if mode == preferredMode {
                            Text(BackupL10n.tr("backup.protection.recommended", fallback: "Recommended"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppColors.brandPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.brandPrimary.opacity(0.16), in: Capsule())
                        }
                    }

                    Text(mode.summary)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(mode.restoreRisk)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(mode == .passphrase ? AppColors.textTertiary : AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.09) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? AppColors.brandPrimary.opacity(0.55) : Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!appState.isBackupEnabled || isBusy)
    }

    @ViewBuilder
    private func primaryActionButton(
        title: String,
        subtitle: String,
        icon: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isEnabled ? AppColors.textPrimary : AppColors.textTertiary)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(isEnabled ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isEnabled ? AppColors.textPrimary : AppColors.textTertiary)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if isBusy {
                    ProgressView()
                        .tint(AppColors.textPrimary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isEnabled ? AppColors.textTertiary : AppColors.textTertiary.opacity(0.7))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isEnabled ? 0.08 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
    }

    @ViewBuilder
    private func compactActionButton(title: String, icon: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isEnabled ? AppColors.textPrimary : AppColors.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isEnabled ? 0.08 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var exportActionButton: some View {
        compactActionButton(
            title: BackupL10n.tr("backup.actions.export.title", fallback: "Export selected"),
            icon: "square.and.arrow.up",
            isEnabled: canExportSelectedVersion
        ) {
            Task { await exportSelectedVersion() }
        }
    }

    private var importActionButton: some View {
        compactActionButton(
            title: BackupL10n.tr("backup.actions.import.title", fallback: "Import file"),
            icon: "square.and.arrow.down",
            isEnabled: canImportVersion
        ) {
            isImportingVersion = true
        }
    }

    private var passphraseCollapsedSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.toggleOnGreen)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(BackupL10n.tr("backup.passphrase.summary.title", fallback: "Saved"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(BackupL10n.tr("backup.passphrase.summary.subtitle", fallback: "Used for backup and restore, change it only if needed"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private enum BackupPassphraseStore {
    private static let service = "com.millio.backup"
    private static let account = "backup_passphrase_v1"

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ passphrase: String) -> Bool {
        guard let data = passphrase.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            return SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecSuccess
        }

        var newQuery = query
        newQuery[kSecValueData as String] = data
        return SecItemAdd(newQuery as CFDictionary, nil) == errSecSuccess
    }
}

private enum BackupProtectionDisclosureStore {
    private static let key = "backup.protectionDisclosureExpanded"

    static var hasStoredPreference: Bool {
        UserDefaults.standard.object(forKey: key) != nil
    }

    static func load(defaultValue: Bool = true) -> Bool {
        let defaults = UserDefaults.standard
        guard hasStoredPreference else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    static func save(_ isExpanded: Bool) {
        UserDefaults.standard.set(isExpanded, forKey: key)
    }
}
