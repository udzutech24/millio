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
    /// S8 (риск плана): архивация ненулевого счёта «прячет деньги» на графике без объяснения.
    /// Вместо прямого архивирования — выбор «перевести остаток» (тогда ступеньки не будет)
    /// или «закрыть с остатком» (архивировать как есть, осознанно).
    @State private var showNonZeroBalanceArchiveWarning = false
    /// Bottom sheet «···» вклада (Коммит 1) — заменяет системный `Menu` у верхнего края.
    @State private var showDepositActionsSheet = false
    /// Оформление счёта грузится ОДИН раз на открытие экрана, а не из тела `body`: `body`
    /// пересчитывается на каждую мутацию, а редактора оформления на этом экране нет.
    @State private var appearance: AccountAppearanceSnapshot?

    private enum ActiveSheet: Identifiable {
        case income
        case expense
        case adjustBalance
        case editDetails
        case transfer
        case earlyClose
        case depositTopUp
        case depositAdjustBalance
        case depositTerms
        case depositMaturity
        case buy
        case sell
        case dividend
        case fee
        case refund
        case revalue

        var id: Int { hashValue }
    }

    private var service: AccountsCoreService {
        AccountsCoreService(modelContext: modelContext)
    }

    private var isDebitProduct: Bool {
        DebitCardContract.products.contains(account.productType ?? .unknownLegacy)
    }

    /// Провайдер живых цен нового ядра (Фаза 4) — синхронный снэпшот append-only кэша
    /// `HistoricalAssetPrice`, читается один раз на пересчёт body. `nil` для не-рыночных счетов.
    private var priceProviderForThisAccount: MarketPriceProviding? {
        guard account.kind == .marketInvestment, let meta = account.marketMeta else { return nil }
        return AccountMarketPriceService(modelContext: modelContext).makeSnapshotProvider(symbols: [meta.symbol])
    }

    private var balanceToday: Decimal {
        _ = refreshToken // читаем @State, чтобы body пересчитывался после мутаций
        // Ф1: шапка «Остаток» = подтверждённый баланс, тот же, что в строке списка и в тоталах.
        return AccountBalanceEngine.balanceAt(
            events: DepositConfirmedBalanceResolver.confirmedEvents(
                account.events ?? [], accountID: account.id, kind: account.kind
            ),
            kind: account.kind,
            on: Date(),
            priceProvider: priceProviderForThisAccount,
            marketMeta: account.marketMeta
        )
    }

    private var sortedEvents: [AccountEvent] {
        _ = refreshToken
        return (account.events ?? [])
            .filter { event in
                if account.kind == .deposit {
                    return !DepositDetailPresentation.isGeneratedForecastEvent(event, accountID: account.id)
                }
                return !(account.kind == .marketInvestment && event.type == .openingBalance && (event.amount ?? 0) == 0)
            }
            .sorted { lhs, rhs in
            lhs.date != rhs.date ? lhs.date > rhs.date : lhs.createdAt > rhs.createdAt
        }
    }

    private var depositPresentation: DepositDetailPresentation? {
        guard account.kind == .deposit else { return nil }
        _ = refreshToken
        let snapshot = DepositFinancialContract.snapshot(
            accountID: account.id,
            currency: account.currency,
            openingDate: account.createdAt,
            archivedAt: account.archivedAt,
            deletedAt: account.deletedAt,
            meta: account.depositMeta,
            events: account.events ?? [],
            asOf: Date(),
            calendarPolicy: DepositCalendarPolicy(timeZone: .current)
        )
        return DepositDetailPresentation.make(snapshot: snapshot)
    }

    /// Сумма hero — ровно то же число, что в строке списка «Счета» и в тоталах: у кредитки это
    /// долг со знаком минус, а не доступный лимит. Второго определения баланса не заводим.
    private var heroAmount: Decimal {
        AccountTotalsContribution.signedValue(
            rawBalance: balanceToday,
            kind: account.kind,
            creditLimit: account.cardMeta?.creditLimit
        )
    }

    private var heroPresentation: AccountHeroPresentation {
        AccountHeroPresentation.make(
            key: account.id.uuidString,
            name: account.name,
            appearance: appearance,
            fallbackIconName: account.kind.fallbackIconName,
            subtitle: heroSubtitle,
            typeTitle: heroTypeTitle,
            amountText: AccountRowAmountFormatter.text(
                NSDecimalNumber(decimal: heroAmount).doubleValue,
                isHidden: false,
                maximumFractionDigits: account.kind == .marketInvestment ? 2 : 0
            ),
            currencySymbol: MonetaCurrency(rawValue: account.currency)?.symbol ?? account.currency,
            isNegative: heroAmount < 0,
            detailLines: heroDetailLines,
            badges: heroBadges
        )
    }

    /// Тип продукта на hero. Кредитка — не отдельный `AccountKind` (это `debitCard` с лимитом),
    /// поэтому её название разрешается по `productType`, а не по `kind`.
    private var heroTypeTitle: String {
        account.productType == .creditCard
            ? L("accounts_core.detail.type.credit_card")
            : account.kind.localizedTitle
    }

    /// Вторая строка идентичности: у рыночной позиции — тикер, у карты — банк и `•• last4`.
    private var heroSubtitle: String? {
        if account.kind == .marketInvestment, let symbol = account.marketMeta?.symbol, !symbol.isEmpty {
            return symbol.uppercased()
        }
        return bankLine
    }

    private var heroDetailLines: [String] {
        var lines: [String] = []
        lines.append(contentsOf: loanInfoLines ?? [])
        lines.append(contentsOf: debtInfoLines ?? [])
        lines.append(contentsOf: depositInfoLines ?? [])
        if let creditHeroLine { lines.append(creditHeroLine) }
        if account.kind == .marketInvestment {
            // Нереализованный P/L был на прежнем `stockHero` — теряться при переезде он не должен.
            lines.append("\(signedAmountText(unrealizedPL, type: .adjustment)) \(account.currency)")
        }
        if let note = account.note, !note.isEmpty { lines.append(note) }
        return lines
    }

    /// Кредитка на hero: доступный лимит и дата ближайшего платежа. Подробные метрики (утилизация,
    /// проценты, комиссии) остаются в `CreditCardDetailSection` — hero их не дублирует.
    private var creditHeroLine: String? {
        guard account.productType == .creditCard, let limit = account.cardMeta?.creditLimit else { return nil }
        guard let snapshot = CreditCardFinancialContract.snapshot(
            rawAvailableBalance: balanceToday,
            creditLimit: limit,
            events: account.events ?? []
        ) else { return nil }
        var parts = [String(
            format: L("accounts_core.detail.credit.available_format"),
            NSDecimalNumber(decimal: snapshot.availableLimit).doubleValue,
            account.currency
        )]
        if let settings = CreditCardPaymentSettingsStore().load(accountID: account.id),
           let status = CreditCardPaymentPolicy.status(
               settings: settings,
               graceDays: account.cardMeta?.graceDays,
               now: Date(),
               calendar: .current
           ) {
            parts.append(String(
                format: L("accounts_core.detail.credit.payment_due_format"),
                status.dueDate.formatted(date: .abbreviated, time: .omitted)
            ))
        }
        return parts.joined(separator: " · ")
    }

    private var heroBadges: [AccountHeroPresentation.Badge] {
        var badges: [AccountHeroPresentation.Badge] = []
        if account.archivedAt != nil {
            badges.append(.init(text: L("accounts_core.detail.badge.archived"), systemImage: "archivebox"))
        }
        if !account.includeInTotal {
            badges.append(.init(text: L("accounts_core.detail.total.excluded"), systemImage: "sum"))
        }
        if account.kind == .marketInvestment {
            badges.append(.init(
                text: isPriceStale
                    ? L("accounts_core.detail.market.price_stale_badge")
                    : L("accounts_core.detail.market.price_today_badge"),
                systemImage: isPriceStale ? "clock.badge.exclamationmark" : "bolt.fill",
                isWarning: isPriceStale
            ))
        }
        return badges
    }

    private var debitSnapshot: DebitCardSnapshot? {
        guard isDebitProduct else { return nil }
        _ = refreshToken
        return DebitCardContract.snapshot(account: account, events: account.events ?? [], on: Date())
    }

    var body: some View {
        ZStack {
            GradientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    // Ф3: идентичность счёта рисует ТОЛЬКО hero — для всех типов сразу.
                    // Исключение — недвижимость: её шапка это фото-обложка объекта (баланса на ней
                    // нет), заменить её градиентом означало бы удалить фотографии пользователя.
                    if AccountDetailDescriptor.resolve(for: account).kind != .realEstate {
                        // Вклад — единственное исключение из стандартной начинки hero: несёт
                        // баланс/статус/метрики вклада вместо имени/бейджа/иконки счёта (см.
                        // `DepositHeroContent`). Второй, отдельной карточки статуса вклада после
                        // этого существовать не должно — вся её начинка переехала сюда.
                        if let investmentPresentation {
                            // Рыночная позиция: та же логика замены standardContent, что у вклада —
                            // hero несёт стоимость/прибыль/график позиции вместо identity-строки
                            // счёта (имя уже в navigation title, тикер отдельно не дублируем).
                            AccountHeroCardView(presentation: heroPresentation) {
                                InvestmentHeroContent(presentation: investmentPresentation)
                            }
                        } else if let depositPresentation {
                            AccountHeroCardView(presentation: heroPresentation) {
                                DepositHeroContent(
                                    presentation: depositPresentation,
                                    openingDate: account.createdAt,
                                    meta: account.depositMeta
                                )
                            }
                        } else {
                            AccountHeroCardView(presentation: heroPresentation)
                        }
                    }
                    if AccountDetailDescriptor.resolve(for: account).kind == .realEstate {
                        RealEstateDetailSection(
                            account: account,
                            modelContext: modelContext,
                            refreshToken: refreshToken,
                            onEdit: { sheet = .editDetails }
                        )
                    }
                    if let depositPresentation {
                        DepositDetailSection(
                            presentation: depositPresentation,
                            taxPresentation: depositTaxPresentation,
                            onAction: handleDepositAction
                        )
                    } else if account.productType == .creditCard {
                        CreditCardDetailSection(account: account, rawBalance: balanceToday)
                    } else if let snapshot = debitSnapshot {
                        DebitCardDetailSection(account: account, snapshot: snapshot)
                    }
                    if account.kind != .deposit && account.archivedAt == nil && account.deletedAt == nil
                        && (debitSnapshot?.canWrite ?? true) {
                        actionsRow
                    }
                    historySection
                }
                .padding(AppSpacing.l)
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let presentation = depositPresentation,
               !depositOverflowActions(presentation).isEmpty || canEditDepositDetails {
                ToolbarItem(placement: .topBarTrailing) {
                    // Коммит 1: bottom sheet вместо `Menu` у верхнего края — тот же список пунктов,
                    // «Реквизиты счёта»/«Изменить условия» слиты в один (см. `depositActionSheetItems`).
                    Button {
                        showDepositActionsSheet = true
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel(L("accounts_core.detail.action.edit"))
                }
            } else if account.productType == .creditCard {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(L("accounts_core.detail.action.edit"), systemImage: "pencil") {
                            sheet = .editDetails
                        }
                        Button(archiveActionTitle, systemImage: "archivebox", role: .destructive) {
                            requestArchiveConfirmation()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel(L("accounts_core.detail.action.edit"))
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(for: sheet)
        }
        .sheet(isPresented: $showDepositActionsSheet) {
            if let presentation = depositPresentation {
                AccountActionsSheet(
                    accountName: account.name,
                    accountTypeTitle: account.kind.localizedTitle,
                    items: depositActionSheetItems(presentation),
                    onDismiss: { showDepositActionsSheet = false }
                )
            }
        }
        .alert(
            L("accounts_core.detail.delete_confirm.title"),
            isPresented: $showArchiveConfirm
        ) {
            Button(archiveActionTitle, role: .destructive) {
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
            L("accounts_core.detail.delete_nonzero_confirm.title"),
            isPresented: $showNonZeroBalanceArchiveWarning
        ) {
            Button(L("accounts_core.detail.delete_nonzero_confirm.transfer_first")) {
                sheet = .transfer
            }
            Button(L("accounts_core.detail.delete_nonzero_confirm.close_anyway"), role: .destructive) {
                archiveAccount()
            }
            Button(L("accounts_core.detail.sheet.cancel"), role: .cancel) {}
        } message: {
            Text(L("accounts_core.detail.delete_nonzero_confirm.message"))
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
        .task(id: account.id) {
            appearance = try? AccountAppearanceStore(context: modelContext)
                .loadSnapshots()[account.id]
            guard account.kind == .marketInvestment else { return }
            await AccountMarketPriceService(modelContext: modelContext).refreshTodayPrices()
            refreshToken = UUID()
        }
    }

    // MARK: - Header

    /// Прежние `standardHeader` и `stockHero` сняты в Ф3: их содержимое переехало в
    /// `AccountHeroCardView` (`heroDetailLines` / `heroBadges` / `heroSubtitle`).
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
    ///
    /// ⚠️ Единственные два вызова, которые ОСОЗНАННО остаются на сыром движке (Ф1 плана
    /// `2026-08-26__deposit-confirmed-balance-unification.md`, acceptance criterion 3): прогноз
    /// «через месяц/к сроку» по определению состоит из ещё не подтверждённых начислений.
    /// Через `DepositConfirmedBalanceResolver` он дал бы тождественный ноль.
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
    /// Foreign interest is deliberately incomplete here until event-date historical evidence is
    /// loaded asynchronously. Relabelling its nominal amount as RUB would fabricate a tax value.
    private var depositTaxAllocationForThisAccount: DepositTaxAllocation? {
        guard account.kind == .deposit else { return nil }
        let year = Calendar.current.component(.year, from: Date())
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.kindRaw == "deposit" })
        guard let allDeposits = try? modelContext.fetch(descriptor) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }

        let yearDeposits = allDeposits.flatMap { deposit in
            (deposit.events ?? []).filter {
                $0.type == .interest && $0.date >= yearStart && $0.date < yearEnd && $0.date <= Date()
                    && !DepositDetailPresentation.isGeneratedForecastEvent($0, accountID: deposit.id)
            }
                .map { (deposit, $0) }
        }
        guard yearDeposits.allSatisfy({ $0.0.currency.uppercased() == "RUB" }) else { return nil }
        let inputs: [DepositTaxCalculator.InterestEventInput] = yearDeposits.map { deposit, event in
            DepositTaxCalculator.InterestEventInput(accountID: deposit.id, amountRUB: event.amount ?? 0)
        }

        let result = DepositTaxCalculator.calculate(interestEventsInRUB: inputs, year: year, settings: SettingsManager.shared.depositTaxSettings)
        return result.perAccount.first(where: { $0.accountID == account.id })
    }

    private var depositTaxPresentation: DepositTaxPresentation? {
        guard account.kind == .deposit else { return nil }
        let year = Calendar.current.component(.year, from: Date())
        let deposits = (try? modelContext.fetch(FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.kindRaw == "deposit" }
        ))) ?? []
        let events = deposits.flatMap { deposit in
            (deposit.events ?? []).compactMap { event -> DepositTaxEvent? in
                guard event.type == .interest, event.date <= Date(),
                      !DepositDetailPresentation.isGeneratedForecastEvent(event, accountID: deposit.id),
                      let amount = event.amount else { return nil }
                return .init(accountID: deposit.id, date: event.date, currency: deposit.currency, amount: amount)
            }
        }
        return DepositTaxPresentationBuilder.make(
            events: events, year: year, settings: SettingsManager.shared.depositTaxSettings,
            historicalFX: [:], calendar: .current
        )
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

    // MARK: - Рыночный счёт (.marketInvestment) — qty/цена/P&L (Фаза 4)

    /// UI consumes the pure FIFO replay; it must not grow a second quantity/cost-basis engine.
    private var stockSnapshot: StockPositionSnapshot? {
        _ = refreshToken
        return try? StockLotEngine.replay(events: account.events ?? [], on: Date())
    }

    private var currentQuantity: Decimal {
        stockSnapshot?.quantity ?? 0
    }

    private var todayQuote: HistoricalAssetPrice? {
        guard let symbol = account.marketMeta?.symbol.uppercased() else { return nil }
        let dayKey = AccountEvent.dayKey(for: Date())
        let descriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate { $0.symbol == symbol && $0.dayKey == dayKey }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private var latestCachedQuote: HistoricalAssetPrice? {
        guard let symbol = account.marketMeta?.symbol.uppercased() else { return nil }
        let descriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate { $0.symbol == symbol },
            sortBy: [SortDescriptor(\.dayKey, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Unrealized P&L excludes realized proceeds and is based only on remaining FIFO lots.
    private var unrealizedPL: Decimal {
        stockSnapshot?.unrealizedProfitLoss(at: currentUnitPrice) ?? 0
    }

    private var stockTotalReturn: Decimal {
        stockSnapshot?.totalReturn(at: currentUnitPrice) ?? 0
    }

    /// Текущая цена за единицу + признак «не сегодняшняя» (пометка «посл. известная»). `nil` цены из
    /// live-кэша (`AccountMarketPriceService`) трактуем как «нет сегодняшних данных» — падаем на
    /// последнюю цену buy/sell/revaluation из событий (офлайн/auth-error, брифинг Фазы 4, задача 2).
    private var currentUnitPrice: Decimal {
        if let todayQuote { return todayQuote.price }
        if let latestCachedQuote { return latestCachedQuote.price }
        return (account.events ?? [])
            .sorted { $0.date < $1.date }
            .last(where: { ($0.type == .buy || $0.type == .sell) && $0.unitPrice != nil })?
            .unitPrice ?? 0
    }

    /// `true`, если сегодняшней живой цены в кэше нет вовсе — карточка показывает пометку
    /// «посл. известная цена» (упрощение, задокументировано: не различаем «вчера»/«неделю назад»).
    private var isPriceStale: Bool {
        todayQuote == nil
    }

    /// Данные hero-карточки рыночной позиции (единая карточка вместо hero + плашка «ПОЗИЦИЯ» +
    /// таблица на 8 строк). `nil`, если реплей событий упал — тогда hero молча падает на
    /// стандартную начинку счёта вместо падения экрана целиком (см. `AccountDetailView.body`).
    private var investmentPresentation: InvestmentHeroPresentation? {
        guard account.kind == .marketInvestment, let snapshot = stockSnapshot else { return nil }
        _ = refreshToken
        let invested = snapshot.openCostBasis
        // Знаменатель доходности — себестоимость ОТКРЫТОЙ позиции, а не сумма всех покупок за
        // историю: снапшот не хранит второе число, а плодить его ради процента не стоит (KISS).
        let returnPercent: Decimal? = invested > 0 ? (stockTotalReturn / invested) * 100 : nil
        return InvestmentHeroPresentation(
            currency: account.currency,
            currencySymbol: MonetaCurrency(rawValue: account.currency)?.symbol ?? account.currency,
            positionValue: balanceToday,
            totalReturn: stockTotalReturn,
            returnPercent: returnPercent,
            quantity: snapshot.quantity,
            currentUnitPrice: currentUnitPrice,
            averageUnitCost: snapshot.averageUnitCost,
            invested: invested,
            dividends: snapshot.dividends,
            realizedProfitLoss: snapshot.realizedProfitLoss,
            fees: snapshot.totalFees,
            portfolioSharePercent: portfolioSharePercent,
            sparkline: priceHistoryPoints,
            sparklineMonths: sparklineMonths,
            latestPriceAsOf: latestPriceAsOf
        )
    }

    /// Реальные точки цены символа из append-only кэша `HistoricalAssetPrice` — ничего не
    /// синтезируем. Меньше 2 точек (нет истории или только сегодняшняя live-цена) — график не
    /// строим вовсе, а не рисуем плоскую линию из одной точки.
    private var priceHistoryPoints: [InvestmentPricePoint] {
        guard let symbol = account.marketMeta?.symbol, !symbol.isEmpty else { return [] }
        let upper = symbol.uppercased()
        let descriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate<HistoricalAssetPrice> { $0.symbol == upper },
            sortBy: [SortDescriptor(\.dayKey, order: .forward)]
        )
        guard let rows = try? modelContext.fetch(descriptor), rows.count >= 2 else { return [] }
        // ~6 месяцев — дальше линия на sparkline-высоте карточки становится нечитаемой.
        return rows.suffix(183).compactMap { row in
            guard let date = Self.dayKeyFormatter.date(from: row.dayKey) else { return nil }
            return InvestmentPricePoint(date: date, price: NSDecimalNumber(decimal: row.price).doubleValue)
        }
    }

    private var sparklineMonths: Int {
        guard let first = priceHistoryPoints.first?.date, let last = priceHistoryPoints.last?.date else { return 0 }
        let months = Calendar.current.dateComponents([.month], from: first, to: last).month ?? 0
        return max(months, 1)
    }

    private var latestPriceAsOf: Date? {
        guard !priceHistoryPoints.isEmpty else { return nil }
        return todayQuote?.fetchedAt ?? latestCachedQuote?.fetchedAt
    }

    private static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Та же цепочка фолбэков, что у `currentUnitPrice`, но параметризованная — нужна для чужих
    /// позиций в `portfolioSharePercent` (там не годится завязка на `account.marketMeta`).
    private func liveOrCachedPrice(symbol: String, events: [AccountEvent]) -> Decimal {
        let upper = symbol.uppercased()
        let dayKey = AccountEvent.dayKey(for: Date())
        let todayDescriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate<HistoricalAssetPrice> { $0.symbol == upper && $0.dayKey == dayKey }
        )
        if let today = try? modelContext.fetch(todayDescriptor).first { return today.price }
        let cachedDescriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate<HistoricalAssetPrice> { $0.symbol == upper },
            sortBy: [SortDescriptor(\.dayKey, order: .reverse)]
        )
        if let cached = try? modelContext.fetch(cachedDescriptor).first { return cached.price }
        return events
            .sorted { $0.date < $1.date }
            .last(where: { ($0.type == .buy || $0.type == .sell) && $0.unitPrice != nil })?
            .unitPrice ?? 0
    }

    /// Доля позиции в общей стоимости открытых рыночных счетов ТОЙ ЖЕ валюты. Кросс-валютные
    /// позиции сюда не подмешиваем без конвертации — это была бы неверная цифра, а не «примерная»
    /// (см. брифинг: «если источника нет — не выдумывай»). `nil`, если сравнивать не с чем.
    private var portfolioSharePercent: Decimal? {
        guard account.kind == .marketInvestment else { return nil }
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.kindRaw == "marketInvestment" })
        guard let candidates = try? modelContext.fetch(descriptor) else { return nil }
        let currency = account.currency
        let peers = candidates.filter { $0.currency == currency && $0.archivedAt == nil && $0.deletedAt == nil }
        let total = peers.reduce(Decimal.zero) { sum, acc in
            guard let symbol = acc.marketMeta?.symbol, !symbol.isEmpty,
                  let snapshot = try? StockLotEngine.replay(events: acc.events ?? [], on: Date()) else { return sum }
            return sum + snapshot.quantity * liveOrCachedPrice(symbol: symbol, events: acc.events ?? [])
        }
        guard total > 0 else { return nil }
        return (balanceToday / total) * 100
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsRow: some View {
        if account.kind == .marketInvestment {
            marketActions
        } else {
            genericActions
        }
    }

    /// Круглые действия (вариант A, утверждён): только «Купить» окрашена акцентом — это основной
    /// путь пользователя на этом экране. «Продать»/«Дивиденд»/«Ещё» — одинаковый тёмный нейтральный
    /// круг, чтобы не читаться как три равнозначных предупреждения (был баг: жёлтый/оранжевый).
    private var marketActions: some View {
        HStack(spacing: AppSpacing.m) {
            circularMarketAction(L("accounts_core.detail.market.action.buy"), icon: "plus", prominent: true) {
                sheet = .buy
            }
            circularMarketAction(L("accounts_core.detail.market.action.sell"), icon: "minus") {
                sheet = .sell
            }
            circularMarketAction(L("accounts_core.detail.market.action.dividend"), icon: "banknote") {
                sheet = .dividend
            }
            Menu {
                Button(L("accounts_core.detail.market.action.fee"), systemImage: "minus.circle") { sheet = .fee }
                Button(L("accounts_core.detail.action.edit"), systemImage: "pencil") { sheet = .editDetails }
                Button(archiveActionTitle, systemImage: "archivebox", role: .destructive) { requestArchiveConfirmation() }
            } label: {
                circularActionLabel(icon: "ellipsis", prominent: false, title: L("accounts_core.detail.market.action.more"))
            }
            .accessibilityLabel(L("accounts_core.detail.action.edit"))
            Spacer(minLength: 0)
        }
    }

    private func circularMarketAction(_ title: String, icon: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            circularActionLabel(icon: icon, prominent: prominent, title: title)
        }
        .buttonStyle(.plain)
    }

    /// Круг 46pt + подпись 11,5pt под ним. `#1C1C1E` — тот же ad-hoc hex, что уже использует этот
    /// экран для рыночных акцентов (`Color(hex: "FFD166")` было здесь же) — токена под точный
    /// нейтральный круг из мока в `AppColors` нет.
    private func circularActionLabel(icon: String, prominent: Bool, title: String? = nil) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.millioBodySemibold)
                .foregroundStyle(prominent ? Color.white : AppColors.textPrimary)
                .frame(width: 46, height: 46)
                .background(Circle().fill(prominent ? AppColors.positiveColor : Color(hex: "1C1C1E")))
            if let title {
                Text(title)
                    .font(.millioCaption2Medium)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    private var genericActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.s) {
                switch account.kind {
                case .manualAsset:
                    actionButton(L("accounts_core.detail.manual_asset.action.revalue"), icon: "arrow.triangle.2.circlepath") {
                        sheet = .revalue
                    }
                default:
                    actionButton(incomeActionTitle, icon: "plus.circle.fill") {
                        requestTopUpOrOpenIncomeSheet()
                    }
                    actionButton(expenseActionTitle, icon: "minus.circle.fill") {
                        sheet = .expense
                    }
                    if isDebitProduct {
                        actionButton(L("debit_card.action.fee"), icon: "banknote") {
                            sheet = .fee
                        }
                        actionButton(L("debit_card.action.refund"), icon: "arrow.uturn.backward.circle") {
                            sheet = .refund
                        }
                    }
                    actionButton(account.productType == .creditCard ? "Изменить сумму долга" : L("accounts_core.detail.action.adjust_balance"), icon: "slider.horizontal.3") {
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
                }
                if account.productType != .creditCard {
                    actionButton(L("accounts_core.detail.action.edit"), icon: "pencil") {
                        sheet = .editDetails
                    }
                    actionButton(archiveActionTitle, icon: "archivebox.fill", isDestructive: true) {
                        requestArchiveConfirmation()
                    }
                }
            }
        }
    }

    private var archiveActionTitle: String {
        account.productType == .realEstate
            ? L("real_estate.archive.action")
            : L("accounts_core.detail.action.delete")
    }

    /// Ненулевой баланс (S8): сначала показываем выбор «перевести остаток / закрыть как есть»,
    /// вместо простого confirm — обычный `showArchiveConfirm` остаётся для счетов с нулём.
    private func requestArchiveConfirmation() {
        if AccountArchivePolicy.shouldWarnBeforeArchiving(balance: balanceToday) {
            showNonZeroBalanceArchiveWarning = true
        } else {
            showArchiveConfirm = true
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

    private func actionButton(
        _ title: String,
        icon: String,
        isDestructive: Bool = false,
        tint: Color? = nil,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let foreground = isDestructive ? AppColors.error : (isProminent ? Color.white : (tint ?? AppColors.textPrimary))
        let background = isProminent
            ? (tint ?? AppColors.brandPrimary)
            : (tint ?? Color.white).opacity(tint == nil ? 0.2 : 0.14)
        return Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.millioHeadline)
                Text(title)
                    .font(.millioCaptionRegular)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                    .stroke(isProminent ? Color.white.opacity(0.14) : (tint ?? Color.clear).opacity(0.28), lineWidth: 1)
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
        AccountDetailPlaqueSection(
            title: L("accounts_core.detail.history_title"),
            caption: sortedEvents.isEmpty ? nil : L("cashflow.month_workspace.transaction_count \(sortedEvents.count)")
        ) {
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
            if (event.type == .buy || event.type == .sell || event.type == .adjustment),
               let quantity = event.quantity {
                // buy/sell не имеют `amount` (движок E считает по quantity×price, не по денежной сумме) —
                // показываем количество и цену отдельными строками, а не одной «49 × 769,35».
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text(formattedAmount(quantity))
                        .font(.millioBodySemibold)
                        .foregroundStyle(AppColors.textPrimary)
                    if let unitPrice = event.unitPrice {
                        Text(String(format: L("accounts_core.detail.market.event_price_format"), formattedAmount(unitPrice)))
                            .font(.millioCaptionRegular)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            } else if let amount = event.amount {
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
        case .creditCardPurchase: return L("accounts_core.detail.event.expense")
        case .creditCardRefund, .creditCardRepayment: return L("accounts_core.detail.event.income")
        case .creditCardFee, .creditCardInterest: return L("accounts_core.detail.event.fee")
        case .extraPayment: return L("accounts_core.detail.event.extra_payment")
        case .buy: return L("accounts_core.detail.event.buy")
        case .sell: return L("accounts_core.detail.event.sell")
        case .dividend: return L("accounts_core.detail.event.dividend")
        case .revaluation: return L("accounts_core.detail.event.revaluation")
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
                    perform {
                        if isDebitProduct {
                            _ = try DebitCardOperationCoordinator(modelContext: modelContext).record(
                                account: account,
                                command: .init(operationID: "debit-detail:\(UUID().uuidString)", kind: .income, amount: amount, date: date, note: note)
                            )
                        } else {
                            try service.recordEvent(account: account, type: incomeSheetEventType, amount: amount, date: date, note: note)
                        }
                    }
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
                    perform {
                        if isDebitProduct {
                            _ = try DebitCardOperationCoordinator(modelContext: modelContext).record(
                                account: account,
                                command: .init(operationID: "debit-detail:\(UUID().uuidString)", kind: .expense, amount: amount, date: date, note: note)
                            )
                        } else {
                            try service.recordEvent(account: account, type: expenseSheetEventType, amount: amount, date: date, note: note)
                        }
                    }
                }
            )
        case .adjustBalance:
            let isCreditCard = account.productType == .creditCard
            let creditLimit = account.cardMeta?.creditLimit ?? 0
            let debt = max(0, creditLimit - balanceToday)
            AccountAdjustBalanceSheet(
                currentBalance: isCreditCard ? debt : balanceToday,
                titleOverride: isCreditCard ? "Изменить сумму долга" : nil,
                onSave: { newValue in
                    perform {
                        if isDebitProduct {
                            _ = try DebitCardOperationCoordinator(modelContext: modelContext).adjust(
                                account: account, to: newValue,
                                operationID: "debit-detail:\(UUID().uuidString)",
                                reason: "manual_balance_correction"
                            )
                        } else {
                            try service.adjustBalance(
                                account: account,
                                to: isCreditCard
                                    ? CreditCardFinancialContract.rawAvailableBalance(debt: newValue, creditLimit: creditLimit)
                                    : newValue
                            )
                        }
                    }
                }
            )
        case .editDetails:
            if account.kind == .deposit, let meta = account.depositMeta, let presentation = depositPresentation {
                // Коммит 2: «Реквизиты счёта» вклада — слияние генерик-формы и правки условий в
                // один экран тёмного языка приложения. Другие типы продолжают открывать прежние
                // экраны ниже — их поведение этой веткой не затронуто.
                DepositAccountDetailsSheet(
                    account: account,
                    modelContext: modelContext,
                    meta: meta,
                    canEarlyClose: presentation.actions.contains(.earlyClose),
                    onSave: { edit in
                        performDeposit {
                            try service.updateAccount(
                                account,
                                name: edit.name,
                                group: edit.group,
                                note: edit.note,
                                includeInTotal: edit.includeInTotal
                            )
                            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
                            let coordinator = DepositOperationCoordinator(modelContext: modelContext)
                            let result = try coordinator.editTerms(
                                depositID: account.id,
                                command: DepositTermsEditCommand(meta: edit.meta)
                            )
                            synchronizeDepositReminder(meta: edit.meta)
                            return result
                        }
                    },
                    onProductTransitionCommitted: productTransitionCommitted,
                    onRequestEarlyClose: { showEarlyCloseConfirm = true },
                    onRequestDelete: { requestArchiveConfirmation() }
                )
            } else if account.productType == .creditCard {
                CreditCardEditSheet(account: account, modelContext: modelContext, onSave: { command, settings in
                    performEdit {
                        try CreditCardEditorService(modelContext: modelContext).update(account: account, command: command)
                        CreditCardPaymentSettingsStore().save(settings, accountID: account.id)
                        Task { await NotificationManager.shared.scheduleCreditCardPaymentReminder(
                            accountID: account.id, cardName: account.name,
                            settings: settings, graceDays: account.cardMeta?.graceDays
                        ) }
                    }
                })
            } else if account.productType == .realEstate {
                RealEstateEditSheet(
                    account: account,
                    modelContext: modelContext,
                    onSave: { name, group, note, includeInTotal, propertyType, reminderMonths, linkedLoanID, photos in
                        performEdit {
                            try RealEstateEditorService(modelContext: modelContext).update(
                                account: account,
                                name: name,
                                group: group,
                                note: note,
                                includeInTotal: includeInTotal,
                                propertyType: propertyType,
                                reminderMonths: reminderMonths,
                                linkedLoanID: linkedLoanID,
                                photos: photos
                            )
                        }
                    }
                )
            } else if account.productType == .marketStock, let stockSnapshot {
                StockPositionEditSheet(
                    account: account,
                    modelContext: modelContext,
                    snapshot: stockSnapshot,
                    onSave: { name, group, note, includeInTotal, quantity, averageCost in
                        performEdit {
                            try service.correctStockPosition(
                                account: account,
                                name: name,
                                group: group,
                                note: note,
                                includeInTotal: includeInTotal,
                                targetQuantity: quantity,
                                targetAverageCost: averageCost
                            )
                        }
                    }
                )
            } else {
                AccountEditDetailsSheet(
                    account: account,
                    modelContext: modelContext,
                    onSave: { name, group, note, includeInTotal, _, _, _ in
                        performEdit {
                            try service.updateAccount(
                                account,
                                name: name,
                                group: group,
                                note: note,
                                includeInTotal: includeInTotal
                            )
                        }
                    },
                    onProductTransitionCommitted: productTransitionCommitted
                )
            }
        case .transfer:
            AccountTransferSheet(
                source: account,
                modelContext: modelContext,
                onSave: { destination, amount in
                    perform {
                        if isDebitProduct {
                            _ = try DebitCardOperationCoordinator(modelContext: modelContext).transfer(
                                from: account, to: destination,
                                operationID: "debit-detail:\(UUID().uuidString)", amount: amount
                            )
                        } else {
                            try service.transfer(from: account, to: destination, amountInSourceCurrency: amount)
                        }
                    }
                }
            )
        case .earlyClose:
            if let snapshot = depositPresentation?.snapshot {
                DepositCloseSheet(
                    source: account,
                    modelContext: modelContext,
                    preview: DepositDetailPresentation.earlyClosePreview(
                        snapshot: snapshot,
                        penaltyShare: account.depositMeta?.earlyClosePenalty
                    ),
                    isMaturity: false,
                    onSave: { destination in
                        performDepositAndDismiss {
                            let result = try DepositOperationCoordinator(modelContext: modelContext).earlyClose(
                                depositID: account.id,
                                command: DepositTransferCommand(
                                    operationID: "deposit-early-close:\(UUID().uuidString)",
                                    destinationAccountID: destination.id
                                )
                            )
                            NotificationManager.shared.cancelAccountDepositMaturityReminder(accountID: account.id)
                            return result
                        }
                    }
                )
            }
        case .depositTopUp:
            DepositTopUpSheet(deposit: account, modelContext: modelContext) { source, amount in
                performDeposit {
                    try DepositOperationCoordinator(modelContext: modelContext).topUp(
                        depositID: account.id,
                        command: DepositTopUpCommand(
                            operationID: "deposit-top-up:\(UUID().uuidString)",
                            sourceAccountID: source.id,
                            amount: amount
                        )
                    )
                }
            }
        case .depositAdjustBalance:
            if let currentBalance = depositPresentation?.snapshot.currentBalance.value {
                DepositBalanceAdjustmentSheet(currentBalance: currentBalance, currency: account.currency) { amount, date, note in
                    performDeposit {
                        try DepositOperationCoordinator(modelContext: modelContext).adjustBalance(
                            depositID: account.id,
                            command: DepositBalanceAdjustmentCommand(
                                operationID: "deposit-balance-adjustment:\(UUID().uuidString)",
                                newBalance: amount,
                                date: date,
                                note: note
                            )
                        )
                    }
                }
            }
        case .depositTerms:
            if let meta = account.depositMeta, let snapshot = depositPresentation?.snapshot {
                DepositTermsEditSheet(
                    meta: meta,
                    snapshot: snapshot,
                    openingDate: account.createdAt,
                    currentNote: account.note
                ) { edit in
                    performDeposit {
                        // Заметка пишется ПЕРВОЙ и именно `updateAccount`: она живёт в контексте
                        // экрана, а координатор работает в своём. Если писать её после операций
                        // координатора, экранный `account` будет уже устаревшим снимком строки и
                        // сохранение заметки могло бы затереть только что записанную мету.
                        if edit.note != account.note {
                            try service.updateAccount(
                                account,
                                name: account.name,
                                group: account.group,
                                note: edit.note,
                                includeInTotal: account.includeInTotal
                            )
                            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
                        }
                        let coordinator = DepositOperationCoordinator(modelContext: modelContext)
                        // Порядок важен: сначала новые условия, потом коррекция суммы. Обе операции
                        // перестраивают будущий график, и вторая должна считать его уже по новой мете.
                        let result = try coordinator.editTerms(
                            depositID: account.id,
                            command: DepositTermsEditCommand(meta: edit.meta)
                        )
                        if let newBalance = edit.newBalance {
                            _ = try coordinator.adjustBalance(
                                depositID: account.id,
                                command: DepositBalanceAdjustmentCommand(
                                    operationID: "deposit-balance-adjustment:\(UUID().uuidString)",
                                    newBalance: newBalance,
                                    date: Date()
                                )
                            )
                        }
                        synchronizeDepositReminder(meta: edit.meta)
                        return result
                    }
                }
            }
        case .depositMaturity:
            if depositPresentation?.snapshot != nil {
                DepositCloseSheet(source: account, modelContext: modelContext, preview: nil, isMaturity: true) { destination in
                    performDepositAndDismiss {
                        let result = try DepositOperationCoordinator(modelContext: modelContext).mature(
                            depositID: account.id,
                            command: DepositTransferCommand(
                                operationID: "deposit-maturity:\(UUID().uuidString)",
                                destinationAccountID: destination.id
                            )
                        )
                        NotificationManager.shared.cancelAccountDepositMaturityReminder(accountID: account.id)
                        return result
                    }
                }
            }
        case .buy:
            AccountBuySellSheet(
                title: L("accounts_core.detail.market.action.buy"),
                currentQuantity: currentQuantity,
                initialUnitPrice: currentUnitPrice > 0 ? currentUnitPrice : nil,
                currency: account.currency,
                showsSellWarning: false,
                onSave: { quantity, unitPrice, fee, date, note in
                    perform { try service.buy(account: account, quantity: quantity, unitPrice: unitPrice, fee: fee, date: date, note: note) }
                }
            )
        case .sell:
            AccountBuySellSheet(
                title: L("accounts_core.detail.market.action.sell"),
                currentQuantity: currentQuantity,
                initialUnitPrice: currentUnitPrice > 0 ? currentUnitPrice : nil,
                currency: account.currency,
                showsSellWarning: true,
                onSave: { quantity, unitPrice, fee, date, note in
                    perform { try service.sell(account: account, quantity: quantity, unitPrice: unitPrice, fee: fee, date: date, note: note) }
                }
            )
        case .dividend:
            AccountEventEntrySheet(
                title: L("accounts_core.detail.market.action.dividend"),
                onSave: { amount, date, note in
                    perform { try service.recordMarketCashEvent(account: account, type: .dividend, amount: amount, date: date, note: note) }
                }
            )
        case .fee:
            AccountEventEntrySheet(
                title: isDebitProduct ? L("debit_card.action.fee") : L("accounts_core.detail.market.action.fee"),
                onSave: { amount, date, note in
                    perform {
                        if isDebitProduct {
                            _ = try DebitCardOperationCoordinator(modelContext: modelContext).record(
                                account: account,
                                command: .init(operationID: "debit-detail:\(UUID().uuidString)", kind: .fee, amount: amount, date: date, note: note)
                            )
                        } else {
                            try service.recordMarketCashEvent(account: account, type: .fee, amount: amount, date: date, note: note)
                        }
                    }
                }
            )
        case .refund:
            DebitCardRefundSheet(
                expenses: sortedEvents.filter { $0.type == .expense && $0.sourceTransactionID != nil },
                currency: account.currency
            ) { originalOperationID, amount, date, note in
                perform {
                    _ = try DebitCardOperationCoordinator(modelContext: modelContext).record(
                        account: account,
                        command: .init(
                            operationID: "debit-detail:\(UUID().uuidString)",
                            kind: .refund(originalOperationID: originalOperationID),
                            amount: amount, date: date, note: note
                        )
                    )
                }
            }
        case .revalue:
            AccountAdjustBalanceSheet(
                currentBalance: balanceToday,
                titleOverride: L("accounts_core.detail.manual_asset.action.revalue"),
                onSave: { newValue in
                    perform { try service.revalue(account: account, newValue: newValue) }
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

    private func handleDepositAction(_ action: DepositDetailAction) {
        switch action {
        case .topUp: sheet = .depositTopUp
        case .adjustBalance: sheet = .depositAdjustBalance
        case .editTerms: sheet = .depositTerms
        case .earlyClose: showEarlyCloseConfirm = true
        case .withdrawAtMaturity: sheet = .depositMaturity
        case .archive: requestArchiveConfirmation()
        }
    }

    /// Правка реквизитов вклада (имя, группа, учёт в тотале) — те же условия, что и у actionsRow
    /// остальных типов счетов: архивный/удалённый счёт не редактируется.
    private var canEditDepositDetails: Bool {
        account.archivedAt == nil && account.deletedAt == nil
    }

    private func depositOverflowActions(_ presentation: DepositDetailPresentation) -> [DepositDetailAction] {
        presentation.actions.filter { $0 != .topUp && $0 != .adjustBalance }
    }

    /// Пункты bottom-sheet меню вклада (Коммит 1, `AccountActionsSheet`). «Реквизиты счёта» и
    /// «Изменить условия» слиты в один пункт — экран `.editDetails` для вклада сам показывает
    /// условия (Коммит 2). «Пополнить» сюда не добавляем — кнопка уже есть на экране
    /// (`DepositDetailSection.actions`).
    private func depositActionSheetItems(_ presentation: DepositDetailPresentation) -> [AccountActionSheetItem] {
        var items: [AccountActionSheetItem] = []
        if canEditDepositDetails {
            items.append(.init(
                title: L("accounts_core.detail.action.edit_details"),
                icon: "square.and.pencil",
                action: { sheet = .editDetails }
            ))
        }
        if presentation.actions.contains(.earlyClose) {
            items.append(.init(
                title: L("accounts_core.detail.deposit.action.early_close"),
                // Реальное последствие из кода (`earlyClosePreview`), не выдуманная формулировка:
                // штраф — доля от УЖЕ начисленных процентов, будущие начисления просто теряются.
                subtitle: L("accounts_core.detail.deposit.early_close_confirm.message"),
                icon: "xmark.circle",
                action: { showEarlyCloseConfirm = true }
            ))
        }
        if presentation.actions.contains(.archive) {
            items.append(.init(
                title: L("accounts_core.detail.action.delete_account"),
                icon: "trash",
                isDestructive: true,
                action: { requestArchiveConfirmation() }
            ))
        }
        return items
    }

    private func performDeposit(_ operation: () throws -> DepositOperationResult) {
        do {
            _ = try operation()
            refreshToken = UUID()
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performDepositAndDismiss(_ operation: () throws -> DepositOperationResult) {
        do {
            _ = try operation()
            sheet = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do {
            try operation()
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            refreshToken = UUID()
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Правка «карточки» счёта (имя/группа/заметка) — как `perform`, но при успехе публикует
    /// `investmentsUpdated`: смена имени/группы должна обновить список и группировку на экране «Счета»
    /// (этот экран не держит ссылку на `FinanceViewModel` — тот же канал, что использует `archiveAccount`).
    private func performEdit(_ operation: () throws -> Void) {
        do {
            try operation()
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            refreshToken = UUID()
            sheet = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Product transitions commit in an isolated context. Closing this stale detail instance makes
    /// the accounts list refetch the committed product (and is also required for replacement flows).
    private func productTransitionCommitted() {
        EventBus.shared.publish(FinanceEvent.investmentsUpdated)
        sheet = nil
        dismiss()
    }

    private func archiveAccount() {
        do {
            if isDebitProduct {
                try DebitCardOperationCoordinator(modelContext: modelContext).archive(account)
            } else {
                try service.archiveAccount(account)
            }
            if account.kind == .deposit {
                NotificationManager.shared.cancelAccountDepositMaturityReminder(accountID: account.id)
            }
            // Track D1: этот экран не хранит ссылку на FinanceViewModel — без события список
            // счетов и «Общий баланс» на экране Счетов не пересчитываются до перезапуска приложения
            // (FinanceViewModel.state.totalAmount обновляется только явным calculateTotalAmount(),
            // а сюда его никто не позвал бы). investmentsUpdated — уже существующий канал,
            // подписка есть в FinanceViewModel.subscribeToFinanceEvents().
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func synchronizeDepositReminder(meta: DepositMeta) {
        guard meta.remindEnd, let maturity = meta.termEnd else {
            NotificationManager.shared.cancelAccountDepositMaturityReminder(accountID: account.id)
            return
        }
        Task { @MainActor in
            _ = await NotificationManager.shared.scheduleAccountDepositMaturityReminder(
                accountID: account.id, accountName: account.name, maturityDate: maturity
            )
        }
    }
}
