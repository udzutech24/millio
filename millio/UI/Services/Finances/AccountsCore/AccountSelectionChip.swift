import SwiftUI

/// Чипс одиночного выбора в формах счетов — капсула с заливкой-градиентом у выбранного варианта.
///
/// Вынесен из `DepositTermsInputCard.periodChip`, где жил приватным методом: тот же самый чипс
/// нужен периодичности платежа кредита, а второй экземпляр стилей разъехался бы с первым же
/// изменением оформления.
struct AccountSelectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.millioCallout)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.s)
                .background {
                    RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                        .fill(isSelected
                              ? LinearGradient(
                                  colors: AppColors.financesGradient.map { $0.opacity(0.35) },
                                  startPoint: .leading, endPoint: .trailing
                              )
                              : LinearGradient(
                                  colors: [AppColors.iconBackground, AppColors.iconBackground],
                                  startPoint: .leading, endPoint: .trailing
                              ))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                                .stroke(
                                    isSelected ? AppColors.brandPrimary : Color.clear,
                                    lineWidth: 1
                                )
                        }
                }
        }
        .buttonStyle(.plain)
    }
}
