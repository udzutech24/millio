import SwiftUI
import SwiftData

/// Карточка счёта нового ядра event-sourcing (Фаза 1a-ui) — минимальный, но рабочий экран:
/// баланс, история событий, доход/расход/корректировка/перевод/архивация. Единственная точка
/// записи — `AccountsCoreService` (AC1/AC7/AC9/AC12), сама view никогда не мутирует баланс напрямую.
struct AccountDetailView: View {
    let account: Account
    let modelContext: ModelContext

    @Environment(\.dismiss) private var dismiss

    @State private var refreshToken = UUID()
    @State private var sheet: ActiveSheet?
    @State private var showArchiveConfirm = false
    @State private var errorMessage: String?
    /// Предупреждение при попытке пополнить непополняемый вклад (брифинг Фазы 3, п.3) — НЕ жёсткий
    /// запрет, alert с подтверждением («да, всё равно» открывает обычную форму дохода).
    @State private var showTopUpWarning = false
    @State private var showEarlyCloseConfirm = false

    private enum ActiveSheet: Identifiable {
        case income
        case expense
        case adjustBalance
        case transfer
        case earlyClose

        var id: Int { hashValue }
    }

    private var service: AccountsCoreService {
        AccountsCoreService(modelContext: modelContext)
    }

    private var balanceToday: Decimal {
        _ = refreshToken // читаем @State, чтобы body пересчитывался после мутаций
        return AccountBalanceEngine.balanceAt(
            events: account.events ?? [],
            kind: account.kind,
            on: Date(),
            marketMeta: account.marketMeta
        )
    }

    private var sortedEvents: [AccountEvent] {
        _ = refreshToken
        return (account.events ?? []).sorted { lhs, rhs in
            lhs.date != rhs.date ? lhs.date > rhs.date : lhs.createdAt > rhs.createdAt
        }
    }

