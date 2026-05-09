//
//  AutoRestoringView.swift
//  millio
//

import SwiftUI

/// Экран автоматического восстановления данных из последнего бекапа.
/// Показывается без участия пользователя когда приложение обнаружило потерю данных при старте.
struct AutoRestoringView: View {
    let backupDate: Date?

    var body: some View {
        ZStack {
            AppColors.background.ignoresSafeArea()

            VStack(spacing: 24) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(AppColors.brandPrimary)

                VStack(spacing: 8) {
                    Text(BackupL10n.tr("backup.auto-restore.title", fallback: "Restoring Data"))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)

                    if let backupDate {
                        let dateString = backupDate.formatted(date: .abbreviated, time: .omitted)
                        Text(BackupL10n.format("backup.auto-restore.subtitle", fallback: "Restoring from backup of %@", dateString))
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(40)
        }
    }
}
