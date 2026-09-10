import SwiftUI

/// Формулировки подсказок вклада — заготовленные локализованные тексты. Отделены от правил
/// (`DepositNudgeEngine`) намеренно: движок решает ЧТО сказать, этот слой — КАК. Заменить
/// формулировку на сгенерированную можно здесь, не трогая ни правила, ни экран.
extension DepositNudge {
    var title: String {
        switch self {
        case .maturityApproaching: L("accounts_core.deposit.nudge.maturity_approaching.title")
        case .maturedNeedsAction: L("accounts_core.deposit.nudge.matured.title")
        case .rolloverIsManual: L("accounts_core.deposit.nudge.rollover.title")
        case .reminderOff: L("accounts_core.deposit.nudge.reminder_off.title")
        }
    }

    var message: String {
        switch self {
        case .maturityApproaching(let daysRemaining):
            String(format: L("accounts_core.deposit.nudge.maturity_approaching.message_format"), daysRemaining)
        case .maturedNeedsAction(let daysSinceMaturity):
            daysSinceMaturity > 0
                ? String(format: L("accounts_core.deposit.nudge.matured.message_format"), daysSinceMaturity)
                : L("accounts_core.deposit.nudge.matured.message_today")
        case .rolloverIsManual:
            L("accounts_core.deposit.nudge.rollover.message")
        case .reminderOff:
            L("accounts_core.deposit.nudge.reminder_off.message")
        }
    }

    var systemImage: String {
        switch self {
        case .maturityApproaching: "clock"
        case .maturedNeedsAction: "exclamationmark.circle"
        case .rolloverIsManual: "arrow.triangle.2.circlepath"
        case .reminderOff: "bell.slash"
        }
    }

    /// Действие подсказки — только уже существующее действие экрана вклада: своих переходов
    /// подсказка не изобретает.
    var action: DepositDetailAction? {
        switch self {
        case .maturedNeedsAction: .withdrawAtMaturity
        case .reminderOff: .editTerms
        case .maturityApproaching, .rolloverIsManual: nil
        }
    }

    var isTimeCritical: Bool {
        switch self {
        case .maturityApproaching, .maturedNeedsAction: true
        case .rolloverIsManual, .reminderOff: false
        }
    }
}

/// Блок «Что дальше» на экране вклада: подсказки движка правил с переходом в уже существующее
/// действие. Пустой список подсказок карточку не рисует — молчание лучше пустой плашки.
struct DepositNudgeCard: View {
    let nudges: [DepositNudge]
    let onAction: (DepositDetailAction) -> Void

    var body: some View {
        if !nudges.isEmpty {
            AccountDetailPlaqueSection(
                title: L("accounts_core.deposit.nudge.section_title"),
                caption: nil
            ) {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    ForEach(nudges) { nudge in
                        row(nudge)
                    }
                }
            }
        }
    }

    private func row(_ nudge: DepositNudge) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.m) {
            Image(systemName: nudge.systemImage)
                .font(.millioCallout)
                .foregroundStyle(nudge.isTimeCritical ? AppColors.warning : AppColors.textSecondary)
                .frame(width: AppSpacing.xl, alignment: .leading)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(nudge.title)
                    .font(.millioCallout)
                    .foregroundStyle(AppColors.textPrimary)
                Text(nudge.message)
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let action = nudge.action {
                    Button {
                        onAction(action)
                    } label: {
                        Text(action.title)
                            .font(.millioCalloutSemibold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.financesGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppSpacing.xs)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
