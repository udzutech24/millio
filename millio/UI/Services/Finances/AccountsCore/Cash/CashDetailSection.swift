import SwiftUI

/// Наличные (`.cash`): единственная операция, которой нет у банковских продуктов, — сверка
/// с кошельком. Банк наличные не подтверждает, поэтому дата последней сверки и вход в неё
/// вынесены на экран, а не спрятаны в «···».
struct CashDetailSection: View {
    let lastReconciliation: Date?
    /// Архивный/удалённый счёт read-only (A3): кнопка сверки прячется, а не показывается
    /// с системным «Операция не может быть завершена» после отказа `AccountsCoreService`.
    /// История (дата последней сверки) остаётся видимой — не переоценка прошлого, а запрет правки.
    let canReconcile: Bool
    let onReconcile: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(L("accounts_core.detail.cash.reconcile.title"))
                    .font(.millioCallout)
                    .foregroundStyle(AppColors.textPrimary)

                Text(CashReconciliationPresentation.subtitle(lastReconciliation: lastReconciliation))
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: AppSpacing.s)

            if canReconcile {
                Button(action: onReconcile) {
                    Text(L("accounts_core.detail.action.reconcile_cash"))
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.m)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppSpacing.m))
    }
}

/// Витрина сверки наличных — чистая, чтобы дату последней сверки можно было проверить тестом
/// без SwiftUI.
enum CashReconciliationPresentation {
    /// Сверка — это корректировка баланса (`.adjustment`), других её следов в ленте нет.
    /// Будущие даты не отбрасываем: корректировку задним/передним числом пользователь может
    /// поставить сам, и «последняя» для него — самая поздняя из введённых.
    static func lastReconciliationDate(events: [AccountEvent]) -> Date? {
        events
            .filter { $0.type == .adjustment }
            .map(\.date)
            .max()
    }

    static func subtitle(lastReconciliation: Date?, locale: Locale = AppLocalization.currentAppLocale) -> String {
        guard let lastReconciliation else {
            return AppLocalization.string("accounts_core.detail.cash.never_reconciled", locale: locale)
        }
        let formatted = lastReconciliation.formatted(date: .abbreviated, time: .omitted)
        return String(
            format: AppLocalization.string("accounts_core.detail.cash.last_reconciliation_format", locale: locale),
            formatted
        )
    }
}
