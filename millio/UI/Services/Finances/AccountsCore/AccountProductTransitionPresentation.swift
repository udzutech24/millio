import Foundation

/// Keeps the correction/conversion picker aligned with the product categories used by create-flow.
/// Technical subtypes remain selectable, but receive a qualifier when one create category maps to
/// several persisted `AccountProductType` values.
enum AccountProductTransitionPresentation {
    static func availableTargets(current: AccountProductType?) -> [AccountProductType] {
        AccountProductType.allCases.filter {
            $0 != .unknownLegacy && $0 != (current ?? .unknownLegacy)
        }
    }

    static func title(for productType: AccountProductType, locale: Locale) -> String {
        switch productType {
        case .cash:
            return FinancesL10n.tr("accounts_core.kind.cash", locale: locale)
        case .debitCard:
            return qualified(.card, CardType.debit.displayName(for: locale), locale: locale)
        case .creditCard:
            return qualified(.card, CardType.credit.displayName(for: locale), locale: locale)
        case .bankAccount:
            return FinanceAddAccountProductOption.account.title(locale: locale)
        case .deposit:
            return FinanceAddAccountProductOption.deposit.title(locale: locale)
        case .loan:
            return FinanceAddAccountProductOption.credit.title(locale: locale)
        case .receivable:
            return qualified(
                .debt,
                FinancesL10n.tr("accounts_core.detail.debt.direction.owed_to_me", locale: locale),
                locale: locale
            )
        case .payable:
            return qualified(
                .debt,
                FinancesL10n.tr("accounts_core.detail.debt.direction.owed_by_me", locale: locale),
                locale: locale
            )
        case .marketStock:
            return FinanceAddAccountProductOption.stocks.title(locale: locale)
        case .marketCrypto:
            return FinanceAddAccountProductOption.crypto.title(locale: locale)
        case .marketBond:
            return qualified(.investment, InvestmentCategory.bonds.displayName(for: locale), locale: locale)
        case .marketMetal:
            return qualified(.investment, InvestmentCategory.metals.displayName(for: locale), locale: locale)
        case .genericMarketInvestment:
            return FinanceAddAccountProductOption.investment.title(locale: locale)
        case .realEstate:
            return FinanceAddAccountProductOption.house.title(locale: locale)
        case .business:
            return FinanceAddAccountProductOption.business.title(locale: locale)
        case .vehicle:
            return qualified(.investment, InvestmentCategory.car.displayName(for: locale), locale: locale)
        case .otherManualAsset:
            return qualified(.investment, InvestmentCategory.other.displayName(for: locale), locale: locale)
        case .unknownLegacy:
            return FinanceAddAccountProductOption.other.title(locale: locale)
        }
    }

    private static func qualified(
        _ option: FinanceAddAccountProductOption,
        _ qualifier: String,
        locale: Locale
    ) -> String {
        "\(option.title(locale: locale)) — \(qualifier)"
    }
}
