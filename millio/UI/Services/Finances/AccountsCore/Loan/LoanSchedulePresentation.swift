import Foundation

/// Строка графика платежей (макет, ЭКРАН 3): месяц · доли тела и процентов · сумма платежа.
struct LoanScheduleRowPresentation: Identifiable, Equatable {
    /// Номер платежа в графике, с 1 — он же идентификатор строки.
    let index: Int
    let date: Date
    let payment: Decimal
    let principal: Decimal
    let interest: Decimal
    /// Платёж уже внесён — строка приглушается, чтобы «N впереди» на деталке читалось глазами.
    let isPaid: Bool
    /// Ближайший невнесённый платёж — подсвеченная строка «текущий период».
    let isCurrent: Bool
    /// «Апр 26» — три буквы месяца и две цифры года; форматируется витриной, не вью.
    let monthLabel: String
    let paymentText: String

    var id: Int { index }

    /// Доля тела в платеже, 0...1 — ширина зелёной части полосы.
    var principalShare: Decimal {
        payment > 0 ? min(max(principal / payment, .zero), 1) : .zero
    }

    /// Та же доля целыми процентами — колонка «Тело %» таблицы макета. На экране доля выражена
    /// шириной полосы, отдельным числом не печатается, но именно она сверяется с макетом в тестах.
    var principalPercent: Int {
        var result = Decimal()
        var value = principalShare * 100
        NSDecimalRound(&result, &value, 0, .plain)
        return NSDecimalNumber(decimal: result).intValue
    }
}

/// Витрина экрана «График платежей»: все цифры считает `LoanScheduleEngine`, вью не считает ничего.
///
/// Прошлое и будущее берутся из РАЗНЫХ расчётов, и это намеренно:
/// - внесённые платежи — строки исходного графика договора (их уже нельзя пересчитать задним числом);
/// - платежи впереди — график от ФАКТИЧЕСКОГО остатка тем же `LoanScheduleEngine.remainingTerms`,
///   которым живёт деталка. Иначе после досрочного погашения число строк впереди разошлось бы со строкой
///   «N впереди», из которой на этот экран и заходят.
struct LoanSchedulePresentation: Equatable {
    let currency: String
    /// Сумма кредита — база доли переплаты.
    let principal: Decimal
    let rows: [LoanScheduleRowPresentation]
    let paymentsMade: Int
    let paymentsAhead: Int
    /// Проценты за весь срок: уже уплаченные по графику плюс те, что впереди.
    let totalOverpayment: Decimal
    /// Доля переплаты от суммы кредита, 0...1 — «55,3% от суммы кредита» макета.
    let overpaymentShare: Decimal

    static func make(
        terms: LoanTerms,
        outstandingPrincipal: Decimal,
        paymentsMade: Int,
        currency: String,
        calendar: Calendar = Calendar(identifier: .gregorian),
        locale: Locale = AppLocalization.currentAppLocale
    ) -> LoanSchedulePresentation {
        let principal = max(terms.principal, .zero)
        let contractRows = LoanScheduleEngine.schedule(terms: terms, calendar: calendar).rows
        let made = min(max(paymentsMade, 0), contractRows.count)

        let formatter = monthFormatter(locale: locale, calendar: calendar)
        func row(
            _ source: LoanScheduleRow, index: Int, isPaid: Bool, isCurrent: Bool
        ) -> LoanScheduleRowPresentation {
            LoanScheduleRowPresentation(
                index: index,
                date: source.date,
                payment: source.payment,
                principal: source.principal,
                interest: source.interest,
                isPaid: isPaid,
                isCurrent: isCurrent,
                monthLabel: monthLabel(
                    for: source.date, formatter: formatter, calendar: calendar, locale: locale
                ),
                paymentText: LoanMoneyFormat.money(source.payment, currency: currency)
            )
        }

        let paid = contractRows.prefix(made).map {
            row($0, index: $0.index, isPaid: true, isCurrent: false)
        }
        let aheadTerms = LoanScheduleEngine.remainingTerms(
            terms: terms,
            outstanding: max(outstandingPrincipal, .zero),
            paymentsMade: made,
            calendar: calendar
        )
        let ahead = LoanScheduleEngine.schedule(terms: aheadTerms, calendar: calendar).rows.map {
            row($0, index: made + $0.index, isPaid: false, isCurrent: $0.index == 1)
        }

        let rows = paid + ahead
        // Переплата — сумма процентов ровно тех строк, что показаны на экране: карточка итога не
        // должна спорить с таблицей над ней. После досрочного погашения она пересчитается сама.
        let overpayment = rows.reduce(Decimal.zero) { $0 + $1.interest }

        return LoanSchedulePresentation(
            currency: currency,
            principal: principal,
            rows: rows,
            paymentsMade: made,
            paymentsAhead: ahead.count,
            totalOverpayment: overpayment,
            overpaymentShare: principal > 0 ? overpayment / principal : .zero
        )
    }

    // MARK: - Месяц

    private static func monthFormatter(locale: Locale, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("LLL")
        return formatter
    }

    /// «Апр 26» макета: месяц и год собираются по отдельности, а не готовым шаблоном «LLL yy» —
    /// тот в русской локали добавляет «г.» («апр. 26 г.»), и узкая колонка перестаёт помещаться.
    /// Точку сокращения убираем, первую букву поднимаем; на en и zh-Hans это ничего не меняет.
    private static func monthLabel(
        for date: Date, formatter: DateFormatter, calendar: Calendar, locale: Locale
    ) -> String {
        let month = formatter.string(from: date).replacingOccurrences(of: ".", with: "")
        let year = calendar.component(.year, from: date) % 100
        guard let first = month.first else { return month }
        return String(first).uppercased(with: locale) + month.dropFirst() + " " + String(format: "%02d", year)
    }
}

// MARK: - Форматирование

extension LoanSchedulePresentation {
    var overpaymentText: String { LoanMoneyFormat.money(totalOverpayment, currency: currency) }

    var overpaymentShareText: String { LoanMoneyFormat.percent(overpaymentShare) }
}
