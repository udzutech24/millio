import Foundation

/// Единственная точка, где условия кредита превращаются в вход расчётного ядра.
///
/// Правило Р5 спеки: договор `LoanContract` — источник правды, легаси `LoanMeta` — только сид для
/// счетов, заведённых до детального режима. Обратной синхронизации нет, `LoanMeta` не расширяется
/// и не переписывается. Любое чтение условий кредита в приложении обязано идти сюда, иначе два
/// источника разъедутся (риск №1 спеки).
enum LoanTermsResolver {

    static func terms(
        for account: Account,
        contract: LoanContract?,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> LoanTerms? {
        if let contract { return contract.terms }
        guard let meta = account.loanMeta else { return nil }
        return LoanTerms(legacy: meta, openingDate: openingDate(of: account), calendar: calendar)
    }

    /// Дата открытия счёта = дата самого раннего события ленты (обычно `.opening`), а не
    /// `createdAt`: у импортированных и сконвертированных счетов `createdAt` — момент импорта,
    /// и график начинался бы не там, где реально начался кредит.
    private static func openingDate(of account: Account) -> Date {
        account.events?.map(\.date).min() ?? account.createdAt
    }
}
