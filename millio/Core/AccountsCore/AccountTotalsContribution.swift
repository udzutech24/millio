import Foundation

/// Знаковый вклад ядрового счёта в НЕТ-тотал/сальдо (net worth) — ЕДИНАЯ точка на всех потребителей
/// (тоталы шапки, тотал группы, серия Динамики, карточка, строка списка, секции Активы/Обязательства,
/// красный агрегат «Кредит»). Отличается от `AccountBalanceEngine.balanceAt` = «баланс счёта»
/// (остаток на карте, который показывает экран деталки) — это РАЗНЫЕ величины (см. Ф7b плана).
enum AccountTotalsContribution {

    /// Кредитная карта (денежный card-пресет с заданным `creditLimit`) входит в тотал как ДОЛГ:
    /// вклад = остаток(`balanceAt`) − лимит = −(лимит − остаток) = −долг. Это аффинный дериват баланса,
    /// поэтому долг = лимит − остаток остаётся согласованным с реплеем при ЛЮБОМ движении по карте
    /// (расход уменьшает остаток → увеличивает долг; погашение — наоборот).
    ///
    /// Ключуемся на НАЛИЧИИ `creditLimit`, а НЕ на `kind == .debitCard`. Причина (баг Ф7b-2, девайс):
    /// форма «Новый продукт» кладёт кредитку без выбранного банка в `kind == .cash`
    /// (`AccountsCoreAdditionBridge.cardKind(bank: .other) == .cash`), поэтому строгий гард на `.debitCard`
    /// «терял знак» — карта уходила в сальдо как +остаток. `creditLimit` проставляется ТОЛЬКО card-пресетом
    /// при `cardType == .credit` (`FinanceAddAccountView.createMoneyAccountOnNewCore`), значит его наличие —
    /// надёжный признак кредитки независимо от cash/debitCard-классификации. Ограничиваемся денежными
    /// card-kind'ами (`.cash`/`.debitCard`), чтобы гипотетический лимит на другом kind не превращался в долг.
    ///
    /// Все прочие счета — вклад равен балансу без изменений. Инвариант: `creditLimit == nil`
    /// (дебетовые карты и любой счёт без кредитного лимита) → значение бит-в-бит прежнее. Мигрированные
    /// легаси-кредитки этот путь НЕ трогает: у них `creditLimit == nil`, а знак уже зашит в signed
    /// `openingBalance` конвертером (`LegacyAccountConversion`), поэтому двойного применения нет.
    static func signedValue(rawBalance: Decimal, kind: AccountKind, creditLimit: Decimal?) -> Decimal {
        guard kind == .debitCard || kind == .cash, let creditLimit else { return rawBalance }
        return CreditCardFinancialContract.netPosition(
            rawAvailableBalance: rawBalance,
            creditLimit: creditLimit
        )
    }
}
