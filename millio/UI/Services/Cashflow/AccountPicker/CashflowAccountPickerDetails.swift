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

    /// Единственная точка выбора внешнего вида счёта — общая для обоих миров.
    /// Приоритет цвета: ручной `tintHex` → акцент выбранного дизайна (`presetRaw`, Ф2) →
    /// легаси-поля счёта → детерминированный дефолт из палитры по `key`.
    /// Пикер держит `tintHex` и `presetRaw` взаимоисключающими, но порядок нужен всё равно:
    /// бэкап чужой/будущей версии может принести оба поля сразу.
    /// `key` обязан быть стабильным на всю жизнь счёта (`Account.id` / `*UniqueID`), иначе цвет
    /// «поедет» при переименовании.
    static func resolvedAppearance(
        key: String,
        name: String,
        appearance: AccountAppearanceSnapshot?,
        legacyIconName: String? = nil,
        legacyIconColorHex: String? = nil
    ) -> (iconName: String?, iconColorHex: String?) {
        // Пустое имя монограммы не даёт: `monogram:` нарисовался бы пустым бейджем — в этом случае
        // отдаём nil, и бейдж берёт `fallbackIconName` (иконку типа продукта).
        let monogram = AccountIconSet.normalizedMonogram(name).isEmpty
            ? nil
            : AccountIconSet.monogramIconName(name)
        let presetAccent = AccountAppearancePreset.resolve(appearance?.presetRaw)?.accentHex
        return (
            appearance?.iconName ?? legacyIconName ?? monogram,
            appearance?.tintHex
                ?? presetAccent
                ?? legacyIconColorHex
                ?? AccountAppearanceDefaults.tintHex(forKey: key)
        )
    }

    /// Легаси-карта: иконка и цвет свои. «Доступно к трате» = `CardSnapshot.availableAmount`
    /// — для дебетовой это остаток, для кредитки уже доступный лимит (см. `CardSnapshotFactory`).
    static func details(
        for card: Card,
        appearance: AccountAppearanceSnapshot? = nil
    ) -> CashflowAccountPickerDetails {
        let snapshot = CardSnapshotFactory.make(from: card)
        let resolved = resolvedAppearance(
            key: card.cardUniqueID,
            name: snapshot.name,
            appearance: appearance,
            legacyIconName: card.customIconName,
            // `cardColor` хранит и hex, и текстовые имена — в бейдж отдаём только заведомо hex-поле.
            legacyIconColorHex: card.customIconColor
        )
        return CashflowAccountPickerDetails(
            iconName: resolved.iconName,
            iconColorHex: resolved.iconColorHex,
            fallbackIconName: card.cardType.icon,
            availableAmount: Decimal(snapshot.availableAmount)
        )
    }

    /// Счёт нового ядра: персонализация живёт в side-таблице `AccountAppearance` (V11), а не в
    /// полях `Account` — срез приходит готовым словарём из ViewModel, из тела строки не запрашиваем.
    /// Оформления нет → монограмма по имени + детерминированный цвет по `Account.id`.
    /// Баланс приходит извне: он не хранится полем, а является реплеем событий.
    static func details(
        for account: Account,
        appearance: AccountAppearanceSnapshot? = nil,
        balance: Decimal?
    ) -> CashflowAccountPickerDetails {
        let resolved = resolvedAppearance(
            key: account.id.uuidString,
            name: account.name,
            appearance: appearance
        )
        return CashflowAccountPickerDetails(
            iconName: resolved.iconName,
            iconColorHex: resolved.iconColorHex,
            fallbackIconName: account.kind.fallbackIconName,
            availableAmount: balance
        )
    }

    static func details(
        for investment: Investment,
        appearance: AccountAppearanceSnapshot? = nil
    ) -> CashflowAccountPickerDetails {
        let resolved = resolvedAppearance(
            key: investment.investmentUniqueID,
            name: investment.name,
            appearance: appearance,
            legacyIconName: investment.customIconName,
            legacyIconColorHex: investment.customIconColor
        )
        return CashflowAccountPickerDetails(
            iconName: resolved.iconName,
            iconColorHex: resolved.iconColorHex,
            fallbackIconName: investment.category.icon,
            availableAmount: Decimal(investment.amount)
        )
    }
}
