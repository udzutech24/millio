//
//  CashflowAccountPickerDetails.swift
//  millio
//

import Foundation

/// Иконка и «доступно к трате» для строки пикера счёта Cashflow.
/// `availableAmount == nil` — остаток неизвестен (ещё не посчитан или счёт не резолвится):
/// строка рисует прочерк, а НЕ «0», чтобы незагруженный срез не выдавался за реальный ноль.
struct CashflowAccountPickerDetails: Equatable {
    /// SF Symbol или монограмма вида `monogram:СБ` (см. `AccountIconSet`).
    let iconName: String?
    let iconColorHex: String?
    let fallbackIconName: String
    let availableAmount: Decimal?
}

/// Сборка презентационных деталей строки пикера из моделей обоих миров счетов.
enum CashflowAccountPickerDetailsFactory {

    /// Легаси-карта: иконка и цвет свои. «Доступно к трате» = `CardSnapshot.availableAmount`
    /// — для дебетовой это остаток, для кредитки уже доступный лимит (см. `CardSnapshotFactory`).
    static func details(for card: Card) -> CashflowAccountPickerDetails {
        let snapshot = CardSnapshotFactory.make(from: card)
        return CashflowAccountPickerDetails(
            iconName: card.resolvedIconName,
            // `cardColor` хранит и hex, и текстовые имена — в бейдж отдаём только заведомо hex-поле.
            iconColorHex: card.customIconColor,
            fallbackIconName: card.cardType.icon,
            availableAmount: Decimal(snapshot.availableAmount)
        )
    }

    /// Счёт нового ядра: полей иконки/цвета/избранного в схеме нет (миграция отложена,
    /// см. `millio-schema-frozen-types-trap`) — рисуем монограмму по имени.
    /// Баланс приходит извне: он не хранится полем, а является реплеем событий.
    static func details(for account: Account, balance: Decimal?) -> CashflowAccountPickerDetails {
        CashflowAccountPickerDetails(
            iconName: AccountIconSet.monogramIconName(account.name),
            iconColorHex: nil,
            fallbackIconName: account.kind.fallbackIconName,
            availableAmount: balance
        )
    }

    static func details(for investment: Investment) -> CashflowAccountPickerDetails {
        CashflowAccountPickerDetails(
            iconName: investment.resolvedIconName,
            iconColorHex: investment.customIconColor,
            fallbackIconName: investment.category.icon,
            availableAmount: Decimal(investment.amount)
        )
    }
}
