import SwiftUI
import SwiftData

// MARK: - Общие блоки языка экрана (тёмные плашки вместо системного Form)

/// Тёмная плашка-бокс — единица нового языка «Реквизитов счёта» (Коммит 2). Заменяет системный
/// светлый `Form`, который визуально выпадал из тёмного приложения.
struct AccountDetailsBoxCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.xl, style: .continuous)
                    .fill(AppColors.cardBoxBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.xl, style: .continuous)
                    .stroke(AppColors.cardBoxBorder, lineWidth: 1)
            )
    }
}

/// Капитель — подпись секции над боксом («УСЛОВИЯ ВКЛАДА» и т.п.).
private func accountDetailsSectionCaption(_ title: String) -> some View {
    Text(title)
        .font(.millioCaption2)
        .foregroundStyle(AppColors.textTertiary)
        .textCase(.uppercase)
}

/// Строка бокса с чекроном — открывает bottom-sheet пикер вместо перехода на отдельный экран.
struct AccountDetailsFieldRow: View {
    let title: String
    let value: String
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.millioBody)
                    .foregroundStyle(isDestructive ? AppColors.error : AppColors.textPrimary)
                Spacer(minLength: AppSpacing.s)
                Text(value)
                    .font(.millioBody)
                    .foregroundStyle(isDestructive ? AppColors.error.opacity(0.8) : AppColors.textSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.millioCaption2)
                    .foregroundStyle(isDestructive ? AppColors.error.opacity(0.6) : AppColors.textTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.l)
    }
}

private struct AccountDetailsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.millioBody)
                .foregroundStyle(AppColors.textPrimary)
        }
        .tint(AppColors.toggleOnGreen)
        .frame(minHeight: 44)
        .padding(.horizontal, AppSpacing.l)
    }
}

private struct AccountDetailsDivider: View {
    var body: some View {
        Divider().background(Color.white.opacity(0.08)).padding(.leading, AppSpacing.l)
    }
}

