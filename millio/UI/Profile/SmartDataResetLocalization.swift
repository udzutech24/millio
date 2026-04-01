//
//  SmartDataResetLocalization.swift
//  millio
//

import Foundation

enum SmartDataResetL10n {
    static func text(locale: Locale, ru: String, en: String, zhHans: String) -> String {
        switch LocalizationSupport.effectiveLanguage(for: locale) {
        case Language.russian.rawValue:
            return ru
        case Language.simplifiedChinese.rawValue:
            return zhHans
        default:
            return en
        }
    }

    static func navigationTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Умный сброс", en: "Smart reset", zhHans: "智能重置")
    }

    static func confirmResetTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Подтвердите сброс", en: "Confirm reset", zhHans: "确认重置")
    }

    static func confirmResetMessage(locale: Locale) -> String {
        text(
            locale: locale,
            ru: "Это действие нельзя отменить\nРекомендуется сначала создать резервную копию",
            en: "This action cannot be undone. Creating a backup first is recommended.",
            zhHans: "此操作无法撤销\n建议先创建备份"
        )
    }

    static func resetCompleteTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Сброс завершён", en: "Reset complete", zhHans: "重置完成")
    }

    static func failedResetTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Не удалось сбросить данные", en: "Failed to reset data", zhHans: "无法重置数据")
    }

    static func warningTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Важно", en: "Important", zhHans: "重要")
    }

    static func warningBody(locale: Locale) -> String {
        text(
            locale: locale,
            ru: "Период применяется к операциям, операциям по счетам, обнулению баланса и кешбэку. Он не используется при удалении счетов, категорий или настроек.",
            en: "Period is applied to operations, account operations, balance zeroing, and cashback. It is not used when deleting accounts, categories, or settings.",
            zhHans: "时间范围适用于交易、账户操作、余额归零和返现，不用于删除账户、分类或设置。"
        )
    }

    static func periodSectionTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Период", en: "Period", zhHans: "时间范围")
    }

    static func periodPickerTitle(locale: Locale) -> String {
        periodSectionTitle(locale: locale)
    }

    static func periodFrom(locale: Locale) -> String {
        text(locale: locale, ru: "С", en: "From", zhHans: "从")
    }

    static func periodTo(locale: Locale) -> String {
        text(locale: locale, ru: "По", en: "To", zhHans: "到")
    }

    static func targetsSectionTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Что удалить", en: "What to delete", zhHans: "删除内容")
    }

    static func fullResetTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Полный сброс (все типы данных)", en: "Full reset (all data types)", zhHans: "完全重置（所有数据类型）")
    }

    static func previewSectionTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Предпросмотр", en: "Preview", zhHans: "预览")
    }

    static func totalChangesTitle(locale: Locale) -> String {
        text(locale: locale, ru: "Всего изменений", en: "Total changes", zhHans: "总变更数")
    }

    static func backupRecommendation(locale: Locale) -> String {
        text(
            locale: locale,
            ru: "Рекомендуется создать резервную копию перед применением сброса",
            en: "Recommended: create a backup before applying reset.",
            zhHans: "建议在执行重置前先创建备份"
        )
    }

    static func applyResetButton(isApplying: Bool, locale: Locale) -> String {
        if isApplying {
            return text(locale: locale, ru: "Сброс...", en: "Resetting...", zhHans: "重置中...")
        }
        return text(locale: locale, ru: "Применить сброс", en: "Apply reset", zhHans: "应用重置")
    }

    static func ok(locale: Locale) -> String {
        text(locale: locale, ru: "ОК", en: "OK", zhHans: "确定")
    }

    static func cancel(locale: Locale) -> String {
        text(locale: locale, ru: "Отмена", en: "Cancel", zhHans: "取消")
    }

    static func deleteSelectedData(locale: Locale) -> String {
        text(locale: locale, ru: "Удалить выбранные данные", en: "Delete selected data", zhHans: "删除所选数据")
    }

    static func appliedChangesMessage(_ count: Int, locale: Locale) -> String {
        text(locale: locale, ru: "Применено изменений: \(count)", en: "Applied changes: \(count)", zhHans: "已应用变更：\(count)")
    }

    static func periodTitle(_ preset: DataResetPeriodPreset, locale: Locale) -> String {
        switch preset {
        case .allTime:
            return text(locale: locale, ru: "За всё время", en: "All time", zhHans: "所有时间")
        case .last30Days:
            return text(locale: locale, ru: "Последние 30 дней", en: "Last 30 days", zhHans: "最近 30 天")
        case .last90Days:
            return text(locale: locale, ru: "Последние 90 дней", en: "Last 90 days", zhHans: "最近 90 天")
        case .last365Days:
            return text(locale: locale, ru: "Последние 365 дней", en: "Last 365 days", zhHans: "最近 365 天")
        case .custom:
            return text(locale: locale, ru: "Произвольный диапазон", en: "Custom range", zhHans: "自定义范围")
        }
    }

    static func targetTitle(_ target: DataResetTarget, locale: Locale) -> String {
        switch target {
        case .operations:
            return text(locale: locale, ru: "Операции", en: "Operations", zhHans: "交易")
        case .accountOperations:
            return text(locale: locale, ru: "Операции по счетам", en: "Account operations", zhHans: "账户操作")
        case .zeroAccountsInPeriod:
            return text(locale: locale, ru: "Обнуление баланса в периоде", en: "Zero balances in period", zhHans: "区间内余额归零")
        case .cashback:
            return text(locale: locale, ru: "Кешбэк", en: "Cashback", zhHans: "返现")
        case .accounts:
            return text(locale: locale, ru: "Счета", en: "Accounts", zhHans: "账户")
        case .categories:
            return text(locale: locale, ru: "Категории", en: "Categories", zhHans: "分类")
        case .settings:
            return text(locale: locale, ru: "Настройки", en: "Settings", zhHans: "设置")
        }
    }

    static func estimateLabelTransactions(locale: Locale) -> String {
        text(locale: locale, ru: "Операции", en: "Operations", zhHans: "交易")
    }

    static func estimateLabelCashback(locale: Locale) -> String {
        text(locale: locale, ru: "Кешбэк", en: "Cashback", zhHans: "返现")
    }

    static func estimateLabelCards(locale: Locale) -> String {
        text(locale: locale, ru: "Карты", en: "Cards", zhHans: "卡片")
    }

    static func estimateLabelCredits(locale: Locale) -> String {
        text(locale: locale, ru: "Кредиты", en: "Credits", zhHans: "贷款")
    }

    static func estimateLabelInvestments(locale: Locale) -> String {
        text(locale: locale, ru: "Инвестиции", en: "Investments", zhHans: "投资")
    }

    static func estimateLabelAccountLinks(locale: Locale) -> String {
        text(locale: locale, ru: "Связи счетов", en: "Account links", zhHans: "账户关联")
    }

    static func estimateLabelAccountGroups(locale: Locale) -> String {
        text(locale: locale, ru: "Группы счетов", en: "Account groups", zhHans: "账户分组")
    }

    static func estimateLabelCashflowCustomCategories(locale: Locale) -> String {
        text(locale: locale, ru: "Пользовательские категории Кэшфлоу", en: "Custom cashflow categories", zhHans: "自定义现金流分类")
    }

    static func estimateLabelCashflowSystemOverrides(locale: Locale) -> String {
        text(locale: locale, ru: "Переопределения системных категорий", en: "System category overrides", zhHans: "系统分类覆盖")
    }

    static func estimateLabelCashbackCustomCategories(locale: Locale) -> String {
        text(locale: locale, ru: "Пользовательские категории кешбэка", en: "Custom cashback categories", zhHans: "自定义返现分类")
    }

    static func estimateLabelZeroedCards(locale: Locale) -> String {
        text(locale: locale, ru: "Обнулённые карты", en: "Zeroed cards", zhHans: "已归零卡片")
    }

    static func estimateLabelZeroedCredits(locale: Locale) -> String {
        text(locale: locale, ru: "Обнулённые кредиты", en: "Zeroed credits", zhHans: "已归零贷款")
    }

    static func estimateLabelZeroedInvestments(locale: Locale) -> String {
        text(locale: locale, ru: "Обнулённые инвестиции", en: "Zeroed investments", zhHans: "已归零投资")
    }

    static func estimateLabelCreatedAdjustments(locale: Locale) -> String {
        text(locale: locale, ru: "Созданные корректировки", en: "Created adjustments", zhHans: "已创建调整")
    }

    static func estimateLabelSettingsReset(locale: Locale) -> String {
        text(locale: locale, ru: "Сброс настроек", en: "Settings reset", zhHans: "设置重置")
    }
}
