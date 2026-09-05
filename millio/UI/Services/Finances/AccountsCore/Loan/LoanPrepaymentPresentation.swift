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
        /// «выгоднее на 126 316 ₽» — только у выгодного сценария.
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
    /// Сценарий, который реально применится: у дифференцированного графика «платёж» не определён,
    /// и выбор молча падает обратно на «срок».
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
        strategy: LoanPrepaymentStrategy,
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
        strategy: LoanPrepaymentStrategy,
        frequency: LoanPaymentFrequency,
        currency: String,
        locale: Locale
    ) -> LoanPrepaymentPresentation {
        let effective = plan.preview(for: strategy) != nil ? strategy : .term
        // `term` есть всегда — им и закрывается полное погашение, где выбора нет.
        let preview = plan.preview(for: effective) ?? plan.term
        let money = { (value: Decimal) in LoanMoneyFormat.money(value, currency: currency) }

        let hint = plan.closesLoan
            ? String(format: L("accounts_core.loan.prepayment.hint_payoff_format"), money(plan.appliedAmount))
            : String(
                format: L("accounts_core.loan.prepayment.hint_format"),
                dayMonth(plan.nextPaymentDate, locale: locale)
            )

        let diff = [
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

        return LoanPrepaymentPresentation(
            mode: plan.closesLoan ? .payoff : .prepayment,
            currency: currency,
            hint: hint,
            options: options(for: plan, frequency: frequency, currency: currency),
            selectedStrategy: plan.closesLoan ? nil : effective,
            diff: diff,
            outcome: preview.savings > 0
                ? Outcome(
                    title: L("accounts_core.loan.prepayment.savings_title"),
                    value: money(preview.savings),
                    detail: nil,
                    style: .positive
                )
                : nil,
            confirmTitle: String(
                format: L("accounts_core.loan.prepayment.confirm_format"), money(plan.appliedAmount)
            ),
            entry: plan.entry(for: effective)
        )
    }

    /// Радио-строки. При полном погашении выбирать нечего, у дифференцированного графика сценарий
    /// «платёж» не определён — тогда строка одна.
    private static func options(
        for plan: LoanPrepaymentPlan, frequency: LoanPaymentFrequency, currency: String
    ) -> [Option] {
        guard !plan.closesLoan else { return [] }
        let money = { (value: Decimal) in LoanMoneyFormat.money(value, currency: currency) }

        // «Выгоднее на N ₽» — разница экономий двух сценариев, а не разница платежей: сравнивать
        // надо то, ради чего досрочку и вносят.
        let advantage: Decimal? = plan.payment.map { plan.term.savings - $0.savings }
        func tag(_ value: Decimal) -> String? {
            guard value > 0 else { return nil }
            return String(format: L("accounts_core.loan.prepayment.better_by_format"), money(value))
        }

        var options = [
            Option(
                strategy: .term,
                title: L("accounts_core.loan.prepayment.option.term"),
                note: termNote(plan: plan, frequency: frequency, currency: currency),
                tag: advantage.flatMap { tag($0) }
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
                    tag: advantage.flatMap { tag(-$0) }
                )
            )
        }
        return options
    }

    /// «…закроется на 13 месяцев раньше» макета: сокращение считается в МЕСЯЦАХ, а не в платежах —
    /// при квартальной периодичности «на 13 платежей» человеку ни о чём не говорит.
    private static func termNote(
        plan: LoanPrepaymentPlan, frequency: LoanPaymentFrequency, currency: String
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
        guard plan.payment != nil else {
            return String(format: L("accounts_core.loan.prepayment.term_note_differentiated_format"), earlier)
        }
        return String(
            format: L("accounts_core.loan.prepayment.term_note_format"),
            LoanMoneyFormat.money(plan.term.payment, currency: currency),
            earlier
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