    var body: some View {
        ZStack {
            GradientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    header
                    actionsRow
                    if account.kind == .deposit {
                        depositForecastSection
                    }
                    historySection
                }
                .padding(AppSpacing.l)
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { sheet in
            sheetContent(for: sheet)
        }
        .alert(
            L("accounts_core.detail.delete_confirm.title"),
            isPresented: $showArchiveConfirm
        ) {
            Button(L("accounts_core.detail.action.delete"), role: .destructive) {
                archiveAccount()
            }
            Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) {}
        } message: {
            Text(L("accounts_core.detail.delete_confirm.message"))
        }
        .alert(
            L("accounts_core.detail.deposit.top_up_warning.title"),
            isPresented: $showTopUpWarning
        ) {
            Button(L("accounts_core.detail.deposit.top_up_warning.confirm")) {
                sheet = .income
            }
            Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) {}
        } message: {
            Text(L("accounts_core.detail.deposit.top_up_warning.message"))
        }
        .alert(
            L("accounts_core.detail.deposit.early_close_confirm.title"),
            isPresented: $showEarlyCloseConfirm
        ) {
            Button(L("accounts_core.detail.deposit.action.early_close"), role: .destructive) {
                sheet = .earlyClose
            }
            Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) {}
        } message: {
            Text(L("accounts_core.detail.deposit.early_close_confirm.message"))
        }
        .alert(
            L("accounts_core.detail.error.title"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(formattedBalance)
                    .font(.millioTitle)
                    .foregroundStyle(balanceToday < 0 ? AppColors.error : AppColors.textPrimary)
                Text(account.currency)
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textTertiary)
            }

            if let bankLine {
                Text(bankLine)
                    .font(.millioCalloutRegular)
                    .foregroundStyle(AppColors.textSecondary)
            }

            ForEach(loanInfoLines ?? [], id: \.self) { line in
                Text(line)
                    .font(.millioCalloutRegular)
                    .foregroundStyle(AppColors.textSecondary)
            }

            ForEach(debtInfoLines ?? [], id: \.self) { line in
                Text(line)
                    .font(.millioCalloutRegular)
                    .foregroundStyle(AppColors.textSecondary)
            }

            ForEach(depositInfoLines ?? [], id: \.self) { line in
                Text(line)
                    .font(.millioCalloutRegular)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if let note = account.note, !note.isEmpty {
                Text(note)
                    .font(.millioCalloutRegular)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    private var bankLine: String? {
        guard let cardMeta = account.cardMeta else { return nil }
        var parts: [String] = []
        if let bankRaw = cardMeta.bank, let bank = Bank(rawValue: bankRaw) {
            parts.append(bank.displayName)
        }
        if let last4 = cardMeta.last4, !last4.isEmpty {
            parts.append("•• \(last4)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Обязательства (.loan/.debt) — доп. инфо и кастомные действия (Фаза 2)

    private var loanInfoLines: [String]? {
        guard let meta = account.loanMeta else { return nil }
        var lines: [String] = []
        if meta.rate > 0 {
            lines.append(String(format: L("accounts_core.detail.loan.rate_format"), NSDecimalNumber(decimal: meta.rate).doubleValue))
        }
        if let payment = meta.monthlyPayment {
            lines.append(String(format: L("accounts_core.detail.loan.monthly_payment_format"), NSDecimalNumber(decimal: payment).doubleValue, account.currency))
        }
        if let termEnd = meta.termEnd {
            lines.append(String(format: L("accounts_core.detail.loan.term_end_format"), termEnd.formatted(date: .abbreviated, time: .omitted)))
        }
        return lines.isEmpty ? nil : lines
    }

    private var debtInfoLines: [String]? {
        guard let meta = account.debtMeta else { return nil }
        var lines: [String] = [
            meta.direction == .owedToMe
                ? L("accounts_core.detail.debt.direction.owed_to_me")
                : L("accounts_core.detail.debt.direction.owed_by_me")
        ]
        if let counterparty = meta.counterparty, !counterparty.isEmpty {
            lines.append(String(format: L("accounts_core.detail.debt.counterparty_format"), counterparty))
        }
        if let dueDate = meta.dueDate {
            lines.append(String(format: L("accounts_core.detail.debt.due_date_format"), dueDate.formatted(date: .abbreviated, time: .omitted)))
        }
        return lines
    }

    /// Заголовок кнопки «доход»-слота — для обязательств это «Платёж»/«Погашение», не «Доход».
    private var incomeActionTitle: String {
        switch account.kind {
        case .loan: return L("accounts_core.detail.action.payment")
        case .debt: return L("accounts_core.detail.action.repay")
        default: return L("accounts_core.detail.action.add_income")
        }
    }

    /// Заголовок кнопки «расход»-слота — для обязательств это «Увеличить долг»/«Увеличить».
    private var expenseActionTitle: String {
        switch account.kind {
        case .loan: return L("accounts_core.detail.action.increase_debt")
        case .debt: return L("accounts_core.detail.action.increase")
        default: return L("accounts_core.detail.action.add_expense")
        }
    }

    /// `.loan` использует собственный движок (loanSignMap) — income ВСЕГДА уменьшает долг,
    /// вне зависимости от направления. `.debt` использует ленту генерик-движка (как cash) —
    /// направление знака зависит от того, кому должны: owedToMe требует ПРОТИВОПОЛОЖНОГО типа
    /// события, чтобы «погашение» всегда уменьшало |баланс| (см. брифинг Фазы 2, п.2).
    private var incomeSheetEventType: AccountEventType {
        guard account.kind == .debt, account.debtMeta?.direction == .owedToMe else { return .income }
        return .expense
    }

    private var expenseSheetEventType: AccountEventType {
        guard account.kind == .debt, account.debtMeta?.direction == .owedToMe else { return .expense }
        return .income
    }

    // MARK: - Вклад (.deposit) — доп. инфо, прогнозы «чистыми», досрочное закрытие (Фаза 3)

    private var depositInfoLines: [String]? {
        guard let meta = account.depositMeta else { return nil }
        var lines: [String] = []
        lines.append(String(format: L("accounts_core.detail.deposit.rate_format"), NSDecimalNumber(decimal: meta.rate).doubleValue))
        lines.append(meta.allowsTopUp ? L("accounts_core.detail.deposit.badge.top_up_allowed") : L("accounts_core.detail.deposit.badge.top_up_denied"))
        if let termEnd = meta.termEnd {
            let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: termEnd).day ?? 0
            if daysLeft >= 0 {
                lines.append(String(format: L("accounts_core.detail.deposit.days_left_format"), daysLeft))
            } else {
                lines.append(L("accounts_core.detail.deposit.term_ended"))
            }
        } else {
            lines.append(L("accounts_core.detail.deposit.savings_badge"))
        }
        return lines
    }

    /// Начислено % всего (Σ interest ≤ сегодня) — не прогноз, факт.
    private var accruedInterestTotal: Decimal {
        (account.events ?? [])
            .filter { $0.type == .interest && $0.date <= Date() }
            .reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
    }

    /// Прогноз реплеем вперёд (AC: `balanceAt(futureDate)` — та же функция, что и для истории,
    /// отдельного калькулятора прогнозов нет). `nil`, если счёт — не вклад/накопительный счёт.
    private var monthlyForecastGross: Decimal? {
        guard account.kind == .deposit else { return nil }
        let today = Date()
        guard let inMonth = Calendar.current.date(byAdding: .month, value: 1, to: today) else { return nil }
        let balanceIn1Month = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .deposit, on: inMonth)
        return max(0, balanceIn1Month - balanceToday)
    }

    private var termForecastGross: Decimal? {
        guard account.kind == .deposit, let termEnd = account.depositMeta?.termEnd else { return nil }
        let balanceAtTerm = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .deposit, on: termEnd)
        return max(0, balanceAtTerm - balanceToday)
    }

    /// Эффективная ставка налога «чистыми» для ЭТОГО вклада за текущий календарный год (спека §2.8):
    /// доля Σ interest всех вкладов владельца, отнесённая налогом на ЭТОТ счёт, делённая на его gross.
    /// Приближение для прогноза (месяц/срок ещё не наступили — используем ставку текущего года).
    /// TODO Фаза 3+: конвертация процентов валютных вкладов в ₽ курсом даты события (см. докстринг
    /// `DepositTaxCalculator`) — сейчас берём amount как есть, корректно только для ₽-вкладов.
    private var depositTaxAllocationForThisAccount: DepositTaxAllocation? {
        guard account.kind == .deposit else { return nil }
        let year = Calendar.current.component(.year, from: Date())
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.kindRaw == "deposit" })
        guard let allDeposits = try? modelContext.fetch(descriptor) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }

        let inputs: [DepositTaxCalculator.InterestEventInput] = allDeposits.flatMap { deposit -> [DepositTaxCalculator.InterestEventInput] in
            (deposit.events ?? [])
                .filter { $0.type == .interest && $0.date >= yearStart && $0.date < yearEnd }
                .map { DepositTaxCalculator.InterestEventInput(accountID: deposit.id, amountRUB: $0.amount ?? 0) }
        }

        let result = DepositTaxCalculator.calculate(interestEventsInRUB: inputs, year: year, settings: SettingsManager.shared.depositTaxSettings)
        return result.perAccount.first(where: { $0.accountID == account.id })
    }

    /// Эффективная ставка налога «чистыми» для ЭТОГО вклада за текущий год — доля, применяемая
    /// к ПРОГНОЗУ (месяц/срок ещё не наступили, точного расчёта для будущих сумм в этом году нет).
    private var effectiveNetTaxRate: Decimal {
        guard let allocation = depositTaxAllocationForThisAccount, allocation.grossInterestRUB > 0 else { return 0 }
        return allocation.allocatedTaxRUB / allocation.grossInterestRUB
    }

    /// Налог за ТЕКУЩИЙ год, уже начисленный этому вкладу (спека §2.8: «налог за год ≈Z») — оценка,
    /// не событие (не порождает expense, см. докстринг `DepositTaxCalculator`).
    private var yearlyTaxEstimateForThisAccount: Decimal {
        depositTaxAllocationForThisAccount?.allocatedTaxRUB ?? 0
    }

    private func netAmount(_ gross: Decimal) -> Decimal {
        gross * (1 - effectiveNetTaxRate)
    }

    private var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: balanceToday)) ?? "0"
    }

    // MARK: - Actions

    private var actionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.s) {
                actionButton(incomeActionTitle, icon: "plus.circle.fill") {
                    requestTopUpOrOpenIncomeSheet()
                }
                actionButton(expenseActionTitle, icon: "minus.circle.fill") {
                    sheet = .expense
                }
                actionButton(L("accounts_core.detail.action.adjust_balance"), icon: "slider.horizontal.3") {
                    sheet = .adjustBalance
                }
                actionButton(L("accounts_core.detail.action.transfer"), icon: "arrow.left.arrow.right") {
                    sheet = .transfer
                }
                if account.kind == .deposit, account.depositMeta?.allowsEarlyClose == true {
                    actionButton(L("accounts_core.detail.deposit.action.early_close"), icon: "xmark.circle.fill", isDestructive: true) {
                        showEarlyCloseConfirm = true
                    }
                }
                actionButton(L("accounts_core.detail.action.delete"), icon: "archivebox.fill", isDestructive: true) {
                    showArchiveConfirm = true
                }
            }
        }
    }

    /// Непополняемый вклад (Фаза 3, брифинг п.3): попытка пополнения — предупреждение с
    /// подтверждением, НЕ жёсткий запрет («да, всё равно» открывает обычную форму дохода).
    private func requestTopUpOrOpenIncomeSheet() {
        if account.kind == .deposit, account.depositMeta?.allowsTopUp == false {
            showTopUpWarning = true
        } else {
            sheet = .income
        }
    }

    private func actionButton(_ title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.millioHeadline)
                Text(title)
                    .font(.millioCaptionRegular)
            }
            .foregroundStyle(isDestructive ? AppColors.error : AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                    .fill(AppColors.iconBackground)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Прогноз вклада «грязными/чистыми» (Фаза 3)

    private var depositForecastSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(L("accounts_core.detail.deposit.forecast_title"))
                .font(.millioCaption)
                .foregroundStyle(AppColors.textTertiary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                forecastRow(L("accounts_core.detail.deposit.accrued_total"), amount: accruedInterestTotal)

                if let monthlyGross = monthlyForecastGross {
                    forecastRow(L("accounts_core.detail.deposit.per_month_gross"), amount: monthlyGross)
                    forecastRow(L("accounts_core.detail.deposit.per_month_net"), amount: netAmount(monthlyGross))
                }

                if let termGross = termForecastGross {
                    forecastRow(L("accounts_core.detail.deposit.per_term_gross"), amount: termGross)
                    forecastRow(L("accounts_core.detail.deposit.per_term_net"), amount: netAmount(termGross))
                }

                Text(String(format: L("accounts_core.detail.deposit.tax_estimate_format"), "\(formattedAmount(yearlyTaxEstimateForThisAccount)) ₽"))
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(AppSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                    .fill(AppColors.iconBackground)
            )
        }
    }

    private func forecastRow(_ title: String, amount: Decimal) -> some View {
        HStack {
            Text(title)
                .font(.millioCalloutRegular)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text("\(formattedAmount(amount)) \(account.currency)")
                .font(.millioBodySemibold)
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    private func formattedAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0"
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(L("accounts_core.detail.history_title"))
                .font(.millioCaption)
                .foregroundStyle(AppColors.textTertiary)
                .textCase(.uppercase)

            if sortedEvents.isEmpty {
                Text(L("accounts_core.detail.no_events"))
                    .font(.millioCalloutRegular)
                    .foregroundStyle(AppColors.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(sortedEvents, id: \.id) { event in
                        eventRow(event)
                        if event.id != sortedEvents.last?.id {
                            Divider().background(Color.white.opacity(0.08))
                        }
                    }
                }
            }
        }
    }

    private func eventRow(_ event: AccountEvent) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(eventTypeLabel(event.type))
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textPrimary)
                Text(event.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.textTertiary)
                if let note = event.note, !note.isEmpty {
                    Text(note)
                        .font(.millioCaptionRegular)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            Spacer()
            if let amount = event.amount {
                Text(signedAmountText(amount, type: event.type))
                    .font(.millioBodySemibold)
                    .foregroundStyle(amount < 0 ? AppColors.error : AppColors.textPrimary)
            }
        }
        .padding(.vertical, AppSpacing.s)
    }

    private func signedAmountText(_ amount: Decimal, type: AccountEventType) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "0"
    }

    private func eventTypeLabel(_ type: AccountEventType) -> String {
        switch type {
        case .openingBalance: return L("accounts_core.detail.event.opening_balance")
        case .income: return L("accounts_core.detail.event.income")
        case .expense: return L("accounts_core.detail.event.expense")
        case .transferOut: return L("accounts_core.detail.event.transfer_out")
        case .transferIn: return L("accounts_core.detail.event.transfer_in")
        case .adjustment: return L("accounts_core.detail.event.adjustment")
        case .interest: return L("accounts_core.detail.event.interest")
        case .fee: return L("accounts_core.detail.event.fee")
        case .extraPayment: return L("accounts_core.detail.event.extra_payment")
        default: return type.rawValue
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .income:
            AccountEventEntrySheet(
                title: incomeActionTitle,
                onSave: { amount, date, note in
                    perform { try service.recordEvent(account: account, type: incomeSheetEventType, amount: amount, date: date, note: note) }
                }
            )
        case .expense:
            // ВАЖНО: amount передаётся МАГНИТУДОЙ (положительным числом) — движок сам применяет
            // знак по типу события (cashLikeSignMap(.expense) == -1). Ранее здесь стояло `-amount`,
            // что давало ДВОЙНОЕ отрицание и увеличивало баланс вместо уменьшения (найдено при
            // разборе Фазы 2 — см. регрессионный тест engineA_expenseSignConventionMatchesRecordEvent).
            AccountEventEntrySheet(
                title: expenseActionTitle,
                onSave: { amount, date, note in
                    perform { try service.recordEvent(account: account, type: expenseSheetEventType, amount: amount, date: date, note: note) }
                }
            )
        case .adjustBalance:
            AccountAdjustBalanceSheet(
                currentBalance: balanceToday,
                onSave: { newValue in
                    perform { try service.adjustBalance(account: account, to: newValue) }
                }
            )
        case .transfer:
            AccountTransferSheet(
                source: account,
                modelContext: modelContext,
                onSave: { destination, amount in
                    perform { try service.transfer(from: account, to: destination, amountInSourceCurrency: amount) }
                }
            )
        case .earlyClose:
            AccountEarlyCloseSheet(
                source: account,
                modelContext: modelContext,
                onSave: { destination in
                    performEarlyClose(transferTo: destination)
                }
            )
        }
    }

    /// Досрочное закрытие вклада — отдельно от generic `perform` (успех архивирует счёт и закрывает
    /// карточку, а не просто закрывает sheet — счёт больше не открыть, он ушёл в архив).
    private func performEarlyClose(transferTo destination: Account) {
        do {
            try service.earlyCloseDeposit(account, transferTo: destination)
            sheet = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            refreshToken = UUID()
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archiveAccount() {
        do {
            try service.archiveAccount(account)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
