import Foundation

/// Маппинг легаси-счёта (Card/Credit/Investment) в параметры создания core-двойника (Track C, MVP).
///
/// Знаковый вклад в тотал берётся ТОЧНО как в `FinanceTotalsService.getAccountAmount` — это единый
/// источник правды; иначе «Общий баланс» после конвертации разойдётся (ключевой acceptance-тест).
/// `openingBalance` приведён к знаку движка нового ядра:
///  - cashLike (`.debitCard`) / manualAsset (`.manualAsset`) — движок возвращает баланс = +opening,
///    поэтому opening = знаковый вклад;
///  - loan (`.loan`) — движок C возвращает баланс = −opening, поэтому opening = магнитуда.
enum LegacyAccountConversion {

    struct Plan {
        let legacyUniqueID: String
        let name: String
        let currency: String
        let kind: AccountKind
        let openingBalance: Decimal
        let cardMeta: CardMeta?
        let loanMeta: LoanMeta?
        let manualAssetMeta: ManualAssetMeta?
    }

    /// Карта → `.debitCard` (движок cashLike). Знаковый вклад = `netWorthAmount` (для кредитной
    /// карты это −долг, для дебетовой — доступный остаток, 0 при `includeInTotal == false`).
    static func plan(for card: Card) -> Plan {
        let signed = CardSnapshotFactory.make(from: card).netWorthAmount
        let last4 = card.maskedNumber
        return Plan(
            legacyUniqueID: card.cardUniqueID,
            name: card.name,
            currency: card.currency,
            kind: .debitCard,
            openingBalance: Decimal(signed),
            cardMeta: CardMeta(bank: card.bankRaw, last4: last4.isEmpty ? nil : last4),
            loanMeta: nil,
            manualAssetMeta: nil
        )
    }

    /// Кредит → `.loan` (движок C — обязательство). `getAccountAmount` вносит −`remainingAmount`
    /// ВСЕГДА (без учёта `includeInTotal` — легаси-конвенция), движок C даёт баланс = −opening,
    /// поэтому opening = магнитуда `remainingAmount`.
    static func plan(for credit: Credit) -> Plan {
        return Plan(
            legacyUniqueID: credit.creditUniqueID,
            name: credit.name,
            currency: credit.currency,
            kind: .loan,
            openingBalance: Decimal(credit.remainingAmount),
            cardMeta: nil,
            loanMeta: LoanMeta(
                principal: Decimal(credit.amount),
                rate: Decimal(credit.interestRate),
                monthlyPayment: credit.monthlyPayment > 0 ? Decimal(credit.monthlyPayment) : nil,
                paymentDay: credit.paymentDayOfMonth,
                termEnd: credit.endDate,
                scheduleType: .annuity,
                insurance: nil
            ),
            manualAssetMeta: nil
        )
    }

    /// Инвестиция → `.manualAsset` (движок F замораживает значение одним opening-событием).
    ///
    /// Осознанная девиация от «инвестиция → рыночный тип» брифинга: рыночный движок E считает
    /// баланс как quantity×price и ИГНОРИРУЕТ opening — двойник показал бы 0, ломая инвариант
    /// тотала; MVP запрещает реплей истории/котировок. `.deposit` потребовал бы meta/scheduler и
    /// рисковал бы будущим дрейфом от начислений. `.manualAsset` замораживает любое значение без
    /// meta и без дрейфа — единственный вариант, гарантирующий инвариант при MVP-ограничениях.
    /// Знаковый вклад = ±`amount` при `includeInTotal`, иначе 0 (как в `getAccountAmount`).
    static func plan(for investment: Investment, currency: String) -> Plan {
        let signed = investment.includeInTotal
            ? (investment.investmentType == .positive ? investment.amount : -investment.amount)
            : 0
        return Plan(
            legacyUniqueID: investment.investmentUniqueID,
            name: investment.name,
            currency: currency,
            kind: .manualAsset,
            openingBalance: Decimal(signed),
            cardMeta: nil,
            loanMeta: nil,
            manualAssetMeta: ManualAssetMeta(revalReminderMonths: nil, depreciationRatePerYear: nil, linkedLoanID: nil)
        )
    }
}
