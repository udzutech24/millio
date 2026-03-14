//
//  SmartDataResetLocalization.swift
//  millio
//

import Foundation

enum SmartDataResetL10n {
    static func text(locale: Locale, ru: String, en: String) -> String {
        let languageCode = locale.identifier
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased() ?? ""
        return languageCode == "ru" ? ru : en
    }

    static func navigationTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Умный сброс", en: "Smart reset")
    }

    static func confirmResetTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Подтвердите сброс", en: "Confirm reset")
    }

    static func confirmResetMessage(locale: Locale) -> String {
        text(
            locale: locale,
            ru: "Это действие нельзя отменить\nРекомендуется сначала создать резервную копию",
            en: "This action cannot be undone. Creating a backup first is recommended."
        )
    }

    static func resetCompleteTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Сброс завершён", en: "Reset complete")
    }

    static func failedResetTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Не удалось сбросить данные", en: "Failed to reset data")
    }

    static func warningTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Важно", en: "Important")
    }

    static func warningBody(locale: Locale) -> String {
        text(
            locale: locale,
            ru: "Период применяется к операциям, операциям по счетам, обнулению баланса и кешбэку. Он не используется при удалении счетов, категорий или настроек.",
            en: "Period is applied to operations, account operations, balance zeroing, and cashback. It is not used when deleting accounts, categories, or settings."
        )
    }

    static func periodSectionTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Период", en: "Period")
    }

    static func periodPickerTitle(locale: Locale) -> String {
        periodSectionTitle(locale: locale)
    }

    static func periodFrom(locale: Locale) -> String {
        text(locale: locale, ru: "С", en: "From")
    }

    static func periodTo(locale: Locale) -> String {
        text(locale: locale, ru: "По", en: "To")
    }

    static func targetsSectionTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Что удалить", en: "What to delete")
    }

    static func fullResetTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Полный сброс (все типы данных)", en: "Full reset (all data types)")
    }

    static func previewSectionTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Предпросмотр", en: "Preview")
    }

    static func totalChangesTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Всего изменений", en: "Total changes")
    }

    static func backupRecommendation(locale: Locale) -> String {
        text(
            locale: locale,
            ru: "Рекомендуется создать резервную копию перед применением сброса",
            en: "Recommended: create a backup before applying reset."
        )
    }

    static func applyResetButton(isApplying: Bool, locale: Locale) -> String {
        if isApplying {
            return text(locale: locale, ru: "Сброс...", en: "Resetting...")
        }
        return text(locale: locale, ru: "Применить сброс", en: "Apply reset")
    }

    static func ok(locale: Locale) -> String {
        text(locale: locale, ru: "ОК", en: "OK")
    }

    static func cancel(locale: Locale) -> String {
        text(locale: locale, ru: "Отмена", en: "Cancel")
    }

    static func deleteSelectedData(locale: Locale) -> String {
        text(locale: locale, ru: "Удалить выбранные данные", en: "Delete selected data")
    }

    static func appliedChangesMessage(_ count: Int, locale: Locale) -> String {
        text(locale: locale, ru: "Применено изменений: \(count)", en: "Applied changes: \(count)")
    }

    static func periodTitle(_ preset: DataResetPeriodPreset, locale: Locale) -> String {
        switch preset {
        case .allTime:
            return text(locale: locale, ru: "За всё время", en: "All time")
        case .last30Days:
            return text(locale: locale, ru: "Последние 30 дней", en: "Last 30 days")
        case .last90Days:
            return text(locale: locale, ru: "Последние 90 дней", en: "Last 90 days")
        case .last365Days:
            return text(locale: locale, ru: "Последние 365 дней", en: "Last 365 days")
        case .custom:
            return text(locale: locale, ru: "Произвольный диапазон", en: "Custom range")
        }
    }

    static func targetTitle(_ target: DataResetTarget, locale: Locale) -> String {
        switch target {
        case .operations:
            return text(locale: locale, ru: "Операции", en: "Operations")
        case .accountOperations:
            return text(locale: locale, ru: "Операции по счетам", en: "Account operations")
        case .zeroAccountsInPeriod:
            return text(locale: locale, ru: "Обнуление баланса в периоде", en: "Zero balances in period")
        case .cashback:
            return text(locale: locale, ru: "Кешбэк", en: "Cashback")
        case .accounts:
            return text(locale: locale, ru: "Счета", en: "Accounts")
        case .categories:
            return text(locale: locale, ru: "Категории", en: "Categories")
        case .settings:
            return text(locale: locale, ru: "Настройки", en: "Settings")
        }
    }

    static func estimateLabelTransactions(locale: Locale) -> String {
        text(locale: locale, ru: "Операции", en: "Operations")
    }

    static func estimateLabelCashback(locale: Locale) -> String {
        text(locale: locale, ru: "Кешбэк", en: "Cashback")
    }

    static func estimateLabelCards(locale: Locale) -> String {
        text(locale: locale, ru: "Карты", en: "Cards")
    }

    static func estimateLabelCredits(locale: Locale) -> String {
        text(locale: locale, ru: "Кредиты", en: "Credits")
    }

    static func estimateLabelInvestments(locale: Locale) -> String {
        text(locale: locale, ru: "Инвестиции", en: "Investments")
    }

    static func estimateLabelAccountLinks(locale: Locale) -> String {
        text(locale: locale, ru: "Связи счетов", en: "Account links")
    }

    static func estimateLabelAccountGroups(locale: Locale) -> String {
        text(locale: locale, ru: "Группы счетов", en: "Account groups")
    }

    static func estimateLabelCashflowCustomCategories(locale: Locale) -> String {
        text(locale: locale, ru: "Пользовательские категории Кэшфлоу", en: "Custom cashflow categories")
    }

    static func estimateLabelCashflowSystemOverrides(locale: Locale) -> String {
        text(locale: locale, ru: "Переопределения системных категорий", en: "System category overrides")
    }

    static func estimateLabelCashbackCustomCategories(locale: Locale) -> String {
        text(locale: locale, ru: "Пользовательские категории кешбэка", en: "Custom cashback categories")
    }

    static func estimateLabelZeroedCards(locale: Locale) -> String {
        text(locale: locale, ru: "Обнулённые карты", en: "Zeroed cards")
    }

    static func estimateLabelZeroedCredits(locale: Locale) -> String {
        text(locale: locale, ru: "Обнулённые кредиты", en: "Zeroed credits")
    }

    static func estimateLabelZeroedInvestments(locale: Locale) -> String {
        text(locale: locale, ru: "Обнулённые инвестиции", en: "Zeroed investments")
    }

    static func estimateLabelCreatedAdjustments(locale: Locale) -> String {
        text(locale: locale, ru: "Созданные корректировки", en: "Created adjustments")
    }

    static func estimateLabelSettingsReset(locale: Locale) -> String {
        text(locale: locale, ru: "Сброс настроек", en: "Settings reset")
    }
}
