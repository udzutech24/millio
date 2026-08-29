import SwiftUI

struct DebitCardDetailSection: View {
    let account: Account
    let snapshot: DebitCardSnapshot

    var body: some View {
        // Ф3: имя, баланс и статусы «не в тотале» / «архив» рисует общий `AccountHeroCardView`
        // над секцией. Здесь остаётся только то, чего у hero нет — сумма в валюте отображения.
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            convertedValue
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.m)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppSpacing.m))

            if snapshot.incompleteReason != nil {
                VStack(spacing: AppSpacing.s) {
                    Image(systemName: "creditcard.trianglebadge.exclamationmark")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(L("debit_card.state.incomplete.title"))
                        .font(.millioHeadline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("debit_card.state.incomplete.message"))
                        .font(.millioCalloutRegular)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.m)
            }
        }
    }

    @ViewBuilder private var convertedValue: some View {
        switch snapshot.converted {
        case .unavailable:
            Text(L("debit_card.balance.converted.unavailable"))
                .font(.millioCaptionRegular).foregroundStyle(AppColors.textSecondary)
        case let .exact(value, currency):
            Text("\(L("debit_card.balance.converted")): \(amount(value, currency: currency))")
                .font(.millioCalloutRegular).foregroundStyle(AppColors.textSecondary)
        case let .provisional(value, currency):
            Text("\(L("debit_card.balance.converted.provisional")): \(amount(value, currency: currency))")
                .font(.millioCalloutRegular).foregroundStyle(AppColors.textSecondary)
        }
    }

    private func amount(_ value: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = DebitCurrencyPolicy.fractionDigits(for: currency)
        return "\(formatter.string(from: value as NSNumber) ?? "0") \(currency)"
    }
}

struct DebitCardRefundSheet: View {
    let expenses: [AccountEvent]
    let currency: String
    let onSave: (String, Decimal, Date, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedOperationID: String?
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""

    private var amount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                if expenses.isEmpty {
                    ContentUnavailableView(L("debit_card.refund.empty"), systemImage: "arrow.uturn.backward.circle")
                } else {
                    Picker(L("debit_card.refund.original"), selection: $selectedOperationID) {
                        Text(L("debit_card.refund.select")).tag(String?.none)
                        ForEach(expenses, id: \.id) { expense in
                            Text("\(expense.date.formatted(date: .abbreviated, time: .omitted)) · \(expense.amount ?? 0) \(currency)")
                                .tag(expense.sourceTransactionID)
                        }
                    }
                    TextField(L("accounts_core.detail.sheet.amount_placeholder"), text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker(L("accounts_core.detail.sheet.date_label"), selection: $date, displayedComponents: .date)
                    TextField(L("accounts_core.detail.sheet.note_placeholder"), text: $note)
                }
            }
            .navigationTitle(L("debit_card.action.refund"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("accounts_core.detail.sheet.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("accounts_core.detail.sheet.save")) {
                        guard let selectedOperationID, let amount else { return }
                        onSave(selectedOperationID, amount, date, note.isEmpty ? nil : note)
                    }
                    .disabled(selectedOperationID == nil || amount == nil)
                }
            }
        }
        .onAppear { selectedOperationID = selectedOperationID ?? expenses.first?.sourceTransactionID }
    }
}
