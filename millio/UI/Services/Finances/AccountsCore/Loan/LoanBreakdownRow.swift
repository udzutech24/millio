import SwiftUI

/// Строка разбивки платежа: точка-легенда → название → сумма.
///
/// Метрика строки повторяет `AccountDetailsValueRow` (44pt, `millioBody`, паддинг `AppSpacing.l`),
/// поэтому разбивка и обычные строки бокса стоят на одной сетке. Отдельный тип, а не копия в
/// каждом экране: та же строка нужна и деталке, и листу подтверждения платежа.
struct LoanBreakdownRow: View {
    let title: String
    let value: String
    /// Цвет точки-легенды. `nil` — строка без точки (нейтральная величина, не часть платежа).
    var legendColor: Color?

    var body: some View {
        HStack(spacing: AppSpacing.s) {
            if let legendColor {
                Circle().fill(legendColor).frame(width: 8, height: 8)
            }
            Text(title)
                .font(.millioBody)
                .foregroundStyle(AppColors.textPrimary)
            Spacer(minLength: AppSpacing.s)
            Text(value)
                .font(.millioBody)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, AppSpacing.l)
    }
}
