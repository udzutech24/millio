import Foundation

/// Витрина листа досрочного погашения (макет, ЭКРАН 4): все цифры и все тексты считает ядро
/// (`LoanPrepaymentPlanner`), вью только раскладывает готовое по строкам.
///
/// Инвариант таблицы «Что изменится»: «стало» = «было» − экономия (или + рост). Обе величины
/// меряются от ОДНОГО момента — до ближайшего планового платежа, поэтому у недоплаты в «процентах
/// впереди» учтены и проценты, которые она закрывает прямо сейчас. Иначе карточка итога и таблица
/// над ней говорили бы разное: недоплата уменьшает проценты «впереди» просто потому, что часть их
/// уже уплачена.
struct LoanPrepaymentPresentation: Equatable {

    /// Во что превратилась введённая сумма.
    enum Mode: Equatable {
        /// Сумма не введена — на экране только поле и подсказка.
        case idle
        /// Сверх графика: выбор «срок / платёж».
        case prepayment
        /// Меньше планового платежа: выбора нет, вместо экономии — рост.
        case underpayment
        /// Хватает, чтобы закрыть кредит целиком.
        case payoff
    }

    /// Роль значения в цвете: улучшение — зелёным, ухудшение — красным (`AppColors`).
    enum ValueStyle: Equatable {
        case neutral
        case positive
        case negative
    }

    /// Радио-строка выбора сценария.
    struct Option: Equatable, Identifiable {
        let strategy: LoanPrepaymentStrategy
        let title: String
        let note: String
        /// «экономия 226 771 ₽» — абсолютная выгода САМОГО сценария, а не его перевес над соседним:
        /// пока ничего не выбрано, сравнивать не с чем, и человек должен видеть цену каждого выбора.
        let tag: String?

        var id: String { strategy.rawValue }
    }

    /// Строка таблицы «Что изменится». `after == nil` — «без изменений».
    struct DiffRow: Equatable, Identifiable {
        let id: String
        let title: String
        let before: String
        let after: String?
        let afterStyle: ValueStyle
    }

    /// Карточка итога: экономия при досрочке, рост при недоплате.
    struct Outcome: Equatable {
        let title: String
        let value: String
        /// Вторая строка — «Срок вырастет на N платежей».
        let detail: String?
        let style: ValueStyle
    }

    let mode: Mode
    let currency: String
    let hint: String
    let options: [Option]
    /// Сценарий, который реально применится. `nil` — выбор ещё не сделан: предвыбора нет, и до
    /// касания радио-строки подтверждать нечего. Единственный доступный сценарий выбирается сам
    /// (дифференцированный график), при полном погашении и недоплате выбора нет вовсе.
    let selectedStrategy: LoanPrepaymentStrategy?
    let diff: [DiffRow]
    let outcome: Outcome?
    let confirmTitle: String
    /// Что записать при подтверждении. `nil` — подтверждать нечего, кнопка неактивна.
    let entry: LoanExtraPaymentEntry?

    var canConfirm: Bool { entry != nil }

    static func make(
        terms: LoanTerms,
        outstandingPrincipal: Decimal,
        paymentsMade: Int,
        amount: Decimal,
        strategy: LoanPrepaymentStrategy?,
        currency: String,
        calendar: Calendar = Calendar(identifier: .gregorian),
        locale: Locale = AppLocalization.currentAppLocale
    ) -> LoanPrepaymentPresentation {
        let scheduled = LoanPrepaymentPlanner.scheduledPayment(
            terms: terms, outstandingPrincipal: outstandingPrincipal,
            paymentsMade: paymentsMade, calendar: calendar
        )
        let idleHint = scheduled.map {
            String(
                format: L("accounts_core.loan.prepayment.hint_format"),
                dayMonth($0.date, locale: locale)
            )
        } ?? ""

        guard let evaluation = LoanPrepaymentPlanner.evaluate(
            terms: terms, outstandingPrincipal: outstandingPrincipal,
            paymentsMade: paymentsMade, amount: amount, calendar: calendar
        ) else {
            return LoanPrepaymentPresentation(
                mode: .idle, currency: currency, hint: idleHint, options: [],
                selectedStrategy: nil, diff: [], outcome: nil,
                confirmTitle: L("accounts_core.loan.prepayment.confirm"), entry: nil
            )
        }

        switch evaluation {
        case .prepayment(let plan):
            return make(
                plan: plan, strategy: strategy, frequency: terms.frequency,
                currency: currency, locale: locale
            )
        case .underpayment(let plan):
            return make(underpayment: plan, currency: currency, locale: locale)
        }
    }

    // MARK: - Досрочное погашение

