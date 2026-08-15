import SwiftData
import SwiftUI

/// Metadata edit plus an explicit financial correction. Saving appends one absolute
/// `.adjustment` event and keeps the original trade evidence intact.
struct StockPositionEditSheet: View {
    let account: Account
    let modelContext: ModelContext
    let onSave: (String, AccountGroup?, String?, Bool, Decimal, Decimal?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String
    @State private var includeInTotal: Bool
    @State private var selectedGroupID: UUID?
    @State private var quantityText: String
    @State private var averageCostText: String

    init(
        account: Account,
        modelContext: ModelContext,
        snapshot: StockPositionSnapshot,
        onSave: @escaping (String, AccountGroup?, String?, Bool, Decimal, Decimal?) -> Void
    ) {
        self.account = account
        self.modelContext = modelContext
        self.onSave = onSave
        _name = State(initialValue: account.name)
        _note = State(initialValue: account.note ?? "")
        _includeInTotal = State(initialValue: account.includeInTotal)
        _selectedGroupID = State(initialValue: account.group?.id)
        _quantityText = State(initialValue: NSDecimalNumber(decimal: snapshot.quantity).stringValue)
        _averageCostText = State(initialValue: snapshot.averageUnitCost.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
    }

    private var groups: [AccountGroup] {
        (try? modelContext.fetch(FetchDescriptor<AccountGroup>(sortBy: [SortDescriptor(\.order)]))) ?? []
    }
    private var selectedGroup: AccountGroup? { groups.first { $0.id == selectedGroupID } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var quantity: Decimal? {
        Decimal(string: AmountTextField.canonical(from: quantityText, maxFractionDigits: 8))
    }
    private var averageCost: Decimal? {
        Decimal(string: AmountTextField.canonical(from: averageCostText, maxFractionDigits: 8))
    }
    private var isValid: Bool {
        guard !trimmedName.isEmpty, let quantity, quantity >= 0 else { return false }
        return quantity == 0 || (averageCost ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("accounts_core.detail.sheet.edit.name"), text: $name)
                    Picker(L("accounts_core.detail.sheet.edit.group"), selection: $selectedGroupID) {
                        Text(L("accounts_core.detail.sheet.edit.no_group")).tag(Optional<UUID>.none)
                        ForEach(groups, id: \.id) { group in Text(group.name).tag(Optional(group.id)) }
                    }
                    TextField(L("accounts_core.detail.sheet.note_placeholder"), text: $note)
                    Toggle(L("finances.add_account.total_impact.include"), isOn: $includeInTotal)
                        .tint(AppColors.toggleOnGreen)
                }

                Section(L("stock.edit.position.section")) {
                    LabeledContent(L("accounts_core.detail.market.quantity_label")) {
                        AmountTextField(placeholder: "0", value: $quantityText, maxFractionDigits: 8)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 160)
                    }
                    LabeledContent(L("accounts_core.detail.market.average_cost_label")) {
                        AmountTextField(placeholder: "0", value: $averageCostText, maxFractionDigits: 8)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 160)
                            .disabled(quantity == 0)
                    }
                    Text(L("stock.edit.position.warning"))
                        .font(.millioCaptionRegular)
                        .foregroundStyle(AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle(L("accounts_core.detail.sheet.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("accounts_core.detail.sheet.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("accounts_core.detail.sheet.save")) {
                        guard let quantity else { return }
                        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmedName, selectedGroup, trimmedNote.isEmpty ? nil : trimmedNote,
                               includeInTotal, quantity, quantity == 0 ? nil : averageCost)
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}
