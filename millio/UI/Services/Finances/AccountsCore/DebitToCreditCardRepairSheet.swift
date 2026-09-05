import SwiftUI
import SwiftData

/// UI ручного ремонта «дебетовая карта на самом деле кредитка» (Core-логика — `DebitToCreditCardRepair`).
/// Владелец вводит реальный лимит, видит предпросмотр (долг/доступно/смена вклада в «Итого») и
/// подтверждает явно — без предпросмотра и подтверждения запись не происходит.
struct DebitToCreditCardRepairSheet: View {
    let account: Account
    let modelContext: ModelContext
    let onCommitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var limitText: String = ""
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var balanceToday: Decimal {
        AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: Date())
    }

    private var limit: Decimal? {
        Decimal(string: AmountInputFormatter.sanitize(limitText))
    }

    private var preview: DebitToCreditCardRepair.Preview? {
        guard let limit else { return nil }
        return DebitToCreditCardRepair.preview(balanceToday: balanceToday, creditLimit: limit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            Text(L("accounts_core.debit_card.repair.title"))
                .font(.millioBodySemibold)
                .foregroundStyle(AppColors.textPrimary)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(L("accounts_core.debit_card.repair.limit_label"))
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.textSecondary)
                HStack {
                    AmountTextField(placeholder: "0", value: $limitText)
                        .font(.millioTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .focused($isFocused)
                    Text(verbatim: account.currency)
                        .font(.millioBody)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            if let preview {
                previewBlock(preview)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.error)
            }

            Spacer(minLength: 0)

            Button(L("accounts_core.debit_card.repair.confirm"), action: apply)
                .font(.millioBodySemibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(preview == nil ? AppColors.textTertiary : AppColors.error))
                .disabled(preview == nil)

            Button(L("accounts_core.detail.sheet.cancel")) { dismiss() }
                .font(.millioBodySemibold)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
        }
        .padding(AppSpacing.l)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L("common.done")) { isFocused = false }
            }
        }
    }

    private func previewBlock(_ preview: DebitToCreditCardRepair.Preview) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            row(L("accounts_core.debit_card.repair.debt_label"), amountText(preview.debt))
            row(L("accounts_core.debit_card.repair.available_label"), amountText(preview.availableAfter))
            Text(String(
                format: L("accounts_core.debit_card.repair.total_change_format"),
                signedAmountText(preview.contributionBefore), signedAmountText(preview.contributionAfter)
            ))
            .font(.millioCalloutRegular)
            .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.millioCalloutRegular).foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value).font(.millioBodySemibold).foregroundStyle(AppColors.textPrimary)
        }
    }

    private func amountText(_ value: Decimal) -> String {
        DepositAmountTextFormatter.string(value, currency: account.currency, locale: AppLocalization.currentAppLocale)
    }

    private func signedAmountText(_ value: Decimal) -> String {
        (value > 0 ? "+" : "") + amountText(value)
    }

    private func apply() {
        guard let limit else { return }
        do {
            let service = AccountsCoreService(modelContext: modelContext)
            _ = try DebitToCreditCardRepair.apply(
                account: account, creditLimit: limit, balanceToday: balanceToday,
                service: service, context: modelContext
            )
            onCommitted()
        } catch {
            errorMessage = L("accounts_core.debit_card.repair.error")
        }
    }
}
