import SwiftUI
import SwiftData

/// Вклад (`.deposit`): строки инфо, начисленные проценты, налоговая витрина и прогнозы «чистыми».
extension AccountDetailView {
    // MARK: - Вклад (.deposit) — доп. инфо, прогнозы «чистыми», досрочное закрытие (Фаза 3)

    var depositInfoLines: [String]? {
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
    var accruedInterestTotal: Decimal {
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
    var monthlyForecastGross: Decimal? {
        guard account.kind == .deposit else { return nil }
        let today = Date()
        guard let inMonth = Calendar.current.date(byAdding: .month, value: 1, to: today) else { return nil }
        let balanceIn1Month = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .deposit, on: inMonth)
        return max(0, balanceIn1Month - balanceToday)
    }

    var termForecastGross: Decimal? {
        guard account.kind == .deposit, let termEnd = account.depositMeta?.termEnd else { return nil }
        let balanceAtTerm = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .deposit, on: termEnd)
        return max(0, balanceAtTerm - balanceToday)
    }

    /// Эффективная ставка налога «чистыми» для ЭТОГО вклада за текущий календарный год (спека §2.8):
    /// доля Σ interest всех вкладов владельца, отнесённая налогом на ЭТОТ счёт, делённая на его gross.
    /// Приближение для прогноза (месяц/срок ещё не наступили — используем ставку текущего года).
    /// Foreign interest is deliberately incomplete here until event-date historical evidence is
    /// loaded asynchronously. Relabelling its nominal amount as RUB would fabricate a tax value.
    var depositTaxAllocationForThisAccount: DepositTaxAllocation? {
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

    var depositTaxPresentation: DepositTaxPresentation? {
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
    var effectiveNetTaxRate: Decimal {
        guard let allocation = depositTaxAllocationForThisAccount, allocation.grossInterestRUB > 0 else { return 0 }
        return allocation.allocatedTaxRUB / allocation.grossInterestRUB
    }

    /// Налог за ТЕКУЩИЙ год, уже начисленный этому вкладу (спека §2.8: «налог за год ≈Z») — оценка,
    /// не событие (не порождает expense, см. докстринг `DepositTaxCalculator`).
    var yearlyTaxEstimateForThisAccount: Decimal {
        depositTaxAllocationForThisAccount?.allocatedTaxRUB ?? 0
    }

    func netAmount(_ gross: Decimal) -> Decimal {
        gross * (1 - effectiveNetTaxRate)
    }
}
