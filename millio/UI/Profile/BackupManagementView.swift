//
//  BackupManagementView.swift
//  millio
//
//  Created by Александр Сидоркин on 30.01.2026.
//

import Security
import SwiftUI

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
    @State private var encryptionMode: BackupEncryptionMode = .deviceKey
    @State private var backupVersions: [BackupVersionInfo] = []
    @State private var deletingRecordName: String?
    @State private var isVersionsExpanded = false
    @State private var selectedRestoreRecordName: String?
    @State private var showRestoreConfirmation = false
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

    private var isBackupOperational: Bool {
        appState.isBackupEnabled && appState.isICloudAvailable
    }

    private var canCreateBackup: Bool {
        isBackupOperational && !isBusy && deletingRecordName == nil && isPassphraseReadyForBackup
    }

    private var canRestoreSelectedVersion: Bool {
        isBackupOperational
            && selectedRestoreRecordName != nil
            && !isBusy
            && deletingRecordName == nil
            && (encryptionMode != .passphrase || !trimmedPassphrase.isEmpty)
    }

    private var selectedRestoreVersion: BackupVersionInfo? {
        guard let selectedRestoreRecordName else { return nil }
        return backupVersions.first(where: { $0.recordName == selectedRestoreRecordName })
    }

    private var createSliderSubtitle: String {
        if isBusy {
            return "Операция уже выполняется"
        }
        if !isBackupOperational {
            return "Нужно включить backup и iCloud"
        }
        return "Защита от случайного запуска"
    }

    private var restoreSliderTitle: String {
        selectedRestoreVersion == nil ? "Выберите версию для восстановления" : "Сдвиньте, чтобы восстановить выбранную версию"
    }

    private var restoreSliderSubtitle: String {
        guard let selectedRestoreVersion else {
            return "Сначала выберите версию в списке ниже"
        }
        return selectedRestoreVersion.date.formatted(date: .abbreviated, time: .shortened)
    }

    private var primaryActionHint: String? {
        guard appState.isBackupEnabled else {
            return "Включите резервное копирование."
        }
        guard appState.isICloudAvailable else {
            return "Нужен доступ к iCloud."
        }
        guard encryptionMode != .passphrase || !trimmedPassphrase.isEmpty else {
            return "Введите кодовую фразу."
        }
        guard encryptionMode != .passphrase || trimmedPassphrase == trimmedConfirmation else {
            return "Кодовые фразы не совпадают."
        }
        guard encryptionMode != .passphrase || isPassphraseConfirmed else {
            return "Нажмите «Готово», чтобы подтвердить фразу."
        }
        guard selectedRestoreRecordName != nil else {
            return "Выберите версию для восстановления."
        }
        return nil
    }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    overviewCard
                    protectionCard
                    actionsCard
                    versionsCard

                    if let backupError {
                        Text(backupError.localizedDescription)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.error)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .dismissKeyboardOnTap()
            .refreshable {
                await refreshStatusIfNeeded(force: true)
            }
        }
        .confirmationDialog(
            "Восстановить эту версию?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Да, восстановить", role: .destructive) {
                Task { await restoreSelectedVersion() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Текущие локальные данные будут полностью заменены выбранной копией.")
        }
        .onAppear {
            let isDeviceKeyEnabled = SettingsManager.shared.isEncryptionEnabled
            encryptionMode = isDeviceKeyEnabled ? .deviceKey : .passphrase

            if let stored = BackupPassphraseStore.load(), !stored.isEmpty {
                passphrase = stored
                passphraseConfirmation = stored
                isPassphraseConfirmed = true
            }

            Task { await refreshStatusIfNeeded() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                if encryptionMode == .passphrase {
                    Button("Готово") {
                        confirmPassphraseIfPossible()
                    }
                }
            }
        }
        .onChange(of: passphrase) { _, _ in
            isPassphraseConfirmed = false
        }
        .onChange(of: passphraseConfirmation) { _, _ in
            isPassphraseConfirmed = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Резервная копия")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
            Text("Включите backup, задайте защиту, затем создавайте и восстанавливайте копии.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
    }

    private var overviewCard: some View {
        FinancesGlassCard(
            accentColor: AppColors.brandPrimary,
            cornerRadius: 22,
            contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        statusPill(
                            title: isBackupOperational ? "Включено" : (appState.isBackupEnabled ? "Не готово" : "Выключено"),
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

                            if !newValue {
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

                HStack(spacing: 10) {
                    metricTile(
                        title: "Хранение",
                        value: appState.isBackupEnabled ? (appState.isICloudAvailable ? "iCloud" : "Недоступно") : "Локально"
                    )
                    metricTile(
                        title: "Последняя",
                        value: formattedBackupDate(appState.lastBackupDate) ?? "Еще нет"
                    )
                }
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
                            Text(dashboardContent.trustDetail)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Picker("Способ защиты", selection: $encryptionMode) {
                        ForEach(BackupEncryptionMode.allCases) { mode in
                            Text(mode.shortTitle).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!appState.isBackupEnabled || isBusy)

                    subtleCallout(
                        title: encryptionMode == .passphrase ? "Важно" : "Ограничение",
                        text: encryptionMode == .passphrase
                            ? "Без фразы восстановление невозможно."
                            : "Ключ привязан к этому устройству."
                    )
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
                .onChange(of: encryptionMode) { _, newValue in
                    switch newValue {
                    case .deviceKey:
                        SettingsManager.shared.isEncryptionEnabled = true
                        isPassphraseConfirmed = false
                        focusedField = nil
                    case .passphrase:
                        SettingsManager.shared.isEncryptionEnabled = false
                    }
                }

                if encryptionMode == .passphrase {
                    FinancesRowDivider()

                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Кодовая фраза")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(isPassphraseConfirmed ? "Фраза подтверждена" : "Введите и подтвердите")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            if isPassphraseConfirmed {
                                Button("Изменить") {
                                    isPassphraseConfirmed = false
                                    focusedField = .passphrase
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.brandPrimary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        if isPassphraseConfirmed {
                            passphraseConfirmedSummary
                                .padding(.horizontal, 14)
                                .padding(.bottom, 12)
                        } else {
                            HStack(spacing: 12) {
                                Image(systemName: "key.fill")
                                    .foregroundStyle(AppColors.textTertiary)

                                Group {
                                    if isPassphraseVisible {
                                        TextField("Кодовая фраза", text: $passphrase)
                                    } else {
                                        SecureField("Кодовая фраза", text: $passphrase)
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
                                SecureField("Повторите кодовую фразу", text: $passphraseConfirmation)
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
                                    Text("Готово")
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
                                    Text(isPassphraseValid ? "Фраза будет сохранена и можно будет менять." : "Введите одинаковую фразу в оба поля.")
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

    private var actionsCard: some View {
        FinancesGlassCard(accentColor: AppColors.brandPrimary, cornerRadius: 22, contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Действия")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)

                SlideToConfirmControl(
                    title: "Сдвиньте, чтобы создать копию",
                    subtitle: createSliderSubtitle,
                    icon: "arrow.up",
                    gradientColors: AppColors.financesGradient,
                    isEnabled: canCreateBackup,
                    isLoading: isBusy
                ) {
                    Task { await createBackupNow() }
                }

                SlideToConfirmControl(
                    title: restoreSliderTitle,
                    subtitle: restoreSliderSubtitle,
                    icon: "arrow.down",
                    gradientColors: AppColors.financesGradient,
                    isEnabled: canRestoreSelectedVersion,
                    isLoading: isBusy
                ) {
                    showRestoreConfirmation = true
                }

                if let primaryActionHint {
                    Text(primaryActionHint)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(primaryActionHint == "Кодовые фразы не совпадают." ? AppColors.error : AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                            Text("Сохраненные версии")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(backupVersions.isEmpty ? "Пока нет" : "\(backupVersions.count) шт.")
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
                        Text("Сохраненных версий пока нет.")
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

                                HStack(spacing: 10) {
                                    Image(systemName: selectedRestoreRecordName == version.recordName ? "largecircle.fill.circle" : "circle")
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

                                    if version.isPinned {
                                        Text("Закреплено")
                                            .font(.system(size: 10, weight: .semibold))
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
                                    selectedRestoreRecordName = version.recordName
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
        guard appState.isBackupEnabled else { return }
        if !force, appState.isICloudAvailable, appState.lastBackupDate != nil { return }

        backupError = nil

        let cloudStore = CloudBackupStore()
        appState.isICloudAvailable = await cloudStore.isAvailable()

        guard appState.isICloudAvailable, let backupManager else { return }
        backupVersions = await backupManager.listBackupVersions()
        appState.lastBackupDate = backupVersions.first?.date

        if selectedRestoreRecordName == nil || backupVersions.contains(where: { $0.recordName == selectedRestoreRecordName }) == false {
            selectedRestoreRecordName = backupVersions.first?.recordName
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
            focusedField = nil
            switch encryptionMode {
            case .passphrase:
                try await backupManager.backupNow(passphrase: trimmedPassphrase.isEmpty ? nil : trimmedPassphrase)
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
    private func restoreSelectedVersion() async {
        guard let backupManager, let selectedRestoreRecordName else {
            backupError = .restoreFailed("Выберите версию для восстановления")
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

    private func formattedBackupDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func confirmPassphraseIfPossible() {
        guard isPassphraseValid else { return }
        isPassphraseConfirmed = true
        focusedField = nil
        _ = BackupPassphraseStore.save(trimmedPassphrase)
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

    private var passphraseConfirmedSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.toggleOnGreen)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Кодовая фраза готова")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("Фраза сохранена. Можно изменить в любой момент.")
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
