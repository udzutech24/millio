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
/// `AppState` и блокировало шиты импорта выписок (`RootTabView`). Поэтому URL потребляется синхронно,
/// до любого `await`, на всех ветках выхода — но ТОЛЬКО когда приложение готово его обработать
/// (см. `IncomingBackupFileIntake`).
@MainActor
struct IncomingBackupFileRestoreModifier: ViewModifier {
    let appState: AppState
    /// Передаётся ЯВНО, а не через `@Environment(\.diContainer)`: модификатор навешен на корень сцены
    /// СНАРУЖИ `.environment(\.diContainer, …)`, поэтому из окружения он читал бы вечный nil —
    /// восстановление из файла на любом экране отвечало бы «iCloud недоступен».
    let backupManager: BackupManagerProtocol?

    @State private var pending: PendingBackupFile?
    @State private var isRestoring = false
    @State private var alert: RestoreAlert?

    private var isReady: Bool { backupManager != nil }

    private var intake: IncomingBackupFileIntake {
        IncomingBackupFileIntake(appState: appState, backupManager: backupManager)
    }

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
            .onChange(of: isReady) { _, ready in
                // Второй триггер: файл дождался готовности DI (холодный старт из Files).
                guard ready, let url = appState.pendingIncomingBackupURL else { return }
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
        switch await intake.intake(url) {
        case .deferredUntilReady:
            // URL остаётся в AppState — обработаем, как только появится backupManager.
            break
        case .prepared(let file):
            pending = file
        case .failed(let message):
            alert = .failure(message)
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
            alert = .failure(RestoreErrorPresenter.userMessage(for: error))
        }
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
    func incomingBackupFileRestore(
        appState: AppState,
        backupManager: BackupManagerProtocol?
    ) -> some View {
        modifier(IncomingBackupFileRestoreModifier(appState: appState, backupManager: backupManager))
    }
}