/// Bottom-sheet обёртка для полей-пикеров («Ставка», «Дата окончания», «Капитализация», ...) —
/// ручка + заголовок + «Готово», вместо перехода на отдельный экран (требование мока Коммита 2).
private struct AccountFieldPickerSheet<Content: View>: View {
    let title: String
    let onDone: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            HStack {
                Text(title)
                    .font(.millioBodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Button(L("common.done"), action: onDone)
                    .font(.millioBodySemibold)
                    .foregroundStyle(AppColors.brandPrimary)
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.top, AppSpacing.m)
            content()
            Spacer(minLength: 0)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Результат

/// Единый результат «Реквизитов счёта» вклада: генерика (имя/группа/заметка/тотал) — тем же
/// писателем, что у остальных счетов; условия вклада — тем же `DepositOperationCoordinator.editTerms`,
/// что и старый отдельный экран (регенерирует будущий график начислений).
struct DepositAccountDetailsResult {
    let name: String
    let group: AccountGroup?
    let note: String?
    let includeInTotal: Bool
    let meta: DepositMeta
    /// `nil` — дату открытия не трогали. Иначе — новая дата; какой путь применения (тихий/с
    /// подтверждением) уже решён В ЭТОМ экране ДО вызова `onSave` (см. `handleDoneTapped`).
    let openingDate: Date?
}

// MARK: - Экран

/// «Реквизиты счёта» вклада (Коммит 2) — слияние старой генерик-формы (`AccountEditDetailsSheet`)
/// и правки условий (`DepositTermsEditSheet`) в один экран тёмного языка приложения. Используется
/// ТОЛЬКО для `account.kind == .deposit`; остальные типы продолжают открывать прежние экраны
/// (`AccountDetailView.sheetContent(for: .editDetails)` не тронут для них).
struct DepositAccountDetailsSheet: View {
    let account: Account
    let modelContext: ModelContext
    let meta: DepositMeta
    let canEarlyClose: Bool
    let onSave: (DepositAccountDetailsResult) -> Void
    let onProductTransitionCommitted: () -> Void
    let onRequestEarlyClose: () -> Void
    let onRequestDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var note: String
    @State private var includeInTotal: Bool
    @State private var selectedGroupID: UUID?

    @State private var rateText: String
    @State private var openingDate: Date
    @State private var termEnd: Date
    @State private var allowsTopUp: Bool
    @State private var capitalization: AccountDepositCapitalization
    @State private var payoutDay: Int
    @State private var allowsEarlyClose: Bool
    @State private var penaltyText: String
    @State private var isTaxable: Bool

    private enum ActiveFieldSheet: Identifiable {
        case group, rate, openingDate, termEnd, capitalization, payoutDay
        var id: Int { hashValue }
    }
    @State private var activeFieldSheet: ActiveFieldSheet?
    @FocusState private var inputFocused: Bool
    /// Предупреждение перед пересчётом ПОДТВЕРЖДЁННЫХ начислений (Коммит 3, п.2) — показывается
    /// вместо немедленного `onSave`, если дата открытия изменилась и у вклада есть подтверждения.
    @State private var showOpeningDateRecalcWarning = false

    init(
        account: Account,
        modelContext: ModelContext,
        meta: DepositMeta,
        canEarlyClose: Bool,
        onSave: @escaping (DepositAccountDetailsResult) -> Void,
        onProductTransitionCommitted: @escaping () -> Void,
        onRequestEarlyClose: @escaping () -> Void,
        onRequestDelete: @escaping () -> Void
    ) {
        self.account = account
        self.modelContext = modelContext
        self.meta = meta
        self.canEarlyClose = canEarlyClose
        self.onSave = onSave
        self.onProductTransitionCommitted = onProductTransitionCommitted
        self.onRequestEarlyClose = onRequestEarlyClose
        self.onRequestDelete = onRequestDelete

        _name = State(initialValue: account.name)
        _note = State(initialValue: account.note ?? "")
        _includeInTotal = State(initialValue: account.includeInTotal)
        _selectedGroupID = State(initialValue: account.group?.id)

        _rateText = State(initialValue: NSDecimalNumber(decimal: meta.rate).stringValue)
        _openingDate = State(initialValue: account.createdAt)
        _termEnd = State(initialValue: meta.termEnd ?? Date())
        _allowsTopUp = State(initialValue: meta.allowsTopUp)
        _capitalization = State(initialValue: meta.capitalization)
        _payoutDay = State(initialValue: meta.payoutDay ?? Calendar.current.component(.day, from: account.createdAt))
        _allowsEarlyClose = State(initialValue: meta.allowsEarlyClose)
        _penaltyText = State(initialValue: NSDecimalNumber(decimal: (meta.earlyClosePenalty ?? 0) * 100).stringValue)
        _isTaxable = State(initialValue: meta.isTaxable ?? false)
    }

    private var groups: [AccountGroup] {
        let descriptor = FetchDescriptor<AccountGroup>(sortBy: [SortDescriptor(\.order)])
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private var selectedGroup: AccountGroup? { groups.first { $0.id == selectedGroupID } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var rate: Decimal? { Decimal(string: AmountInputFormatter.sanitize(rateText)) }
    private var penalty: Decimal? { Decimal(string: AmountInputFormatter.sanitize(penaltyText)) }

    private var candidateMeta: DepositMeta? {
        guard let rate, rate > 0,
              !allowsEarlyClose || penalty.map({ $0 >= 0 && $0 <= 100 }) == true else { return nil }
        return DepositMeta(
            rate: rate, capitalization: capitalization, termEnd: meta.termEnd == nil ? nil : termEnd,
            payoutDay: capitalization.usesMonthlyPayoutDay ? payoutDay : nil,
            allowsTopUp: allowsTopUp, allowsEarlyClose: allowsEarlyClose,
            earlyClosePenalty: allowsEarlyClose ? penalty.map { $0 / 100 } : nil,
            remindEnd: meta.remindEnd, autoRollover: meta.autoRollover,
            isTaxable: isTaxable
        )
    }

    private var result: DepositAccountDetailsResult? {
        guard !trimmedName.isEmpty, let candidateMeta else { return nil }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return DepositAccountDetailsResult(
            name: trimmedName, group: selectedGroup,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            includeInTotal: includeInTotal, meta: candidateMeta,
            openingDate: openingDateChanged ? openingDate : nil
        )
    }

    /// Сравнение по дню, а не по секундам: пикер даты открытия не редактирует время, полное
    /// равенство `Date` дало бы ложное «изменилось» из-за времени суток исходного `createdAt`.
    private var openingDateChanged: Bool {
        !Calendar.current.isDate(openingDate, inSameDayAs: account.createdAt)
    }

    private var hasConfirmedInterestEvents: Bool {
        DepositOpeningDateRecalculation.hasConfirmedInterest(events: account.events ?? [])
    }

    private var confirmedInterestCount: Int {
        DepositOpeningDateRecalculation.confirmedInterestCount(events: account.events ?? [])
    }

    /// Единственная точка входа кнопки «Готово»: если дата открытия не менялась — сохраняем как
    /// обычно; если менялась и подтверждённых начислений нет — тоже сразу (тихий путь, п.2 брифинга);
    /// если подтверждённые начисления есть — сначала предупреждение, `onSave` вызывается ТОЛЬКО
    /// после явного подтверждения (см. `openingDateWarningSheet`).
    private func handleDoneTapped() {
        guard let result else { return }
        if result.openingDate != nil && hasConfirmedInterestEvents {
            showOpeningDateRecalcWarning = true
        } else {
            onSave(result)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    identityBox
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        accountDetailsSectionCaption(L("accounts_core.deposit_form.section.terms"))
                        termsBox
                        Text(L("accounts_core.deposit_form.opening_date_recalc_hint"))
                            .font(.millioCaption2Regular)
                            .foregroundStyle(AppColors.textTertiary)
                            .padding(.horizontal, AppSpacing.s)
                    }
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        accountDetailsSectionCaption(L("accounts_core.deposit.tax.section_title"))
                        taxBox
                    }
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        accountDetailsSectionCaption(L("accounts_core.transition.title"))
                        productTypeBox
                    }
                    dangerBox
                }
                .padding(AppSpacing.l)
            }
            .navigationTitle(L("accounts_core.detail.sheet.edit.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("accounts_core.detail.sheet.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done"), action: handleDoneTapped)
                    .font(.millioCalloutSemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.m)
                    .padding(.vertical, AppSpacing.xs)
                    .background(Capsule().fill(result == nil ? AppColors.textTertiary : AppColors.brandPrimary))
                    .disabled(result == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("common.done")) { inputFocused = false }
                }
            }
            .sheet(item: $activeFieldSheet) { fieldSheet in
                fieldSheetContent(for: fieldSheet)
            }
            .sheet(isPresented: $showOpeningDateRecalcWarning) {
                openingDateWarningSheet
            }
        }
    }

    // MARK: - Бокс 1: имя/группа/заметка/тотал

    private var identityBox: some View {
        AccountDetailsBoxCard {
            TextField(L("accounts_core.detail.sheet.edit.name"), text: $name)
                .font(.millioTitle3)
                .foregroundStyle(AppColors.textPrimary)
                .focused($inputFocused)
                .padding(.horizontal, AppSpacing.l)
                .padding(.top, AppSpacing.l)
                .padding(.bottom, AppSpacing.m)
            AccountDetailsDivider()
            AccountDetailsFieldRow(
                title: L("accounts_core.detail.sheet.edit.group"),
                value: selectedGroup?.name ?? L("accounts_core.detail.sheet.edit.no_group")
            ) { activeFieldSheet = .group }
            AccountDetailsDivider()
            HStack {
                Text(L("accounts_core.detail.sheet.note_placeholder"))
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: AppSpacing.s)
                TextField(L("accounts_core.detail.sheet.note_add_placeholder"), text: $note)
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .focused($inputFocused)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, AppSpacing.l)
            AccountDetailsDivider()
            AccountDetailsToggleRow(
                title: L("finances.add_account.total_impact.include"), isOn: $includeInTotal
            )
            .padding(.bottom, AppSpacing.xs)
        }
    }

    // MARK: - Бокс 2: условия вклада

    private var termsBox: some View {
        AccountDetailsBoxCard {
            AccountDetailsFieldRow(
                title: L("accounts_core.deposit_form.section.rate"),
                value: rate.map { String(format: "%.2f%%", NSDecimalNumber(decimal: $0).doubleValue) } ?? "—"
            ) { activeFieldSheet = .rate }
            AccountDetailsDivider()
            AccountDetailsFieldRow(
                title: L("accounts_core.deposit_form.opening_date_label"),
                value: openingDate.formatted(date: .abbreviated, time: .omitted)
            ) { activeFieldSheet = .openingDate }
            if meta.termEnd != nil {
                AccountDetailsDivider()
                AccountDetailsFieldRow(
                    title: L("accounts_core.deposit_form.term_end"),
                    value: termEnd.formatted(date: .abbreviated, time: .omitted)
                ) { activeFieldSheet = .termEnd }
            }
            AccountDetailsDivider()
            AccountDetailsToggleRow(title: L("accounts_core.deposit_form.allows_top_up"), isOn: $allowsTopUp)
            AccountDetailsDivider()
            AccountDetailsFieldRow(
                title: L("accounts_core.deposit_form.capitalization_label"),
                value: capitalizationTitle(capitalization)
            ) { activeFieldSheet = .capitalization }
            if capitalization.usesMonthlyPayoutDay {
                AccountDetailsDivider()
                AccountDetailsFieldRow(
                    title: L("accounts_core.deposit_form.payout_day"),
                    value: "\(payoutDay)"
                ) { activeFieldSheet = .payoutDay }
            }
            AccountDetailsDivider()
            AccountDetailsToggleRow(title: L("accounts_core.deposit_form.allows_early_close"), isOn: $allowsEarlyClose)
            if allowsEarlyClose {
                AccountDetailsDivider()
                HStack {
                    Text(L("accounts_core.deposit_form.early_close_penalty"))
                        .font(.millioBody)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    AmountTextField(placeholder: "%", value: $penaltyText)
                        .focused($inputFocused)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
                .frame(minHeight: 44)
                .padding(.horizontal, AppSpacing.l)
                .padding(.bottom, AppSpacing.xs)
            }
        }
    }

    // MARK: - Бокс 3: налог

    private var taxBox: some View {
        AccountDetailsBoxCard {
            AccountDetailsToggleRow(title: L("accounts_core.deposit_form.taxable"), isOn: $isTaxable)
        }
    }

    // MARK: - Бокс 4: тип продукта

    private var productTypeBox: some View {
        AccountDetailsBoxCard {
            NavigationLink {
                AccountProductTransitionEditorView(
                    account: account, modelContext: modelContext, onCommitted: onProductTransitionCommitted
                )
            } label: {
                HStack {
                    Text(L("accounts_core.transition.current"))
                        .font(.millioBody)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer(minLength: AppSpacing.s)
                    Text(AccountProductTransitionPresentation.title(
                        for: account.productType ?? .unknownLegacy,
                        locale: AppLocalization.currentAppLocale
                    ))
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.millioCaption2)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.l)
        }
    }

    // MARK: - Бокс 5: опасная зона

    private var dangerBox: some View {
        AccountDetailsBoxCard {
            if canEarlyClose {
                AccountDetailsFieldRow(
                    title: L("accounts_core.detail.deposit.action.early_close"),
                    value: "", isDestructive: true
                ) {
                    dismiss()
                    onRequestEarlyClose()
                }
                AccountDetailsDivider()
            }
            AccountDetailsFieldRow(
                title: L("accounts_core.detail.action.delete_account"),
                value: "", isDestructive: true
            ) {
                dismiss()
                onRequestDelete()
            }
        }
    }

    // MARK: - Предупреждение перед пересчётом подтверждённых начислений (Коммит 3, п.2)

    /// Показывается ТОЛЬКО когда дата открытия изменилась И у вклада есть подтверждённые
    /// начисления. Красная кнопка — единственный путь, вызывающий `onSave` в этом случае:
    /// без неё `handleDoneTapped` дальше не идёт, `account`/события не меняются.
    private var openingDateWarningSheet: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            Text(L("accounts_core.deposit_form.opening_date_warning.title"))
                .font(.millioBodySemibold)
                .foregroundStyle(AppColors.textPrimary)
            Text(String(format: L("accounts_core.deposit_form.opening_date_warning.message_format"), confirmedInterestCount))
                .font(.millioCalloutRegular)
                .foregroundStyle(AppColors.textSecondary)
            Button(L("accounts_core.deposit_form.opening_date_warning.confirm")) {
                showOpeningDateRecalcWarning = false
                if let result { onSave(result) }
            }
            .font(.millioBodySemibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.error))

            Button(L("accounts_core.detail.sheet.cancel")) {
                showOpeningDateRecalcWarning = false
            }
            .font(.millioBodySemibold)
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
        }
        .padding(AppSpacing.l)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Bottom-sheet пикеры полей

    @ViewBuilder
    private func fieldSheetContent(for field: ActiveFieldSheet) -> some View {
        switch field {
        case .group:
            AccountFieldPickerSheet(title: L("accounts_core.detail.sheet.edit.group")) {
                activeFieldSheet = nil
            } content: {
                List {
                    Button(L("accounts_core.detail.sheet.edit.no_group")) {
                        selectedGroupID = nil
                        activeFieldSheet = nil
                    }
                    ForEach(groups, id: \.id) { group in
                        Button(group.name) {
                            selectedGroupID = group.id
                            activeFieldSheet = nil
                        }
                    }
                }
                .listStyle(.plain)
            }
        case .rate:
            AccountFieldPickerSheet(title: L("accounts_core.deposit_form.section.rate")) {
                activeFieldSheet = nil
            } content: {
                HStack {
                    AmountTextField(placeholder: "0", value: $rateText)
                        .font(.millioTitle)
                        .focused($inputFocused)
                    Text(verbatim: "%").font(.millioTitle3).foregroundStyle(AppColors.brandPrimary)
                }
                .padding(.horizontal, AppSpacing.l)
            }
        case .openingDate:
            AccountFieldPickerSheet(title: L("accounts_core.deposit_form.opening_date_label")) {
                activeFieldSheet = nil
            } content: {
                // `...Date()` — дата открытия не может быть в будущем (тот же запрет, что
                // и в `DepositOpeningDateRecalculation.apply`, здесь дополнительно на уровне UI).
                DatePicker("", selection: $openingDate, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal, AppSpacing.l)
            }
        case .termEnd:
            AccountFieldPickerSheet(title: L("accounts_core.deposit_form.term_end")) {
                activeFieldSheet = nil
            } content: {
                DatePicker("", selection: $termEnd, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal, AppSpacing.l)
            }
        case .capitalization:
            AccountFieldPickerSheet(title: L("accounts_core.deposit_form.capitalization_label")) {
                activeFieldSheet = nil
            } content: {
                List {
                    ForEach(AccountDepositCapitalization.presetCases, id: \.rawValue) { preset in
                        Button(capitalizationTitle(preset)) {
                            capitalization = preset
                            activeFieldSheet = nil
                        }
                    }
                }
                .listStyle(.plain)
            }
        case .payoutDay:
            AccountFieldPickerSheet(title: L("accounts_core.deposit_form.payout_day")) {
                activeFieldSheet = nil
            } content: {
                Picker("", selection: $payoutDay) {
                    ForEach(1...31, id: \.self) { day in Text("\(day)").tag(day) }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            }
        }
    }

    private func capitalizationTitle(_ capitalization: AccountDepositCapitalization) -> String {
        switch capitalization {
        case .none: L("accounts_core.deposit_form.capitalization.none")
        case .daily: L("accounts_core.deposit_form.capitalization.daily")
        case .monthly: L("accounts_core.deposit_form.capitalization.monthly")
        case .quarterly: L("accounts_core.deposit_form.capitalization.quarterly")
        case .customDays: L("accounts_core.deposit_form.capitalization.custom")
        }
    }
}