    private static func make(
        plan: LoanPrepaymentPlan,
        strategy: LoanPrepaymentStrategy?,
        frequency: LoanPaymentFrequency,
        currency: String,
        locale: Locale
    ) -> LoanPrepaymentPresentation {
        // Предвыбора нет (решение владельца): выбор «срок / платёж» человек делает сам. Сам собой
        // сценарий определяется только там, где альтернативы нет: у дифференцированного графика
        // «платёж» не существует, при полном погашении платить дальше нечего.
        let effective: LoanPrepaymentStrategy?
        if plan.closesLoan {
            effective = nil
        } else if plan.payment == nil {
            effective = .term
        } else {
            effective = strategy.flatMap { plan.preview(for: $0) != nil ? $0 : nil }
        }
        // `term` есть всегда — им и закрывается полное погашение, где выбора нет. Пока сценарий не
        // выбран, показывать «стало» не от чего: таблица и карточка итога скрыты.
        let preview: LoanPrepaymentPreview? = plan.closesLoan
            ? plan.term
            : effective.flatMap { plan.preview(for: $0) }
        let money = { (value: Decimal) in LoanMoneyFormat.money(value, currency: currency) }

        let hint = plan.closesLoan
            ? String(format: L("accounts_core.loan.prepayment.hint_payoff_format"), money(plan.appliedAmount))
            : String(
                format: L("accounts_core.loan.prepayment.hint_format"),
                dayMonth(plan.nextPaymentDate, locale: locale)
            )

        let diff = preview.map { preview in diffRows(plan: plan, preview: preview, money: money, locale: locale) } ?? []

        return LoanPrepaymentPresentation(
            mode: plan.closesLoan ? .payoff : .prepayment,
            currency: currency,
            hint: hint,
            options: options(for: plan, frequency: frequency, currency: currency, locale: locale),
            selectedStrategy: effective,
            diff: diff,
            outcome: (preview?.savings ?? 0) > 0
                ? Outcome(
                    title: L("accounts_core.loan.prepayment.savings_title"),
                    value: money(preview?.savings ?? 0),
                    detail: nil,
                    style: .positive
                )
                : nil,
            confirmTitle: String(
                format: L("accounts_core.loan.prepayment.confirm_format"), money(plan.appliedAmount)
            ),
            // Полное погашение закрывается «сроком» — выбирать там нечего, кнопка активна сразу.
            entry: plan.closesLoan ? plan.entry(for: .term) : effective.flatMap { plan.entry(for: $0) }
        )
    }

    private static func diffRows(
        plan: LoanPrepaymentPlan,
        preview: LoanPrepaymentPreview,
        money: (Decimal) -> String,
        locale: Locale
    ) -> [DiffRow] {
        [
            DiffRow(
                id: "debt",
                title: L("accounts_core.loan.prepayment.row.debt"),
                before: money(plan.balanceBefore),
                after: money(plan.balanceAfter),
                afterStyle: .neutral
            ),
            DiffRow(
                id: "payment",
                title: L("accounts_core.loan.prepayment.row.payment"),
                before: money(plan.baselinePayment),
                after: plan.closesLoan
                    ? L("accounts_core.loan_form.value_empty")
                    : (preview.payment == plan.baselinePayment ? nil : money(preview.payment)),
                afterStyle: .neutral
            ),
            DiffRow(
                id: "payoff",
                title: L("accounts_core.loan.prepayment.row.payoff"),
                before: monthYear(plan.baselinePayoffDate, locale: locale),
                after: plan.closesLoan
                    ? L("accounts_core.loan.prepayment.closed")
                    : monthYear(preview.payoffDate, locale: locale),
                afterStyle: .neutral
            ),
            DiffRow(
                id: "interest",
                title: L("accounts_core.loan.prepayment.row.interest_ahead"),
                before: money(plan.baselineInterestAhead),
                after: money(preview.interestAhead),
                afterStyle: preview.savings > 0 ? .positive : .neutral
            )
        ]
    }

    /// Радио-строки. При полном погашении выбирать нечего, у дифференцированного графика сценарий
    /// «платёж» не определён — тогда строка одна.
    private static func options(
        for plan: LoanPrepaymentPlan, frequency: LoanPaymentFrequency, currency: String, locale: Locale
    ) -> [Option] {
        guard !plan.closesLoan else { return [] }
        let money = { (value: Decimal) in LoanMoneyFormat.money(value, currency: currency) }

        // Тег — АБСОЛЮТНАЯ экономия сценария. Разница экономий («выгоднее на N ₽») имела смысл при
        // предвыборе: она объясняла, почему выбран «срок». Без предвыбора сравнивать нечего с чем —
        // человеку нужна цена каждого варианта, а не перевес одного над другим.
        func tag(_ preview: LoanPrepaymentPreview) -> String? {
            guard preview.savings > 0 else { return nil }
            return String(
                format: L("accounts_core.loan.prepayment.saves_format"), money(preview.savings)
            )
        }

        var options = [
            Option(
                strategy: .term,
                title: L("accounts_core.loan.prepayment.option.term"),
                note: termNote(plan: plan, frequency: frequency, currency: currency, locale: locale),
                tag: tag(plan.term)
            )
        ]
        if let payment = plan.payment {
            options.append(
                Option(
                    strategy: .payment,
                    title: L("accounts_core.loan.prepayment.option.payment"),
                    note: String(
                        format: L("accounts_core.loan.prepayment.payment_note_format"),
                        money(payment.payment)
                    ),
                    tag: tag(payment)
                )
            )
        }
        return options
    }

