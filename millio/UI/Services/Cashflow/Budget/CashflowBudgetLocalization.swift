//
//  CashflowBudgetLocalization.swift
//  millio
//
//  Created by Codex on 31.03.2026.
//

import Foundation

enum CashflowBudgetLocalization {
    private static func tr(_ key: String, fallback: String? = nil) -> String {
        AppLocalization.string(key, locale: AppLocalization.currentAppLocale, fallback: fallback)
    }

    static func setupTitle(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.setup.title.expense")
        case .income:
            return tr("cashflow.budget.setup.title.income")
        }
    }

    static func totalSectionTitle(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.total_section.title.expense")
        case .income:
            return tr("cashflow.budget.total_section.title.income")
        }
    }

    static func totalSectionHint(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.total_section.hint.expense")
        case .income:
            return tr("cashflow.budget.total_section.hint.income")
        }
    }

    static func totalToggleTitle(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.total_toggle.title.expense")
        case .income:
            return tr("cashflow.budget.total_toggle.title.income")
        }
    }

    static func totalToggleHint(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.total_toggle.hint.expense")
        case .income:
            return tr("cashflow.budget.total_toggle.hint.income")
        }
    }

    static func totalDisabledText(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.total_disabled.expense")
        case .income:
            return tr("cashflow.budget.total_disabled.income")
        }
    }

    static func categorySectionTitle(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.category_section.title.expense")
        case .income:
            return tr("cashflow.budget.category_section.title.income")
        }
    }

    static func categorySectionHint(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.category_section.hint.expense")
        case .income:
            return tr("cashflow.budget.category_section.hint.income")
        }
    }

    static func footerHint(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.footer_hint.expense")
        case .income:
            return tr("cashflow.budget.footer_hint.income")
        }
    }

    static func repeatSuggestionTitle(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.repeat.cta.expense")
        case .income:
            return tr("cashflow.budget.repeat.cta.income")
        }
    }

    static func autoRepeatHint(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.repeat.auto_hint.expense")
        case .income:
            return tr("cashflow.budget.repeat.auto_hint.income")
        }
    }

    static func categoryTotalsTitle(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.category_totals.expense")
        case .income:
            return tr("cashflow.budget.category_totals.income")
        }
    }

    static func categoryBudgetLimitLabel(for kind: CashflowCategoryKind, amount: String) -> String {
        switch kind {
        case .expense:
            return formatted(
                "cashflow.budget.category_limit_label.expense",
                defaultValue: "Limit %@",
                amount
            )
        case .income:
            return formatted(
                "cashflow.budget.category_limit_label.income",
                defaultValue: "Plan %@",
                amount
            )
        }
    }

    static func overflowMessage(for kind: CashflowCategoryKind, amount: String, currencyCode: String) -> String {
        switch kind {
        case .expense:
            return formatted(
                "cashflow.budget.overflow.expense",
                defaultValue: "Category limits exceed the total by %@ %@, so this setup cannot be saved",
                amount,
                currencyCode
            )
        case .income:
            return formatted(
                "cashflow.budget.overflow.income",
                defaultValue: "Category targets exceed the total by %@ %@, so this setup cannot be saved",
                amount,
                currencyCode
            )
        }
    }

    static func repeatSourceTitle(monthTitle: String) -> String {
        formatted(
            "cashflow.budget.repeat.source_title",
            defaultValue: "Use %@",
            monthTitle
        )
    }

    static func unsetCategoryValue(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .expense:
            return tr("cashflow.budget.category_unset.expense")
        case .income:
            return tr("cashflow.budget.category_unset.income")
        }
    }

    static func categoryStatusSubtitle(for kind: CashflowCategoryKind, snapshot: BudgetCategoryProgressSnapshot) -> String {
        let spent = cashflowAmountText(snapshot.spent)
        let limit = cashflowAmountText(snapshot.limit)

        switch snapshot.status {
        case .normal:
            return formatted(
                "cashflow.budget.category_status.normal",
                defaultValue: "%@ of %@",
                spent,
                limit
            )
        case .warning:
            switch kind {
            case .expense:
                return formatted(
                    "cashflow.budget.category_status.warning.expense",
                    defaultValue: "%@ of %@ · getting close to the limit",
                    spent,
                    limit
                )
            case .income:
                return formatted(
                    "cashflow.budget.category_status.warning.income",
                    defaultValue: "%@ of %@ · getting close to the plan",
                    spent,
                    limit
                )
            }
        case .critical:
            switch kind {
            case .expense:
                return formatted(
                    "cashflow.budget.category_status.critical.expense",
                    defaultValue: "%@ of %@ · almost at the limit",
                    spent,
                    limit
                )
            case .income:
                return formatted(
                    "cashflow.budget.category_status.critical.income",
                    defaultValue: "%@ of %@ · almost completed",
                    spent,
                    limit
                )
            }
        case .exceeded:
            switch kind {
            case .expense:
                return formatted(
                    "cashflow.budget.category_status.exceeded.expense",
                    defaultValue: "Over by %@",
                    cashflowAmountText(abs(snapshot.remaining))
                )
            case .income:
                return formatted(
                    "cashflow.budget.category_status.exceeded.income",
                    defaultValue: "Above the plan by %@",
                    cashflowAmountText(abs(snapshot.remaining))
                )
            }
        }
    }

    static var save: String { tr("cashflow.common.save") }
    static var reset: String { tr("cashflow.common.reset") }
    static var autoRepeat: String { tr("cashflow.budget.repeat.auto_title") }
    static var used: String { tr("cashflow.budget.hero.used") }
    static var periodLimit: String { tr("cashflow.budget.hero.period_limit") }
    static var emptyHint: String { tr("cashflow.budget.hero.empty_hint") }

    static func heroRemaining(_ amount: String, currencyCode: String) -> String {
        formatted(
            "cashflow.budget.hero.remaining",
            defaultValue: "%@ %@ remaining",
            amount,
            currencyCode
        )
    }

    static func heroExceeded(_ amount: String, currencyCode: String) -> String {
        formatted(
            "cashflow.budget.hero.exceeded",
            defaultValue: "Over by %@ %@",
            amount,
            currencyCode
        )
    }

    static func heroOverflow(kind: CashflowCategoryKind, amount: String, currencyCode: String) -> String {
        switch kind {
        case .expense:
            return formatted(
                "cashflow.budget.hero.overflow.expense",
                defaultValue: "Category limits exceed the total by %@ %@",
                amount,
                currencyCode
            )
        case .income:
            return formatted(
                "cashflow.budget.hero.overflow.income",
                defaultValue: "Category targets exceed the total by %@ %@",
                amount,
                currencyCode
            )
        }
    }

    static func status(_ status: BudgetStatus) -> String {
        switch status {
        case .normal:
            return tr("cashflow.budget.status.normal")
        case .warning:
            return tr("cashflow.budget.status.warning")
        case .critical:
            return tr("cashflow.budget.status.critical")
        case .exceeded:
            return tr("cashflow.budget.status.exceeded")
        }
    }

    static func planButtonTitle(for kind: CashflowCategoryTransactionSheetKind, hasBudget: Bool) -> String {
        switch (kind, hasBudget) {
        case (.expense, false):
            return tr("cashflow.budget.plan_button.add_limits")
        case (.expense, true):
            return tr("cashflow.budget.plan_button.limits")
        case (.income, _):
            return tr("cashflow.budget.plan_button.income")
        }
    }

    static func categoryBadgeText(for status: BudgetStatus) -> String? {
        switch status {
        case .warning, .critical:
            return tr("cashflow.budget.badge.near")
        case .exceeded:
            return tr("cashflow.budget.badge.over")
        case .normal:
            return nil
        }
    }

    static func monthlyStatus(for kind: CashflowCategoryTransactionSheetKind, remaining: Double, currency: String) -> String {
        let amount = formattedNumber(remaining)
        let absoluteAmount = formattedNumber(abs(remaining))

        switch kind {
        case .expense:
            if remaining >= 0 {
                return formatted(
                    "cashflow.budget.monthly_status.expense.remaining",
                    defaultValue: "%@ %@ remaining",
                    amount,
                    currency
                )
            }
            return formatted(
                "cashflow.budget.monthly_status.expense.exceeded",
                defaultValue: "Over by %@ %@",
                absoluteAmount,
                currency
            )
        case .income:
            if remaining <= 0.0000001 {
                return tr("cashflow.budget.monthly_status.income.reached")
            }
            return formatted(
                "cashflow.budget.monthly_status.income.remaining",
                defaultValue: "%@ %@ left in plan",
                amount,
                currency
            )
        }
    }

    static func monthlyUsage(for kind: CashflowCategoryTransactionSheetKind, percent: Int) -> String {
        switch kind {
        case .expense:
            return formatted(
                "cashflow.budget.monthly_usage.expense",
                defaultValue: "%d%% of monthly limit",
                percent
            )
        case .income:
            return formatted(
                "cashflow.budget.monthly_usage.income",
                defaultValue: "%d%% of income plan",
                percent
            )
        }
    }

    private static func formatted(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        String(
            format: tr(key, fallback: defaultValue),
            locale: AppLocalization.currentAppLocale,
            arguments: arguments
        )
    }

    private static func formattedNumber(_ value: Double) -> String {
        cashflowAmountText(value)
    }
}
