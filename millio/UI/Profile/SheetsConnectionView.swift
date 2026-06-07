import SwiftUI

// MARK: - SheetsConnectionView

/// Блок профиля для управления подключением к Google Таблицам.
/// Три состояния: не подключено / синхронизация / подключено.
struct SheetsConnectionView: View {

    @Environment(\.diContainer) private var diContainer
    @Environment(\.openURL) private var openURL

    @State private var status: SheetsExportStatus = .disconnected
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDisconnectConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            sectionHeader
            stateContent
        }
        .task {
            await refreshStatus()
        }
        .onOpenURL { url in
            handleOAuthRedirect(url: url)
        }
        .alert(L("sheets.error.tokenRevoked"), isPresented: .constant(errorMessage != nil)) {
            Button(L("cashflow.common.close"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            if let msg = errorMessage {
                Text(msg)
            }
        }
        .confirmationDialog(
            L("sheets.connected.disconnect"),
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("sheets.connected.disconnect"), role: .destructive) {
                Task { await disconnect() }
            }
            Button(L("cashflow.common.cancel"), role: .cancel) {}
        }
    }

    // MARK: - Секция

    @ViewBuilder
    private var sectionHeader: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "tablecells")
                .font(.millioCallout)
                .foregroundStyle(AppColors.profileIconGreen)
            Text(L("sheets.connect.title"))
                .font(.millioCallout)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Контент по состоянию

    @ViewBuilder
    private var stateContent: some View {
        if status.syncState == .syncing || isLoading {
            syncingView
        } else if status.isConnected {
            connectedView
        } else {
            disconnectedView
        }
    }

    // MARK: - Не подключено

    private var disconnectedView: some View {
        Button {
            Task { await connect() }
        } label: {
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "plus.circle.fill")
                    .font(.millioCallout)
                Text(L("sheets.connect.button"))
                    .font(.millioCalloutSemibold)
            }
            .foregroundStyle(AppColors.profileValueAccent)
            .padding(.vertical, AppSpacing.s)
        }
        .disabled(isLoading)
    }

    // MARK: - Синхронизация

    private var syncingView: some View {
        HStack(spacing: AppSpacing.s) {
            ProgressView()
                .tint(AppColors.textSecondary)
                .scaleEffect(0.85)
            Text(L("sheets.sync.progress"))
                .font(.millioCallout)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: - Подключено

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            // Статус строка
            HStack(spacing: AppSpacing.s) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.millioCallout)
                    .foregroundStyle(AppColors.profileIconGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rowsLabel)
                        .font(.millioCalloutSemibold)
                        .foregroundStyle(AppColors.textPrimary)
                    if let lastSync = status.lastSyncAt {
                        Text(lastSyncLabel(date: lastSync))
                            .font(.millioCaptionRegular)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            // Кнопки действий
            HStack(spacing: AppSpacing.m) {
                if let sheetURL = status.spreadsheetURL {
                    Button {
                        openURL(sheetURL)
                    } label: {
                        Label(L("sheets.connected.openButton"), systemImage: "arrow.up.right.square")
                            .font(.millioCaption)
                            .foregroundStyle(AppColors.profileValueAccent)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    showDisconnectConfirmation = true
                } label: {
                    Text(L("sheets.connected.disconnect"))
                        .font(.millioCaption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: - Форматирование

    private var rowsLabel: String {
        let count = status.totalRows
        return String(format: L("sheets.sync.rows"), count)
    }

    private func lastSyncLabel(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timeString = formatter.string(from: date)
        return String(format: L("sheets.sync.lastUpdated"), timeString)
    }

    // MARK: - Действия

    private func refreshStatus() async {
        guard let service = diContainer?.sheetsExportService else { return }
        status = await service.getStatus()
    }

    private func connect() async {
        guard let service = diContainer?.sheetsExportService else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let authURL = try await service.connectAccount()
            openURL(authURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleOAuthRedirect(url: URL) {
        // Ожидаем схему millio://sheets/callback?code=...
        guard
            url.host == "sheets",
            url.path == "/callback",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else { return }

        Task {
            guard let service = diContainer?.sheetsExportService else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                try await service.handleOAuthCallback(code: code)
                await refreshStatus()
            } catch SheetsExportError.tokenRevoked {
                errorMessage = L("sheets.error.tokenRevoked")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func disconnect() async {
        guard let service = diContainer?.sheetsExportService else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.disconnectAccount()
            status = .disconnected
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    SheetsConnectionView()
        .padding(AppSpacing.xl)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
