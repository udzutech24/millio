import SwiftUI
import SwiftData

/// Шапка карточки счёта: presentation для `AccountHeroCardView` и строки идентичности.
extension AccountDetailView {
    /// Сумма hero — ровно то же число, что в строке списка «Счета» и в тоталах: у кредитки это
    /// долг со знаком минус, а не доступный лимит. Второго определения баланса не заводим.
    var heroAmount: Decimal {
        AccountTotalsContribution.signedValue(
            rawBalance: balanceToday,
            kind: account.kind,
            creditLimit: account.cardMeta?.creditLimit
        )
    }

    var heroPresentation: AccountHeroPresentation {
        AccountHeroPresentation.make(
            key: account.id.uuidString,
            name: account.name,
            appearance: appearance,
            fallbackIconName: account.kind.fallbackIconName,
            subtitle: heroSubtitle,
            typeTitle: heroTypeTitle,
            amountText: AccountRowAmountFormatter.text(
                NSDecimalNumber(decimal: heroAmount).doubleValue,
                isHidden: false,
                maximumFractionDigits: account.kind == .marketInvestment ? 2 : 0
            ),
            currencySymbol: MonetaCurrency(rawValue: account.currency)?.symbol ?? account.currency,
            isNegative: heroAmount < 0,
            detailLines: heroDetailLines,
            badges: heroBadges
        )
    }

    /// Тип продукта на hero. Кредитка — не отдельный `AccountKind` (это `debitCard` с лимитом),
    /// поэтому её название разрешается по `productType`, а не по `kind`.
    var heroTypeTitle: String {
        account.productType == .creditCard
            ? L("accounts_core.detail.type.credit_card")
            : account.kind.localizedTitle
    }

    /// Вторая строка идентичности: у рыночной позиции — тикер, у карты — банк и `•• last4`.
    var heroSubtitle: String? {
        if account.kind == .marketInvestment, let symbol = account.marketMeta?.symbol, !symbol.isEmpty {
            return symbol.uppercased()
        }
        return bankLine
    }

    var heroDetailLines: [String] {
        var lines: [String] = []
        lines.append(contentsOf: loanInfoLines ?? [])
        lines.append(contentsOf: debtInfoLines ?? [])
        lines.append(contentsOf: depositInfoLines ?? [])
        if let creditHeroLine { lines.append(creditHeroLine) }
        if account.kind == .marketInvestment {
            // Нереализованный P/L был на прежнем `stockHero` — теряться при переезде он не должен.
            lines.append("\(signedAmountText(unrealizedPL, type: .adjustment)) \(account.currency)")
        }
        if let note = account.note, !note.isEmpty { lines.append(note) }
        return lines
    }

    /// Кредитка на hero: доступный лимит и дата ближайшего платежа. Подробные метрики (утилизация,
    /// проценты, комиссии) остаются в `CreditCardDetailSection` — hero их не дублирует.
    var creditHeroLine: String? {
        guard account.productType == .creditCard, let limit = account.cardMeta?.creditLimit else { return nil }
        guard let snapshot = CreditCardFinancialContract.snapshot(
            rawAvailableBalance: balanceToday,
            creditLimit: limit,
            events: account.events ?? []
        ) else { return nil }
        var parts = [String(
            format: L("accounts_core.detail.credit.available_format"),
            NSDecimalNumber(decimal: snapshot.availableLimit).doubleValue,
            account.currency
        )]
        if let settings = CreditCardPaymentSettingsStore().load(accountID: account.id),
           let status = CreditCardPaymentPolicy.status(
               settings: settings,
               graceDays: account.cardMeta?.graceDays,
               now: Date(),
               calendar: .current
           ) {
            parts.append(String(
                format: L("accounts_core.detail.credit.payment_due_format"),
                status.dueDate.formatted(date: .abbreviated, time: .omitted)
            ))
        }
        return parts.joined(separator: " · ")
    }

    var heroBadges: [AccountHeroPresentation.Badge] {
        var badges: [AccountHeroPresentation.Badge] = []
        if account.archivedAt != nil {
            badges.append(.init(text: L("accounts_core.detail.badge.archived"), systemImage: "archivebox"))
        }
        if !account.includeInTotal {
            badges.append(.init(text: L("accounts_core.detail.total.excluded"), systemImage: "sum"))
        }
        if account.kind == .marketInvestment {
            badges.append(.init(
                text: isPriceStale
                    ? L("accounts_core.detail.market.price_stale_badge")
                    : L("accounts_core.detail.market.price_today_badge"),
                systemImage: isPriceStale ? "clock.badge.exclamationmark" : "bolt.fill",
                isWarning: isPriceStale
            ))
        }
        return badges
    }

    // MARK: - Header

    /// Прежние `standardHeader` и `stockHero` сняты в Ф3: их содержимое переехало в
    /// `AccountHeroCardView` (`heroDetailLines` / `heroBadges` / `heroSubtitle`).
    var bankLine: String? {
        guard let cardMeta = account.cardMeta else { return nil }
        var parts: [String] = []
        if let bankRaw = cardMeta.bank, let bank = Bank(rawValue: bankRaw) {
            parts.append(bank.displayName)
        }
        if let last4 = cardMeta.last4, !last4.isEmpty {
            parts.append("•• \(last4)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
