import SwiftUI
import SwiftData

/// Панель действий счёта, пункты «···» и подтверждения экрана.
extension AccountDetailView {
    // MARK: - Actions

    /// Архивный, удалённый и read-only счёт панель действий не показывает — раньше это же
    /// условие стояло прямо в `body`.
    var isActionsRowVisible: Bool {
        account.archivedAt == nil && account.deletedAt == nil
            && (debitSnapshot?.canWrite ?? true)
            && !actionItems.isEmpty
    }

    /// Панель действий — одна на все типы счетов (`AccountActionsRow`, круглые 46pt).
    /// Главные операции стоят в ряд, остальное уходит в «···» → `AccountActionsSheet`:
    /// у вклада и кредита раньше до любого действия было три тапа.
    var actionsRow: some View {
        AccountActionsRow(items: actionItems)
    }

    var actionItems: [AccountActionItem] {
        switch account.kind {
        case .marketInvestment: marketActionItems
        case .deposit: depositActionItems
        case .loan: loanActionItems
        default: genericActionItems
        }
    }

    /// Акцентом окрашена только «Купить» — это основной путь пользователя на этом экране.
    /// Остальные круги нейтральные, чтобы не читаться как равнозначные предупреждения.
    var marketActionItems: [AccountActionItem] {
        [
            .init(title: L("accounts_core.detail.market.action.buy"), icon: "plus", isProminent: true) { sheet = .buy },
            .init(title: L("accounts_core.detail.market.action.sell"), icon: "minus") { sheet = .sell },
            .init(title: L("accounts_core.detail.market.action.dividend"), icon: "banknote") { sheet = .dividend },
            moreActionItem
        ]
    }

    var depositActionItems: [AccountActionItem] {
        guard let presentation = depositPresentation else { return [] }
        var items: [AccountActionItem] = []
        if presentation.actions.contains(.topUp) {
            items.append(.init(title: DepositDetailAction.topUp.title, icon: DepositDetailAction.topUp.icon, isProminent: true) {
                sheet = .depositTopUp
            })
        }
        if presentation.actions.contains(.adjustBalance) {
            items.append(.init(title: DepositDetailAction.adjustBalance.title, icon: DepositDetailAction.adjustBalance.icon) {
                sheet = .depositAdjustBalance
            })
        }
        if presentation.actions.contains(.withdrawAtMaturity) {
            items.append(.init(title: DepositDetailAction.withdrawAtMaturity.title, icon: DepositDetailAction.withdrawAtMaturity.icon) {
                sheet = .depositMaturity
            })
        }
        if !overflowItems.isEmpty { items.append(moreActionItem) }
        return items
    }

    /// «Внести платёж» = применить плановую операцию Cashflow, поэтому без живого плана (нет
    /// договора, кредит закрыт) кнопки нет вовсе: гасить её нечем — применять нечего.
    /// Досрочка гаснет при нулевом остатке.
    var loanActionItems: [AccountActionItem] {
        guard let presentation = loanPresentation else { return [] }
        var items: [AccountActionItem] = []
        if presentation.plannedPaymentDate != nil {
            items.append(.init(
                title: L("accounts_core.loan.detail.action.payment"),
                icon: "creditcard",
                isProminent: true
            ) { sheet = .loanPayment })
        }
        items.append(contentsOf: [
            .init(
                title: L("accounts_core.loan.detail.action.prepayment"),
                icon: "bolt.fill",
                isEnabled: presentation.outstandingPrincipal > 0
            ) { sheet = .loanPrepayment },
            .init(title: L("accounts_core.loan.detail.schedule"), icon: "list.bullet.rectangle") { showLoanSchedule = true },
            moreActionItem
        ])
        return items
    }

    var genericActionItems: [AccountActionItem] {
        if account.kind == .manualAsset {
            return [
                .init(title: L("accounts_core.detail.manual_asset.action.revalue"), icon: "arrow.triangle.2.circlepath", isProminent: true) {
                    sheet = .revalue
                },
                moreActionItem
            ]
        }
        return [
            .init(title: incomeActionTitle, icon: "plus", isProminent: true) { requestTopUpOrOpenIncomeSheet() },
            .init(title: expenseActionTitle, icon: "minus") { sheet = .expense },
            .init(title: L("accounts_core.detail.action.transfer"), icon: "arrow.left.arrow.right") { sheet = .transfer },
            moreActionItem
        ]
    }

    var moreActionItem: AccountActionItem {
        .init(title: L("accounts_core.detail.market.action.more"), icon: "ellipsis") { showActionsSheet = true }
    }

    /// Хвост действий, не поместившийся в ряд, — один bottom sheet на все типы счетов.
    /// Единственная точка «···»: пока ряд на экране, дублирующей кнопки в toolbar нет.
    var overflowItems: [AccountActionItem] {
        switch account.kind {
        case .marketInvestment:
            // Архивный/удалённый инвест-счёт read-only: без этого guard'а «Комиссия»/«Редактировать»
            // открывались бы на закрытом счёте (БАГ 6, тот же дефект что у generic-счетов ниже).
            guard account.archivedAt == nil, account.deletedAt == nil else { return [] }
            return [
                .init(title: L("accounts_core.detail.market.action.fee"), icon: "minus.circle") { sheet = .fee },
                .init(title: L("accounts_core.detail.action.edit"), icon: "pencil") { sheet = .editDetails },
                .init(title: archiveActionTitle, icon: "archivebox", isDestructive: true) { requestArchiveConfirmation() }
            ]
        case .deposit:
            return depositPresentation.map(depositActionSheetItems) ?? []
        case .loan:
            return loanActionSheetItems
        default:
            return genericOverflowItems
        }
    }

