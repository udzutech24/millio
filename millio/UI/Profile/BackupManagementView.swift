//
//  BackupManagementView.swift
//  millio
//
//  Created by Александр Сидоркин on 30.01.2026.
//

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

    private var canCreateBackup: Bool {
        appState.isBackupEnabled && appState.isICloudAvailable && !isBusy && deletingRecordName == nil && isPassphraseReadyForBackup
    }

    private var readinessColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10, alignment: .top),
            GridItem(.flexible(), spacing: 10, alignment: .top)
        ]
    }

    private var isPassphraseReadyForBackup: Bool {
        encryptionMode != .passphrase || (isPassphraseValid && isPassphraseConfirmed)
    }

    private var primaryActionHint: String? {
        guard appState.isBackupEnabled else {
            return "Включите резервное копирование."
        }
        guard appState.isICloudAvailable else {
            return "Без iCloud новые копии не создаются."
        }
        guard encryptionMode != .passphrase || !trimmedPassphrase.isEmpty else {
            return "Задайте кодовую фразу для переноса."
        }
        guard encryptionMode != .passphrase || trimmedPassphrase == trimmedConfirmation else {
            return "Кодовые фразы не совпадают."
        }
        guard encryptionMode != .passphrase || isPassphraseConfirmed else {
            return "Нажмите «Готово», чтобы подтвердить фразу."
        }
        return nil
    }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(spacing: 16) {
                    header
                    heroCard
                    protectionCard
                    actionsCard
                    readinessCard
                    versionsCard

                    if let backupError {
                        Text(backupError.localizedDescription)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.immediately)
            .dismissKeyboardOnTap()
            .refreshable {
                await refreshStatusIfNeeded(force: true)
            }
        }
        .onAppear {
            let isDeviceKeyEnabled = SettingsManager.shared.isEncryptionEnabled
            encryptionMode = isDeviceKeyEnabled ? .deviceKey : .passphrase
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
            Text("Где лежат данные и можно ли их восстановить.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 18)
    }

    private var heroCard: some View {
        FinancesGlassCard(
            accentColor: AppColors.brandPrimary,
            cornerRadius: 24,
            contentPadding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        statusPill(
                            title: appState.isBackupEnabled ? "Включено" : "Выключено",
                            icon: appState.isBackupEnabled ? "checkmark.circle.fill" : "pause.circle.fill",
                            color: appState.isBackupEnabled ? AppColors.toggleOnGreen : AppColors.warning
                        )

                        Text(dashboardContent.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)

                        Text(dashboardContent.subtitle)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

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

                            Task { await refreshStatusIfNeeded(force: true) }
                        }
                    ))
                    .tint(AppColors.toggleOnGreen)
                    .labelsHidden()
                    .disabled(isBusy)
                }

                HStack(spacing: 12) {
                    metricTile(
                        title: "Хранение",
                        value: appState.isBackupEnabled ? (appState.isICloudAvailable ? "iCloud" : "Недоступно") : "Локально"
                    )
                    metricTile(
                        title: "Последняя копия",
                        value: formattedBackupDate(appState.lastBackupDate) ?? "Еще нет"
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(dashboardContent.storageTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(dashboardContent.storageDetail)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var protectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Защита")

            FinancesGlassCard(accentColor: AppColors.financesGradient.first ?? .cyan, cornerRadius: 24) {
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

                        Text("Способ защиты")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)

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
                                ? "Фраза хранится только у вас. Потеряете ее, восстановление будет недоступно."
                                : "Ключ остается на этом устройстве. Перенос на новый iPhone может не сработать."
                        )

                        Text(encryptionMode.summary + " " + encryptionMode.restoreRisk)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)
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
                                    Text("Кодовая фраза для восстановления")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text(isPassphraseConfirmed ? "Фраза подтверждена. Можно создавать копию." : "Введите фразу и нажмите «Готово».")
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
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 10)

                            if isPassphraseConfirmed {
                                passphraseConfirmedSummary
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 14)
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
                                .padding(.vertical, 13)
                                .padding(.horizontal, 16)

                                FinancesRowDivider(leadingPadding: 16)

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
                                .padding(.vertical, 13)
                                .padding(.horizontal, 16)

                                HStack(spacing: 10) {
                                    Button {
                                        confirmPassphraseIfPossible()
                                    } label: {
                                        Text("Готово")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppColors.textPrimary)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(Color.white.opacity(0.08))
                                            )
                                    }
                                    .buttonStyle(.plain)

                                    if !trimmedPassphrase.isEmpty || !trimmedConfirmation.isEmpty {
                                        Text(isPassphraseValid ? "После подтверждения поля свернутся." : "Введите одинаковую фразу в оба поля.")
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(isPassphraseValid ? AppColors.textSecondary : AppColors.error)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 14)
                            }
                        }
                    }
                }
            }
        }
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Действия")

            VStack(spacing: 10) {
                SlideToConfirmControl(
                    title: "Сдвиньте, чтобы создать копию",
                    subtitle: isBusy ? "Создание уже запущено" : "Защита от случайного запуска",
                    icon: "arrow.right",
                    gradientColors: AppColors.financesGradient,
                    isEnabled: canCreateBackup,
                    isLoading: isBusy
                ) {
                    Task { await createBackupNow() }
                }

                HStack(spacing: 12) {
                    Button {
                        Task { await savePinnedVersionNow() }
                    } label: {
                        compactActionTile(
                            icon: isBusy ? "hourglass" : "pin.fill",
                            title: "Сохранить копию",
                            subtitle: "Оставить как версию"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canCreateBackup)
                    .opacity(canCreateBackup ? 1 : 0.45)

                    Button {
                        Task { await refreshStatusIfNeeded(force: true) }
                    } label: {
                        compactActionTile(
                            icon: "arrow.clockwise",
                            title: "Проверить iCloud",
                            subtitle: "Обновить статус"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                }

                NavigationLink {
                    RestoreView(appState: appState, router: router)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.brandPrimary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Восстановить данные")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            Text("Выберите копию и замените локальные данные.")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                if let primaryActionHint {
                    Text(primaryActionHint)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(primaryActionHint == "Кодовые фразы не совпадают." ? AppColors.error : AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Готовность")

            LazyVGrid(columns: readinessColumns, spacing: 10) {
                ForEach(dashboardContent.readiness) { item in
                    FinancesGlassCard(accentColor: item.isComplete ? AppColors.toggleOnGreen : AppColors.brandPrimary, cornerRadius: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle.dashed")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(item.isComplete ? AppColors.toggleOnGreen : AppColors.textTertiary)

                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(item.detail)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                        .padding(14)
                    }
                }
            }
        }
    }

    private var versionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Сохраненные копии")

            FinancesGlassCard {
                if backupVersions.isEmpty {
                    Text("Сохраненных копий пока нет")
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
                                    Text("Закреплено")
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
    private func savePinnedVersionNow() async {
        guard let backupManager else {
            backupError = .iCloudUnavailable
            return
        }

        isBusy = true
        backupError = nil
        defer { isBusy = false }

        do {
            focusedField = nil
            try await backupManager.saveVersionNow(
                passphrase: encryptionMode == .passphrase ? (trimmedPassphrase.isEmpty ? nil : trimmedPassphrase) : nil
            )
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func subtleCallout(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            Text(text)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var passphraseConfirmedSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.toggleOnGreen)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Кодовая фраза готова")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("Будет использована для этой копии. Millio ее не сохраняет.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func compactActionTile(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.brandPrimary)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
