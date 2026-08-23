//
//  IncomingBackupFileRestore.swift
//  millio
//

import SwiftUI

/// Единственный потребитель `AppState.pendingIncomingBackupURL`: доводит файл бэкапа, открытый из
/// Files/AirDrop, до восстановления данных на ЛЮБОМ экране и при холодном старте.
///
/// Раньше потребителем был только `BackupManagementView` — файл, открытый из Files где угодно, кроме
/// экрана «Резервные копии», не доходил ни до импорта, ни до восстановления, а значение залипало в
/// `AppState` и блокировало шиты импорта выписок (`RootTabView`). Поэтому URL здесь потребляется
/// безусловно и синхронно, до любого `await`, на всех ветках выхода.
@MainActor
struct IncomingBackupFileRestoreModifier: ViewModifier {
    let appState: AppState

    @Environment(\.diContainer) private var diContainer

    @State private var pending: PendingBackupFile?
    @State private var isRestoring = false
    @State private var alert: RestoreAlert?

    private var backupManager: BackupManagerProtocol? { diContainer?.backupManager }

    func body(content: Content) -> some View {
        content
            .task {
                // Холодный старт: `onOpenURL` мог отработать до появления этого модификатора.
                if let url = appState.pendingIncomingBackupURL {
                    await handle(url)
                }
            }
            .onChange(of: appState.pendingIncomingBackupURL) { _, url in
                guard let url else { return }
                Task { await handle(url) }
            }
            .overlay {
                if isRestoring {
                    IncomingBackupRestoreProgressOverlay()
                }
            }
            .confirmationDialog(
                BackupL10n.tr("backup.incoming_file.confirm.title", fallback: "Restore from this file?"),
                isPresented: Binding(
                    get: { pending != nil && !isRestoring },
                    set: { if !$0 { pending = nil } }
                ),
                titleVisibility: .visible,
                presenting: pending
            ) { file in
                Button(
                    BackupL10n.tr("backup.incoming_file.confirm.action", fallback: "Replace Data"),
                    role: .destructive
                ) {
                    Task { await restore(file) }
                }
                Button(BackupL10n.tr("common.cancel", fallback: "Cancel"), role: .cancel) {
                    pending = nil
                }
            } message: { file in
                Text(file.confirmationMessage)
            }
            .alert(item: $alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(BackupL10n.tr("common.ok", fallback: "OK")))
                )
            }
    }

    private func handle(_ url: URL) async {
        // Потребление ДО любого await и до любого return: `RootTabView` держит шиты выписок
        // заблокированными, пока значение != nil.
        appState.pendingIncomingBackupURL = nil

        guard let backupManager else {
            alert = .failure(AppError.iCloudUnavailable.localizedDescription)
            return
        }

        let didAccessScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            let info = try await backupManager.inspectBackupFile(data)
            pending = PendingBackupFile(data: data, info: info)
        } catch {
            alert = .failure(Self.message(for: error))
        }
    }

    private func restore(_ file: PendingBackupFile) async {
        guard let backupManager else { return }
        pending = nil
        isRestoring = true
        defer { isRestoring = false }

        do {
            let receipt = try await backupManager.restoreFromFile(file.data, passphrase: nil)
            AppLogger.log(.info, category: "App", "Restore from incoming file completed: \(receipt.diagnosticSummary)")
            appState.lifecycle = .ready
            alert = .success
        } catch {
            CrashReporting.record(error: error)
            alert = .failure(Self.message(for: error))
        }
    }

    /// Провал отката (`RestoreRollbackFailure`) — исход высшей тяжести: у пользователя нет ни старых,
    /// ни новых данных, поэтому сообщение берём как есть, не подменяя общим «не удалось восстановить».
    static func message(for error: Error) -> String {
        if let rollbackFailure = error as? RestoreRollbackFailure {
            return rollbackFailure.errorDescription ?? rollbackFailure.underlyingDescription
        }
        if let appError = error as? AppError {
            return appError.localizedDescription
        }
        return AppError.restoreFailed(error.localizedDescription).localizedDescription
    }
}

struct PendingBackupFile: Identifiable {
    let id = UUID()
    let data: Data
    let info: BackupInfo

    var confirmationMessage: String {
        let date = info.date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened)
                .locale(AppLocalization.currentAppLocale)
        )
        let size = ByteCountFormatter.string(fromByteCount: info.size, countStyle: .file)
        return BackupL10n.format(
            "backup.incoming_file.confirm.message",
            fallback: "Backup of %@ · %@. Current data on this device will be replaced.",
            date,
            size
        )
    }
}

private struct IncomingBackupRestoreProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: AppSpacing.m) {
                ProgressView()
                    .tint(AppColors.textPrimary)
                Text(BackupL10n.tr("backup.incoming_file.restoring", fallback: "Restoring from file…"))
                    .font(.millioSubheadline)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(AppSpacing.xl)
            .background(AppColors.backgroundMiddle, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct RestoreAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    static var success: RestoreAlert {
        RestoreAlert(
            title: BackupL10n.tr("backup.incoming_file.success.title", fallback: "Data Restored"),
            message: BackupL10n.tr("backup.incoming_file.success.message", fallback: "The backup file has been restored to this device.")
        )
    }

    static func failure(_ message: String) -> RestoreAlert {
        RestoreAlert(
            title: BackupL10n.tr("backup.incoming_file.failure.title", fallback: "Restore Failed"),
            message: message
        )
    }
}

extension View {
    /// Подключается ОДИН раз в корне сцены — иначе URL потребят несколько экранов сразу.
    func incomingBackupFileRestore(appState: AppState) -> some View {
        modifier(IncomingBackupFileRestoreModifier(appState: appState))
    }
}
