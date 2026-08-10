import SwiftData
import SwiftUI

struct CreditCardEditSheet: View {
    let account: Account
    let modelContext: ModelContext
    let onSave: (CreditCardEditCommand) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var bank: String
    @State private var last4: String
    @State private var limit: String
    @State private var minimumPayment: String
    @State private var note: String
    @State private var statementDay: Int
    @State private var dueDay: Int
    @State private var graceDays: Int
    @State private var includeInTotal: Bool
    @State private var groupID: UUID?
    @State private var showsAdditional = false

    init(account: Account, modelContext: ModelContext, onSave: @escaping (CreditCardEditCommand) -> Void) {
        self.account = account
        self.modelContext = modelContext
        self.onSave = onSave
        let meta = account.cardMeta
        _name = State(initialValue: account.name)
        _bank = State(initialValue: meta?.bank ?? "")
        _last4 = State(initialValue: meta?.last4 ?? "")
        _limit = State(initialValue: meta?.creditLimit.map { "\($0)" } ?? "")
        _minimumPayment = State(initialValue: meta?.minPayment.map { "\($0)" } ?? "")
        _note = State(initialValue: account.note ?? "")
        _statementDay = State(initialValue: meta?.statementDay ?? 1)
        _dueDay = State(initialValue: meta?.dueDay ?? 20)
        _graceDays = State(initialValue: meta?.graceDays ?? 0)
        _includeInTotal = State(initialValue: account.includeInTotal)
        _groupID = State(initialValue: account.group?.id)
    }

    private var groups: [AccountGroup] {
        (try? modelContext.fetch(FetchDescriptor<AccountGroup>(sortBy: [SortDescriptor(\.order)]))) ?? []
    }
    private var parsedLimit: Decimal? { Decimal(string: limit.replacingOccurrences(of: ",", with: ".")) }
    private var parsedMinimum: Decimal? {
        minimumPayment.isEmpty ? nil : Decimal(string: minimumPayment.replacingOccurrences(of: ",", with: "."))
    }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (parsedLimit ?? 0) > 0 &&
        (last4.isEmpty || (last4.count == 4 && last4.allSatisfy(\.isNumber)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    section("Main") {
                        TextField(L("accounts_core.detail.sheet.edit.name"), text: $name)
                        Divider(); TextField("Bank / issuer", text: $bank)
                        Divider(); TextField(L("finances.editor.card.number_placeholder"), text: $last4)
                            .keyboardType(.numberPad)
                            .onChange(of: last4) { _, value in last4 = String(value.filter(\.isNumber).prefix(4)) }
                        Divider(); Picker(L("accounts_core.detail.sheet.edit.group"), selection: $groupID) {
                            Text(L("accounts_core.detail.sheet.edit.no_group")).tag(Optional<UUID>.none)
                            ForEach(groups, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    section("Limit and terms") {
                        TextField(L("finances.add_account.card.credit_limit"), text: $limit).keyboardType(.decimalPad)
                        Divider(); Stepper("Grace period: \(graceDays)", value: $graceDays, in: 0...365)
                    }
                    section(L("finances.add_account.credit.payment.section")) {
                        Stepper("Statement day: \(statementDay)", value: $statementDay, in: 1...31)
                        Divider(); Stepper("Payment day: \(dueDay)", value: $dueDay, in: 1...31)
                        Divider(); TextField(L("finances.add_account.credit.monthly_payment"), text: $minimumPayment).keyboardType(.decimalPad)
                    }
                    section("Accounting") {
                        Toggle(L("finances.add_account.total_impact.include"), isOn: $includeInTotal).tint(AppColors.toggleOnGreen)
                        Divider(); ViewThatFits(in: .horizontal) {
                            HStack { Text(L("finances.add_account.field.currency")); Spacer(); Text(account.currency).foregroundStyle(AppColors.textSecondary) }
                            VStack(alignment: .leading) { Text(L("finances.add_account.field.currency")); Text(account.currency).foregroundStyle(AppColors.textSecondary) }
                        }
                    }
                    section(nil) {
                        Button { withAnimation { showsAdditional.toggle() } } label: {
                            HStack { Label(L("finances.editor.section.additional"), systemImage: "slider.horizontal.3"); Spacer(); Image(systemName: showsAdditional ? "chevron.up" : "chevron.down") }
                        }.buttonStyle(.plain)
                        if showsAdditional { Divider(); TextField(L("accounts_core.detail.sheet.note_placeholder"), text: $note, axis: .vertical).lineLimit(2...6) }
                    }
                }.padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(L("accounts_core.detail.sheet.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(L("accounts_core.detail.sheet.cancel")) }
                ToolbarItem(placement: .confirmationAction) { Button { save() } label: { Image(systemName: "checkmark") }.accessibilityLabel(L("accounts_core.detail.sheet.save")).disabled(!isValid) }
            }
        }
    }

    @ViewBuilder private func section<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.headline).foregroundStyle(AppColors.textSecondary) }
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(14).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func save() {
        guard let parsedLimit else { return }
        onSave(CreditCardEditCommand(
            name: name,
            group: groups.first { $0.id == groupID },
            note: note,
            includeInTotal: includeInTotal,
            bank: bank,
            last4: last4,
            creditLimit: parsedLimit,
            statementDay: statementDay,
            dueDay: dueDay,
            minPayment: parsedMinimum,
            graceDays: graceDays == 0 ? nil : graceDays
        ))
    }
}
