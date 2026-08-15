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
    /// Заголовок формы — по умолчанию «Изменить баланс», но эта же форма переиспользуется для
    /// переоценки ручного актива (Фаза 4: «Переоценить» — тот же ввод «новое значение целиком»).
    var titleOverride: String?

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String

    init(currentBalance: Decimal, titleOverride: String? = nil, onSave: @escaping (Decimal) -> Void) {
        self.currentBalance = currentBalance
        self.titleOverride = titleOverride
        self.onSave = onSave
        _amountText = State(initialValue: NSDecimalNumber(decimal: currentBalance).stringValue)
    }

    private var parsedAmount: Decimal? {
        let canonical = AmountInputFormatter.sanitize(amountText)
        return Decimal(string: canonical)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountTextField(
                        placeholder: L("accounts_core.detail.sheet.adjust.new_balance"),
                        value: $amountText
                    )
                }
            }
            .navigationTitle(titleOverride ?? L("accounts_core.detail.sheet.adjust.title"))
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

/// Форма «купить/продать» рыночного актива (Фаза 4): количество + цена за единицу + дата + заметка,
/// вызывает `AccountsCoreService.buy`/`sell`. Продажа больше остатка — предупреждение (НЕ жёсткий
/// запрет, брифинг Фазы 4, задача 4): текст под полем, кнопка «Сохранить» остаётся активной.
struct AccountBuySellSheet: View {
    let title: String
    let currentQuantity: Decimal
    let initialUnitPrice: Decimal?
    let currency: String
    /// `true` для формы продажи — включает предупреждение о превышении остатка.
    let showsSellWarning: Bool
    let onSave: (Decimal, Decimal, Decimal, Date, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantityText = ""
    @State private var unitPriceText = ""
    @State private var feeText = ""
    @State private var date = Date()
    @State private var note = ""

    private var parsedQuantity: Decimal? {
        let canonical = AmountTextField.canonical(from: quantityText, maxFractionDigits: 8)
        guard let value = Decimal(string: canonical), value > 0 else { return nil }
        return value
    }

    private var parsedUnitPrice: Decimal? {
        let canonical = AmountTextField.canonical(from: unitPriceText, maxFractionDigits: 8)
        guard let value = Decimal(string: canonical), value > 0 else { return nil }
        return value
    }

    private var parsedFee: Decimal {
        let canonical = AmountTextField.canonical(from: feeText, maxFractionDigits: 8)
        return max(0, Decimal(string: canonical) ?? 0)
    }

    private var grossTotal: Decimal? {
        guard let quantity = parsedQuantity, let price = parsedUnitPrice else { return nil }
        return quantity * price
    }

    private var exceedsCurrentQuantity: Bool {
        guard showsSellWarning, let quantity = parsedQuantity else { return false }
        return quantity > currentQuantity
    }

    var body: some View {
        NavigationStack {
            Form {
                if let price = initialUnitPrice, price > 0 {
                    Section {
                        HStack {
                            Label(L("accounts_core.detail.market.price_label"), systemImage: "waveform.path.ecg")
                            Spacer()
                            Text("\(AmountInputFormatter.display(NSDecimalNumber(decimal: price).stringValue, maxFractionDigits: 8)) \(currency)")
                                .font(.millioBodySemibold)
                        }
                    }
                    .listRowBackground(AppColors.brandPrimary.opacity(0.14))
                }
                Section {
                    AmountTextField(
                        placeholder: L("accounts_core.detail.sheet.market.quantity_placeholder"),
                        value: $quantityText,
                        maxFractionDigits: 8
                    )
                    AmountTextField(
                        placeholder: L("accounts_core.detail.sheet.market.unit_price_placeholder"),
                        value: $unitPriceText,
                        maxFractionDigits: 8
                    )
                    AmountTextField(
                        placeholder: L("accounts_core.detail.market.action.fee"),
                        value: $feeText,
                        maxFractionDigits: 8
                    )
                    DatePicker(L("accounts_core.detail.sheet.date_label"), selection: $date, displayedComponents: .date)
                    TextField(L("accounts_core.detail.sheet.note_placeholder"), text: $note)
                }
                if let grossTotal {
                    Section {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: showsSellWarning ? "arrow.down.right.circle.fill" : "arrow.up.right.circle.fill")
                                .foregroundStyle(showsSellWarning ? AppColors.warning : AppColors.positiveColor)
                            Spacer()
                            Text("\(AmountInputFormatter.display(NSDecimalNumber(decimal: grossTotal).stringValue, maxFractionDigits: 8)) \(currency)")
                                .font(.millioTitle)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .listRowBackground(
                        (showsSellWarning ? AppColors.warning : AppColors.positiveColor).opacity(0.13)
                    )
                }
                if exceedsCurrentQuantity {
                    Section {
                        Text(String(format: L("accounts_core.detail.market.sell_exceeds_warning_format"), NSDecimalNumber(decimal: currentQuantity).stringValue))
                            .foregroundStyle(AppColors.warning)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard unitPriceText.isEmpty, let initialUnitPrice, initialUnitPrice > 0 else { return }
                unitPriceText = NSDecimalNumber(decimal: initialUnitPrice).stringValue
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("accounts_core.detail.sheet.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("accounts_core.detail.sheet.save")) {
                        guard let quantity = parsedQuantity, let unitPrice = parsedUnitPrice else { return }
                        onSave(quantity, unitPrice, parsedFee, date, note.isEmpty ? nil : note)
                    }
                    .disabled(parsedQuantity == nil || parsedUnitPrice == nil || exceedsCurrentQuantity)
                }
            }
        }
    }
}

/// Форма досрочного закрытия вклада (Фаза 3): выбор ТОЛЬКО счёта-получателя остатка — сумма не
/// вводится (весь остаток переводится автоматически, `AccountsCoreService.earlyCloseDeposit`).
/// Скоуп, как у `AccountTransferSheet`: получатель — счёт той же валюты.
struct AccountEarlyCloseSheet: View {
    let source: Account
    let modelContext: ModelContext
    let onSave: (Account) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDestinationID: UUID?

    private var candidates: [Account] {
        let descriptor = FetchDescriptor<Account>()
        guard let all = try? modelContext.fetch(descriptor) else { return [] }
        let today = Date()
        return all.filter {
            $0.id != source.id && $0.currency == source.currency && $0.participates(on: today)
        }
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
                    }
                }
            }
            .navigationTitle(L("accounts_core.detail.deposit.action.early_close"))
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
                        guard let destination = selectedDestination else { return }
                        onSave(destination)
                    }
                    .disabled(selectedDestination == nil)
                }
            }
        }
    }
}

