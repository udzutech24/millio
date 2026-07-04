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

    private enum ActiveSheet: Identifiable {
        case income
        case expense
        case adjustBalance
        case transfer

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
                    sheet = .income
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
                actionButton(L("accounts_core.detail.action.delete"), icon: "archivebox.fill", isDestructive: true) {
                    showArchiveConfirm = true
                }
            }
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
