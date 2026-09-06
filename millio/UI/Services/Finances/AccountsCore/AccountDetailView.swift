import SwiftUI
import SwiftData

/// Карточка счёта нового ядра event-sourcing (Фаза 1a-ui) — минимальный, но рабочий экран:
/// баланс, история событий, доход/расход/корректировка/перевод/архивация. Единственная точка
/// записи — `AccountsCoreService` (AC1/AC7/AC9/AC12), сама view никогда не мутирует баланс напрямую.
struct AccountDetailView: View {
    let account: Account
    let modelContext: ModelContext

    @Environment(\.dismiss) var dismiss

    @State var refreshToken = UUID()
    @State var sheet: ActiveSheet?
    @State var errorMessage: String?
    /// Одно состояние на все подтверждения экрана — раньше это были четыре отдельных `.alert`.
    @State var confirmation: Confirmation?
    /// Один bottom sheet «···» на все типы счетов — заменил системные `Menu` у верхнего края
    /// и три отдельных состояния (вклад / кредит / кредитка).
    @State var showActionsSheet = false
    /// График платежей кредита — отдельный экран пушем (Ф5), как «Тип продукта» у вклада.
    @State var showLoanSchedule = false
    /// Оформление счёта грузится ОДИН раз на открытие экрана, а не из тела `body`: `body`
    /// пересчитывается на каждую мутацию, а редактора оформления на этом экране нет.
    @State var appearance: AccountAppearanceSnapshot?
    /// Договор кредита (V12) — грузится тем же одним заходом, что и оформление. Через него
    /// `LoanTermsResolver` отдаёт условия; напрямую `account.loanMeta` экран больше не читает.
    @State var loanContract: LoanContract?

    enum ActiveSheet: Identifiable {
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
        case loanTerms
        case loanPayment
        case loanPrepayment
        case buy
        case sell
        case dividend
        case fee
        case refund
        case revalue

        var id: Int { hashValue }
    }

    /// Что именно подтверждает пользователь. `archiveNonZeroBalance` — отдельный случай:
    /// архивация счёта с остатком «прячет деньги» на графике, поэтому предлагаем сначала
    /// перевести остаток (S8 плана ядра счетов).
    enum Confirmation: Identifiable {
        case archive
        case archiveNonZeroBalance
        case depositTopUp
        case depositEarlyClose

        var id: Int { hashValue }
    }

    var service: AccountsCoreService {
        AccountsCoreService(modelContext: modelContext)
    }

    var isDebitProduct: Bool {
        DebitCardContract.products.contains(account.productType ?? .unknownLegacy)
    }

    /// Провайдер живых цен нового ядра (Фаза 4) — синхронный снэпшот append-only кэша
    /// `HistoricalAssetPrice`, читается один раз на пересчёт body. `nil` для не-рыночных счетов.
    var priceProviderForThisAccount: MarketPriceProviding? {
        guard account.kind == .marketInvestment, let meta = account.marketMeta else { return nil }
        return AccountMarketPriceService(modelContext: modelContext).makeSnapshotProvider(symbols: [meta.symbol])
    }

    var balanceToday: Decimal {
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

    var sortedEvents: [AccountEvent] {
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

    var depositPresentation: DepositDetailPresentation? {
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

    /// Детальный режим кредита (Ф4). Признак режима — наличие условий, а не `kind`: счёт `.loan`
    /// без `LoanMeta` и без договора остаётся на старом генерик-экране, ничего не теряя.
    ///
    /// Остаток берётся из ленты событий (спека Р6) и разворачивается в положительную величину:
    /// в ядре долг хранится отрицательным балансом, а человеку показываем «сколько осталось».
    var loanOutstandingPrincipal: Decimal {
        LoanOutstanding.fromLedger(balance: balanceToday)
    }

    var loanPresentation: LoanDetailPresentation? {
        guard account.kind == .loan else { return nil }
        _ = refreshToken
        guard let terms = LoanTermsResolver.terms(for: account, contract: loanContract) else { return nil }
        return LoanDetailPresentation.make(
            terms: terms,
            outstandingPrincipal: loanOutstandingPrincipal,
            paymentsMade: loanContract?.paymentsMade ?? 0,
            paidInterestTotal: loanContract?.paidInterestTotal ?? 0,
            currency: account.currency
        )
    }

    var debitSnapshot: DebitCardSnapshot? {
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
                        } else if let loanPresentation {
                            // Кредит — та же подмена начинки, что у вклада: hero несёт остаток
                            // долга, прогресс погашенного тела и ближайший платёж.
                            AccountHeroCardView(presentation: heroPresentation) {
                                LoanHeroContent(presentation: loanPresentation)
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
                            taxPresentation: depositTaxPresentation
                        )
                    } else if let loanPresentation {
                        LoanDetailSection(presentation: loanPresentation, onAction: handleLoanAction)
                    } else if account.productType == .creditCard {
                        CreditCardDetailSection(account: account, rawBalance: balanceToday)
                    } else if let snapshot = debitSnapshot {
                        DebitCardDetailSection(account: account, snapshot: snapshot)
                    }
                    if isActionsRowVisible {
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
            // «···» в toolbar остаётся только как запасной вход: пока панель действий на экране,
            // её кнопка «Ещё» открывает тот же лист, и вторая точка входа была бы дубликатом.
            if !isActionsRowVisible && !overflowItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showActionsSheet = true
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel(L("accounts_core.detail.market.action.more"))
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(for: sheet)
        }
        // Витрина графика строится ЗДЕСЬ, а не в свойстве экрана: 60 строк не нужны на каждый
        // пересчёт `body`, а замыкание назначения выполняется только в момент перехода.
        .navigationDestination(isPresented: $showLoanSchedule) {
            if let terms = LoanTermsResolver.terms(for: account, contract: loanContract) {
                LoanScheduleView(presentation: LoanSchedulePresentation.make(
                    terms: terms,
                    outstandingPrincipal: loanOutstandingPrincipal,
                    paymentsMade: loanContract?.paymentsMade ?? 0,
                    currency: account.currency
                ))
            }
        }
        .sheet(isPresented: $showActionsSheet) {
            AccountActionsSheet(
                accountName: account.name,
                accountTypeTitle: account.kind.localizedTitle,
                items: overflowItems,
                onDismiss: { showActionsSheet = false }
            )
        }
        // Подтверждения — тем же листом снизу, что и «···»: последствие действия читается
        // второй строкой пункта, а не в системном алерте посреди экрана.
        .sheet(item: $confirmation) { request in
            AccountActionsSheet(
                accountName: account.name,
                accountTypeTitle: confirmationTitle(request),
                items: confirmationItems(request),
                onDismiss: { confirmation = nil }
            )
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
            // Ленивый перевод в детальный режим (спека Р5): счёт `.loan`, заведённый старой формой,
            // получает договор из легаси-меты ровно здесь — при первом открытии деталки.
            loanContract = account.kind == .loan
                ? try? LoanContractBackfill.ensureContract(for: account, context: modelContext)
                : nil
            guard account.kind == .marketInvestment else { return }
            await AccountMarketPriceService(modelContext: modelContext).refreshTodayPrices()
            refreshToken = UUID()
        }
    }

}