/// Минимальная форма правки «карточки» счёта (Ф5c.7.0): имя + группа + заметка + membership. Полноценный
/// rich-edit (структурная meta по kind, иконка) — отдельная под-фаза 5c.7.5 через перетипизированную
/// `FinanceAddAccountView`. Вызывает `AccountsCoreService.updateAccount` (единственная точка записи).
/// Валюты в форме нет намеренно — смена валюты запрещена в v1 (инвариант 8, см. докстринг `updateAccount`).
struct AccountEditDetailsSheet: View {
    let account: Account
    let modelContext: ModelContext
    /// Generic fields plus optional real-estate metadata.
    let onSave: (String, AccountGroup?, String?, Bool, RealEstatePropertyType, Int?, UUID?) -> Void
    let onProductTransitionCommitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String
    @State private var includeInTotal: Bool
    @State private var propertyType: RealEstatePropertyType
    @State private var reminderMonths: Int
    @State private var selectedLoanID: UUID?
    /// nil = «Без группы» (счёт без группы = `account.group == nil`, канон Ungrouped ядра).
    @State private var selectedGroupID: UUID?

    init(
        account: Account,
        modelContext: ModelContext,
        onSave: @escaping (String, AccountGroup?, String?, Bool, RealEstatePropertyType, Int?, UUID?) -> Void,
        onProductTransitionCommitted: @escaping () -> Void
    ) {
        self.account = account
        self.modelContext = modelContext
        self.onSave = onSave
        self.onProductTransitionCommitted = onProductTransitionCommitted
        _name = State(initialValue: account.name)
        _note = State(initialValue: account.note ?? "")
        _includeInTotal = State(initialValue: account.includeInTotal)
        let profile = try? RealEstateProfileService(modelContext: modelContext).profile(accountID: account.id)
        _propertyType = State(initialValue: profile?.propertyType ?? .other)
        _reminderMonths = State(initialValue: account.manualAssetMeta?.revalReminderMonths ?? 0)
        _selectedLoanID = State(initialValue: account.manualAssetMeta?.linkedLoanID)
        _selectedGroupID = State(initialValue: account.group?.id)
    }

    private var groups: [AccountGroup] {
        let descriptor = FetchDescriptor<AccountGroup>(sortBy: [SortDescriptor(\.order)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedGroup: AccountGroup? {
        groups.first { $0.id == selectedGroupID }
    }

    private var eligibleLoans: [Account] {
        let currency = account.currency
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> {
            $0.kindRaw == "loan" && $0.currency == currency && $0.archivedAt == nil && $0.deletedAt == nil
        })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("accounts_core.detail.sheet.edit.name"), text: $name)
                    Picker(L("accounts_core.detail.sheet.edit.group"), selection: $selectedGroupID) {
                        Text(L("accounts_core.detail.sheet.edit.no_group")).tag(Optional<UUID>.none)
                        ForEach(groups, id: \.id) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }
                    TextField(L("accounts_core.detail.sheet.note_placeholder"), text: $note)
                    Toggle(L("finances.add_account.total_impact.include"), isOn: $includeInTotal)
                        .tint(AppColors.toggleOnGreen)
                }
                if account.productType == .realEstate {
                    Section(L("real_estate.edit.object")) {
                        Picker(L("real_estate.about.type"), selection: $propertyType) {
                            ForEach(RealEstatePropertyType.allCases) { type in
                                Text(type.localizedTitle).tag(type)
                            }
                        }
                        LabeledContent(L("real_estate.about.currency"), value: account.currency)
                        Stepper(value: $reminderMonths, in: 0...60) {
                            Text(reminderMonths == 0
                                 ? L("real_estate.reminder.off")
                                 : String(format: L("real_estate.about.reminder.months"), reminderMonths))
                        }
                        Picker(L("real_estate.about.mortgage"), selection: $selectedLoanID) {
                            Text(L("real_estate.mortgage.none")).tag(Optional<UUID>.none)
                            ForEach(eligibleLoans, id: \.id) { loan in
                                Text(loan.name).tag(Optional(loan.id))
                            }
                        }
                    }
                }
                AccountProductTransitionSection(
                    account: account,
                    modelContext: modelContext,
                    onCommitted: onProductTransitionCommitted
                )
            }
            .navigationTitle(L("accounts_core.detail.sheet.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("accounts_core.detail.sheet.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("accounts_core.detail.sheet.save")) {
                        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(
                            trimmedName,
                            selectedGroup,
                            trimmedNote.isEmpty ? nil : trimmedNote,
                            includeInTotal,
                            propertyType,
                            reminderMonths == 0 ? nil : reminderMonths,
                            selectedLoanID
                        )
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }
}
