//
//  CashbackCardPresentation.swift
//  millio
//
//  Centralized copy for cashback account selection screens.
//

import Foundation

/// Тексты строки счёта в пикере кэшбэка. Работает на едином `CashflowSelectableAccount`
/// (карты легаси ∪ core-счета нового ядра), поэтому несёт только поля, общие для обоих миров:
/// имя и валюту. Богатая мета легаси-карты (банк/тип/маскированный номер/баланс/лимит) сюда
/// не входит — у core `Account` её нет (баланс — производная движка, `cardType`/маска отсутствуют),
/// а смешанный пикер должен выглядеть единообразно (6b Путь B, Ф5c.4).
enum CashbackCardPresentation {
    static func title(for account: CashflowSelectableAccount, locale: Locale = CashbackL10n.locale) -> String {
        account.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CashbackL10n.text("cashback.card.unnamed", locale: locale, fallback: "Untitled card")
            : account.title
    }

    /// Подзаголовок строки счёта — валюта (единственное общее поле-различитель для одноимённых счетов).
    static func subtitle(for account: CashflowSelectableAccount, locale: Locale = CashbackL10n.locale) -> String {
        account.currency.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func pickerSubtitle(for account: CashflowSelectableAccount, locale: Locale = CashbackL10n.locale) -> String {
        subtitle(for: account, locale: locale)
    }
}