    var genericOverflowItems: [AccountActionItem] {
        // БАГ 6: архивный/удалённый счёт открывался этим же листом («Редактировать»/«Изменить
        // баланс»/«Удалить») через toolbar-фолбэк AccountDetailView — правки проходили на
        // закрытом счёте, потому что здесь не было проверки archivedAt/deletedAt (образец
        // такой проверки уже есть у вклада и кредита в этом же файле).
        guard account.archivedAt == nil, account.deletedAt == nil else { return [] }
        var items: [AccountActionItem] = []
        if isDebitProduct {
            items.append(.init(title: L("debit_card.action.fee"), icon: "banknote") { sheet = .fee })
            items.append(.init(title: L("debit_card.action.refund"), icon: "arrow.uturn.backward.circle") { sheet = .refund })
        }
        // У наличных этот же вход уже стоит на экране кнопкой «Сверка» (`CashDetailSection`) —
        // второй пункт в «···» был бы дубликатом того же листа.
        if account.kind != .manualAsset, account.kind != .cash {
            items.append(.init(title: adjustBalanceActionTitle, icon: "slider.horizontal.3") { sheet = .adjustBalance })
        }
        items.append(.init(title: L("accounts_core.detail.action.edit"), icon: "pencil") { sheet = .editDetails })
        items.append(.init(title: archiveActionTitle, icon: "archivebox.fill", isDestructive: true) { requestArchiveConfirmation() })
        return items
    }

    /// У кредитки «изменить баланс» = поправить сумму долга: слово «баланс» на экране
    /// обязательства читается как остаток денег, а не как задолженность.
    var adjustBalanceActionTitle: String {
        account.productType == .creditCard
            ? L("accounts_core.detail.action.adjust_debt")
            : L("accounts_core.detail.action.adjust_balance")
    }

    var archiveActionTitle: String {
        account.productType == .realEstate
            ? L("real_estate.archive.action")
            : L("accounts_core.detail.action.delete")
    }

    /// Ненулевой баланс (S8): сначала показываем выбор «перевести остаток / закрыть как есть»,
    /// вместо простого confirm — обычное подтверждение остаётся для счетов с нулём.
    func requestArchiveConfirmation() {
        confirmation = AccountArchivePolicy.shouldWarnBeforeArchiving(balance: balanceToday)
            ? .archiveNonZeroBalance
            : .archive
    }

    /// Непополняемый вклад (Фаза 3, брифинг п.3): попытка пополнения — предупреждение с
    /// подтверждением, НЕ жёсткий запрет («да, всё равно» открывает обычную форму дохода).
    func requestTopUpOrOpenIncomeSheet() {
        if account.kind == .deposit, account.depositMeta?.allowsTopUp == false {
            confirmation = .depositTopUp
        } else {
            sheet = .income
        }
    }

    // MARK: - Подтверждения

    func confirmationTitle(_ request: Confirmation) -> String {
        switch request {
        case .archive: L("accounts_core.detail.delete_confirm.title")
        case .archiveNonZeroBalance: L("accounts_core.detail.delete_nonzero_confirm.title")
        case .depositTopUp: L("accounts_core.detail.deposit.top_up_warning.title")
        case .depositEarlyClose: L("accounts_core.detail.deposit.early_close_confirm.title")
        }
    }

    func confirmationItems(_ request: Confirmation) -> [AccountActionItem] {
        switch request {
        case .archive:
            return [.init(
                title: archiveActionTitle,
                subtitle: L("accounts_core.detail.delete_confirm.message"),
                icon: "archivebox",
                isDestructive: true
            ) { archiveAccount() }]
        case .archiveNonZeroBalance:
            return [
                .init(
                    title: L("accounts_core.detail.delete_nonzero_confirm.transfer_first"),
                    subtitle: L("accounts_core.detail.delete_nonzero_confirm.message"),
                    icon: "arrow.left.arrow.right"
                ) { sheet = .transfer },
                .init(
                    title: L("accounts_core.detail.delete_nonzero_confirm.close_anyway"),
                    icon: "archivebox",
                    isDestructive: true
                ) { archiveAccount() }
            ]
        case .depositTopUp:
            return [.init(
                title: L("accounts_core.detail.deposit.top_up_warning.confirm"),
                subtitle: L("accounts_core.detail.deposit.top_up_warning.message"),
                icon: "plus"
            ) { sheet = .income }]
        case .depositEarlyClose:
            return [.init(
                title: L("accounts_core.detail.deposit.action.early_close"),
                subtitle: L("accounts_core.detail.deposit.early_close_confirm.message"),
                icon: "xmark.circle",
                isDestructive: true
            ) { sheet = .earlyClose }]
        }
    }
}