    /// «…закроется на 13 месяцев раньше» макета: сокращение считается в МЕСЯЦАХ, а не в платежах —
    /// при квартальной периодичности «на 13 платежей» человеку ни о чём не говорит.
    private static func termNote(
        plan: LoanPrepaymentPlan, frequency: LoanPaymentFrequency, currency: String, locale: Locale
    ) -> String {
        let shortened = -plan.term.paymentsDelta
        guard shortened > 0 else {
            return String(
                format: L("accounts_core.loan.prepayment.term_note_same_format"),
                LoanMoneyFormat.money(plan.term.payment, currency: currency)
            )
        }
        let earlier = L("accounts_core.loan_form.term_months \(shortened * frequency.stepMonths)")
        // У дифференцированного графика платёж убывает сам — «платёж остаётся» было бы неправдой,
        // постоянная величина в нём другая: тело в периоде.
        let base = plan.payment == nil
            ? String(format: L("accounts_core.loan.prepayment.term_note_differentiated_format"), earlier)
            : String(
                format: L("accounts_core.loan.prepayment.term_note_format"),
                LoanMoneyFormat.money(plan.term.payment, currency: currency),
                earlier
            )
        // Дата закрытия — прямо в подписи варианта: без предвыбора таблица «что изменится» до
        // выбора пуста, и «на 13 месяцев раньше» не с чем соотнести.
        guard let payoffDate = plan.term.payoffDate else { return base }
        return String(
            format: L("accounts_core.loan.prepayment.note_payoff_format"),
            base, monthYear(payoffDate, locale: locale)
        )
    }

    // MARK: - Недоплата

    private static func make(
        underpayment plan: LoanUnderpaymentPlan,
        currency: String,
        locale: Locale
    ) -> LoanPrepaymentPresentation {
        let money = { (value: Decimal) in LoanMoneyFormat.money(value, currency: currency) }
        let hint = plan.principalPart > 0
            ? String(
                format: L("accounts_core.loan.prepayment.hint_underpayment_format"),
                money(plan.scheduledPayment)
            )
            : String(
                format: L("accounts_core.loan.prepayment.hint_below_interest_format"),
                money(plan.periodInterest)
            )

        let diff = [
            DiffRow(
                id: "debt",
                title: L("accounts_core.loan.prepayment.row.debt"),
                before: money(plan.balanceBefore),
                after: plan.principalPart > 0 ? money(plan.balanceAfter) : nil,
                afterStyle: .neutral
            ),
            DiffRow(
                id: "payment",
                title: L("accounts_core.loan.prepayment.row.payment"),
                before: money(plan.scheduledPayment),
                after: nil,
                afterStyle: .neutral
            ),
            DiffRow(
                id: "payoff",
                title: L("accounts_core.loan.prepayment.row.payoff"),
                before: monthYear(plan.baselinePayoffDate, locale: locale),
                after: monthYear(plan.payoffDate, locale: locale),
                afterStyle: plan.paymentsDelta > 0 ? .negative : .neutral
            ),
            DiffRow(
                id: "interest",
                title: L("accounts_core.loan.prepayment.row.interest_ahead"),
                before: money(plan.baselineInterestAhead),
                // Проценты меряются от того же момента, что и «было»: те, что закрываются сейчас,
                // из будущего никуда не делись — они просто уже уплачены.
                after: money(plan.baselineInterestAhead + plan.extraInterest),
                afterStyle: plan.extraInterest > 0 ? .negative : .neutral
            )
        ]

        return LoanPrepaymentPresentation(
            mode: .underpayment,
            currency: currency,
            hint: hint,
            options: [],
            selectedStrategy: nil,
            diff: diff,
            outcome: plan.extraInterest > 0
                ? Outcome(
                    title: L("accounts_core.loan.prepayment.growth_title"),
                    value: money(plan.extraInterest),
                    detail: plan.paymentsDelta > 0
                        ? String(
                            format: L("accounts_core.loan.prepayment.growth_term_format"),
                            L("accounts_core.loan.prepayment.payments \(plan.paymentsDelta)")
                        )
                        : nil,
                    style: .negative
                )
                : nil,
            confirmTitle: String(
                format: L("accounts_core.loan.prepayment.confirm_format"),
                money(plan.interestPart + plan.principalPart)
            ),
            entry: plan.entry
        )
    }

    // MARK: - Даты

    /// «15 сентября» подсказки: год в ней лишний — платёж всегда ближайший.
    private static func dayMonth(_ date: Date, locale: Locale) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(locale))
    }

    /// «мар 2031» строки «Закроется»: сокращение месяца без точки, год полностью.
    private static func monthYear(_ date: Date?, locale: Locale) -> String {
        guard let date else { return L("accounts_core.loan_form.value_empty") }
        return date
            .formatted(.dateTime.month(.abbreviated).year().locale(locale))
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " г", with: "")
    }
}
