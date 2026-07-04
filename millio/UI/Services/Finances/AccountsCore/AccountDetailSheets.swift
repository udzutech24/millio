import SwiftUI
import SwiftData

/// Форма «доход/расход» для `AccountDetailView` — сумма + дата + заметка, вызывающая
/// `AccountsCoreService.recordEvent` (единственная точка записи).
struct AccountEventEntrySheet: View {
    let title: String
    let onSave: (Decimal, Date, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""

    private var parsedAmount: Decimal? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: normalized), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("accounts_core.detail.sheet.amount_placeholder"), text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker(L("accounts_core.detail.sheet.date_label"), selection: $date, displayedComponents: .date)
                    TextField(L("accounts_core.detail.sheet.note_placeholder"), text: $note)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("accounts_core.detail.sheet.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("accounts_core.detail.sheet.save")) {
                        guard let amount = parsedAmount else { return }
                        onSave(amount, date, note.isEmpty ? nil : note)
                    }
                    .disabled(parsedAmount == nil)
                }
            }
        }
    }
}

/// Форма «изменить баланс» — пользователь вводит НОВЫЙ остаток, сервис сам считает дельту
/// и создаёт `adjustment`-событие (AC1: события, а не хранимое поле, остаются истиной).
struct AccountAdjustBalanceSheet: View {
    let currentBalance: Decimal
    let onSave: (Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String

    init(currentBalance: Decimal, onSave: @escaping (Decimal) -> Void) {
        self.currentBalance = currentBalance
        self.onSave = onSave
        _amountText = State(initialValue: NSDecimalNumber(decimal: currentBalance).stringValue)
    }

    private var parsedAmount: Decimal? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: normalized)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("accounts_core.detail.sheet.adjust.new_balance"), text: $amountText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle(L("accounts_core.detail.sheet.adjust.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("accounts_core.detail.sheet.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("accounts_core.detail.sheet.save")) {
                        guard let amount = parsedAmount else { return }
                        onSave(amount)
                    }
                    .disabled(parsedAmount == nil)
                }
            }
        }
    }
}

/// Форма перевода между счетами нового ядра. МИНИМАЛЬНЫЙ скоуп Фазы 1a-ui: получатель —
/// только счёт ТОЙ ЖЕ валюты (курс перевода между разными валютами — отдельная задача,
/// см. заметки для 1b/2 в ответе сессии), иначе `AccountsCoreService.transfer` потребовал бы
/// курс, который эта форма пока не запрашивает.
struct AccountTransferSheet: View {
    let source: Account
    let modelContext: ModelContext
    let onSave: (Account, Decimal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var selectedDestinationID: UUID?

    private var candidates: [Account] {
        let descriptor = FetchDescriptor<Account>()
        guard let all = try? modelContext.fetch(descriptor) else { return [] }
        let today = Date()
        return all.filter {
            $0.id != source.id && $0.currency == source.currency && $0.participates(on: today)
        }
    }

    private var parsedAmount: Decimal? {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: normalized), value > 0 else { return nil }
        return value
    }

    private var selectedDestination: Account? {
        candidates.first { $0.id == selectedDestinationID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if candidates.isEmpty {
                    Text(L("accounts_core.detail.transfer.no_destinations"))
                        .foregroundStyle(AppColors.textTertiary)
                } else {
                    Section {
                        Picker(L("accounts_core.detail.sheet.transfer.destination"), selection: $selectedDestinationID) {
                            ForEach(candidates, id: \.id) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                        TextField(L("accounts_core.detail.sheet.amount_placeholder"), text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                }
            }
            .navigationTitle(L("accounts_core.detail.sheet.transfer.title"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if selectedDestinationID == nil {
                    selectedDestinationID = candidates.first?.id
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("accounts_core.detail.sheet.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("accounts_core.detail.sheet.save")) {
                        guard let amount = parsedAmount, let destination = selectedDestination else { return }
                        onSave(destination, amount)
                    }
                    .disabled(parsedAmount == nil || selectedDestination == nil)
                }
            }
        }
    }
}
