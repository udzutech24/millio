//
//  AppliedPlannedNoticeStubSheet.swift
//  millio
//
//  ВРЕМЕННО (Фаза 2 плана plans/2026-09-05__planned-operations-applied-notice.md).
//  Задача файла — доказать, что триггер и очередь листов работают: показывается только число
//  применённых операций. Настоящий лист (суммы по валютам, раскрытие в список, «и ещё N»)
//  собирается в Ф3, локализованные строки заводятся в Ф5 — поэтому здесь ни одного текста,
//  только цифра.
//

import SwiftUI

struct AppliedPlannedNoticeStubSheet: View {
    let digest: AppliedPlannedDigest

    var body: some View {
        VStack(spacing: AppSpacing.s) {
            Text(verbatim: "\(digest.totalCount)")
                .font(.millioDisplayLarge)
                .foregroundStyle(AppColors.textPrimary)
            Text(verbatim: "\(digest.incomeCount) / \(digest.expenseCount)")
                .font(.millioCallout)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppSpacing.xl)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
