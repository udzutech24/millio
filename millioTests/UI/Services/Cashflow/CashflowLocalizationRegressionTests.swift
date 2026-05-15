//
//  CashflowLocalizationRegressionTests.swift
//  millioTests
//
//  Created by Codex on 09.03.2026.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
struct CashflowLocalizationRegressionTests {
    @Test("Hidden system override keeps category localized after app language switch")
    @MainActor
    func hiddenSystemOverrideUsesCurrentAppLanguage() throws {
        try AppLanguageTestSupport.withLockedAppLanguage {
            let previousLanguage = LanguageManager.shared.currentLanguage
            defer { LanguageManager.shared.setLanguage(previousLanguage) }

            let schema = Schema([
                CashflowTransaction.self,
                CashflowCustomCategory.self,
                CashflowSystemCategoryOverride.self,
                Card.self,
                FinanceGroup.self,
                FinanceAccount.self,
                HistoricalRate.self
            ])
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
            let context = container.mainContext

            LanguageManager.shared.setLanguage(.russian)
            let baseRussianName = ExpenseCategory.groceries.displayName
            let override = CashflowSystemCategoryOverride(
                kind: .expense,
                categoryRaw: ExpenseCategory.groceries.rawValue,
                name: baseRussianName,
                icon: ExpenseCategory.groceries.icon,
                isHidden: true
            )
            context.insert(override)
            try context.save()

            let viewModel = CashflowViewModel(modelContext: context)

            LanguageManager.shared.setLanguage(.english)
            let option = viewModel.categoryOption(for: ExpenseCategory.groceries.rawValue, kind: .expense)

            #expect(baseRussianName == "Продукты")
            #expect(option.displayName == "Groceries")
        }
    }

    @Test("Legacy Russian system override names are treated as system names after language switch")
    @MainActor
    func legacyRussianSystemOverrideNamesAreLocalized() throws {
        try AppLanguageTestSupport.withLockedAppLanguage {
            let previousLanguage = LanguageManager.shared.currentLanguage
            defer { LanguageManager.shared.setLanguage(previousLanguage) }

            let schema = Schema([
                CashflowTransaction.self,
                CashflowCustomCategory.self,
                CashflowSystemCategoryOverride.self,
                Card.self,
                FinanceGroup.self,
                FinanceAccount.self,
                HistoricalRate.self
            ])
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
            let context = container.mainContext

            LanguageManager.shared.setLanguage(.russian)

            let legacyServiceOverride = CashflowSystemCategoryOverride(
                kind: .expense,
                categoryRaw: ExpenseCategory.carService.rawValue,
                name: "Сервис",
                icon: ExpenseCategory.carService.icon,
                isHidden: true
            )
            let legacyGroceriesOverride = CashflowSystemCategoryOverride(
                kind: .expense,
                categoryRaw: ExpenseCategory.groceries.rawValue,
                name: "Супермаркеты",
                icon: ExpenseCategory.groceries.icon,
                isHidden: true
            )
            let legacyUtilitiesOverride = CashflowSystemCategoryOverride(
                kind: .expense,
                categoryRaw: ExpenseCategory.utilities.rawValue,
                name: "ЖКХ и коммунальные",
                icon: ExpenseCategory.utilities.icon,
                isHidden: true
            )
            context.insert(legacyServiceOverride)
            context.insert(legacyGroceriesOverride)
            context.insert(legacyUtilitiesOverride)
            try context.save()

            let viewModel = CashflowViewModel(modelContext: context)

            LanguageManager.shared.setLanguage(.english)

            let groceries = viewModel.categoryOption(for: ExpenseCategory.groceries.rawValue, kind: .expense)
            let service = viewModel.categoryOption(for: ExpenseCategory.carService.rawValue, kind: .expense)
            let utilities = viewModel.categoryOption(for: ExpenseCategory.utilities.rawValue, kind: .expense)

            #expect(groceries.displayName == "Groceries")
            #expect(service.displayName == "Car service")
            #expect(utilities.displayName == "Utilities")
        }
    }

    @Test("Russian locale contains localized Cashflow labels")
    func russianLocaleHasCashflowTranslations() {
        let locale = Locale(identifier: "ru_RU")

        #expect(AppLocalization.string("cashflow.stats.assets_start", locale: locale) == "Активы на начало периода")
        #expect(AppLocalization.string("cashflow.stats.assets_end", locale: locale) == "Активы на конец периода")
        #expect(AppLocalization.string("cashflow.stats.income", locale: locale) == "Доходы")
        #expect(AppLocalization.string("cashflow.stats.expenses", locale: locale) == "Расходы")
        #expect(AppLocalization.string("cashflow.stats.asset_value_change", locale: locale) == "Изменение стоимости активов")
        #expect(AppLocalization.string("cashflow.stats.result", locale: locale) == "Результат")
        #expect(AppLocalization.string("cashflow.quick_action.transfer", locale: locale) == "Перевод")
        #expect(AppLocalization.string("cashflow.operation.new_transfer", locale: locale) == "Новый перевод")
        #expect(AppLocalization.string("cashflow.chart.expand", locale: locale) == "Развернуть график")
        #expect(AppLocalization.string("cashflow.chart.title", locale: locale) == "Доходы и расходы")
        #expect(AppLocalization.string("cashflow.chart.empty", locale: locale) == "Нет данных для графика")
        #expect(AppLocalization.string("cashflow.chart.empty.banner.title", locale: locale) == "Пульс кэшфлоу")
        #expect(AppLocalization.string("cashflow.chart.empty.banner.subtitle", locale: locale) == "Когда в выбранном периоде появятся доходы и расходы, здесь появится динамика, начните с первой операции")
        #expect(AppLocalization.string("cashflow.chart.empty.banner.add_action", locale: locale) == "Добавить операцию")
        #expect(AppLocalization.string("cashflow.chart.empty.banner.open_finances", locale: locale) == "Добавить счёт")
        #expect(AppLocalization.string("cashflow.chart.visible_range", locale: locale) == "Диапазон")
        #expect(AppLocalization.string("cashflow.chart.hint_format", locale: locale).contains("Диапазон"))
        #expect(AppLocalization.string("cashflow.asset_change.balance_check", locale: locale) == "Сверка баланса")
        #expect(AppLocalization.string("cashflow.asset_change.matches", locale: locale) == "Баланс сходится")
        #expect(AppLocalization.string("cashflow.asset_change.mismatch", locale: locale) == "Есть расхождение")
        #expect(AppLocalization.string("cashflow.asset_change.substitution", locale: locale) == "Расчёт")
        #expect(AppLocalization.string("cashflow.period_selector.title", locale: locale) == "Выбор периода")
        #expect(AppLocalization.string("cashflow.editor.transaction_type", locale: locale) == "Тип операции")
        #expect(AppLocalization.string("cashflow.operation.total", locale: locale) == "Итого")
        #expect(AppLocalization.string("cashflow.scheduled.monthly_badge", locale: locale) == "Ежемесячно")
        #expect(AppLocalization.string("cashflow.scheduled.section.recurring", locale: locale) == "Регулярно")
        #expect(AppLocalization.string("cashflow.scheduled.planner_expenses", locale: locale) == "Планировщик платежей")
        #expect(AppLocalization.string("cashflow.scheduled.display.calendar", locale: locale) == "Календарь")
        #expect(AppLocalization.string("cashflow.scheduled.display.list", locale: locale) == "Список")
        #expect(AppLocalization.string("cashflow.scheduled.create_picker.title", locale: locale) == "Что добавить?")
        #expect(AppLocalization.string("cashflow.scheduled.create_picker.monthly", locale: locale) == "Ежемесячно")
        #expect(AppLocalization.string("cashflow.scheduled.create_picker.one_time", locale: locale) == "Разово")
        #expect(AppLocalization.string("cashflow.scheduled.day_agenda.empty.add_here", locale: locale) == "Добавить")
        #expect(AppLocalization.string("cashflow.editor.category_sheet.title.expense", locale: locale) == "Категории расходов")
        #expect(AppLocalization.string("cashflow.editor.category_sheet.create.expense", locale: locale) == "Создать категорию расходов")
        #expect(AppLocalization.string("cashflow.category.settings.title", locale: locale) == "Настройки категорий")
        #expect(AppLocalization.string("cashflow.category.actions.message", locale: locale) == "Выбери действие для этой категории.")
        #expect(AppLocalization.string("cashflow.category.actions.delete", locale: locale) == "Удалить")
        #expect(AppLocalization.string("cashflow.category.visibility.visible", locale: locale) == "Показывается в списке")
        #expect(AppLocalization.string("cashflow.category.visibility.hidden", locale: locale) == "Скрыта из списка")
        #expect(AppLocalization.string("cashflow.category.visibility.always", locale: locale) == "Всегда отображается")
        #expect(AppLocalization.string("cashflow.editor.account", locale: locale) == "Счет")
        #expect(AppLocalization.string("cashflow.editor.affect_balance.subtitle.expense", locale: locale) == "Выключи, если текущий остаток уже верный и нужно только дозанести траты за выбранный период в историю")
        #expect(AppLocalization.string("cashflow.recurrence.quarterly", locale: locale) == "Каждые 3 месяца")
        #expect(AppLocalization.string("cashflow.recurrence.semiannual", locale: locale) == "Каждые 6 месяцев")
        #expect(AppLocalization.string("cashflow.recurrence.yearly", locale: locale) == "Каждый год")
        #expect(AppLocalization.string("cashflow.main.empty_intro.description", locale: locale) == "Здесь видно, откуда приходят деньги и куда уходят. Добавьте первую операцию, чтобы начать.")

        #expect(AppLocalization.string("Income", locale: locale) == "Доход")
        #expect(AppLocalization.string("Expense", locale: locale) == "Расход")
        #expect(AppLocalization.string("Salary", locale: locale) == "Зарплата")
        #expect(AppLocalization.string("Groceries", locale: locale) == "Продукты")
        #expect(AppLocalization.string("Transfer", locale: locale) == "Перевод")
        #expect(AppLocalization.string("Do not repeat", locale: locale) == "Не повторять")
        #expect(AppLocalization.string("Salary", locale: locale) == "Зарплата")
        #expect(AppLocalization.string("Groceries", locale: locale) == "Продукты")
        #expect(AppLocalization.string("New income", locale: locale) == "Добавить доход")
        #expect(AppLocalization.string("New expense", locale: locale) == "Новый расход")
        #expect(AppLocalization.string("Recurring income", locale: locale) == "Регулярный доход")
        #expect(AppLocalization.string("Recurring expenses", locale: locale) == "Регулярные расходы")
        #expect(AppLocalization.string("Planned income", locale: locale) == "Запланированный доход")
        #expect(AppLocalization.string("Planned expenses", locale: locale) == "Запланированные расходы")
        #expect(AppLocalization.string("Add recurring expense", locale: locale) == "Добавить регулярный расход")
        #expect(AppLocalization.string("Total income for month", locale: locale) == "Доходы за месяц")
        #expect(AppLocalization.string("cashflow.history.filter.income", locale: locale) == "Доходы")
        #expect(AppLocalization.string("Total expense for month", locale: locale) == "Расход за месяц")
        #expect(AppLocalization.string("Uncategorized", locale: locale) == "Без категории")
        #expect(AppLocalization.string("Asset value adjustment", locale: locale) == "Корректировка стоимости активов")
        #expect(AppLocalization.string("Account balance adjustment", locale: locale) == "Корректировка баланса счета")
        #expect(AppLocalization.string("Debt adjustment", locale: locale) == "Корректировка долга")
        #expect(AppLocalization.string("Hide hints", locale: locale) == "Скрыть подсказки")
        #expect(AppLocalization.string("Add card in Finances", locale: locale) == "Добавить карту в Финансах")
        #expect(AppLocalization.string("Result", locale: locale) == "Результат")
        #expect(AppLocalization.string("Week", locale: locale) == "Неделя")
        #expect(AppLocalization.string("Visible range", locale: locale) == "Диапазон")
    }

    @Test("English locale contains new compact cashflow helper copy")
    func englishLocaleHasNewCashflowHelperTranslations() {
        let locale = Locale(identifier: "en_US")

        #expect(AppLocalization.string("cashflow.editor.account", locale: locale) == "Account")
        #expect(AppLocalization.string("cashflow.operation.new_transfer", locale: locale) == "New transfer")
        #expect(AppLocalization.string("cashflow.chart.title", locale: locale) == "Income and Expenses")
        #expect(AppLocalization.string("cashflow.chart.empty", locale: locale) == "No data for the chart yet")
        #expect(AppLocalization.string("cashflow.chart.hint_format", locale: locale).contains("Range"))
        #expect(AppLocalization.string("cashflow.chart.empty.banner.title", locale: locale) == "Cashflow pulse")
        #expect(AppLocalization.string("cashflow.chart.empty.banner.subtitle", locale: locale) == "When income and expenses appear in the selected period, a trend chart will show up here, start with your first transaction")
        #expect(AppLocalization.string("cashflow.chart.empty.banner.add_action", locale: locale) == "Add transaction")
        #expect(AppLocalization.string("cashflow.chart.empty.banner.open_finances", locale: locale) == "Add account")
        #expect(AppLocalization.string("cashflow.stats.income", locale: locale) == "Income")
        #expect(AppLocalization.string("cashflow.category.actions.message", locale: locale) == "Choose an action for this category.")
        #expect(AppLocalization.string("cashflow.category.actions.delete", locale: locale) == "Delete")
        #expect(AppLocalization.string("cashflow.category.visibility.visible", locale: locale) == "Visible in list")
        #expect(AppLocalization.string("cashflow.editor.affect_balance.subtitle.expense", locale: locale) == "Turn off if the current balance is already correct and you only need to backfill expense history for the selected period")
        #expect(AppLocalization.string("cashflow.recurrence.quarterly", locale: locale) == "Every 3 months")
        #expect(AppLocalization.string("cashflow.recurrence.semiannual", locale: locale) == "Every 6 months")
        #expect(AppLocalization.string("cashflow.recurrence.yearly", locale: locale) == "Every year")
        #expect(AppLocalization.string("cashflow.main.empty_intro.description", locale: locale) == "Here you can see where money comes from and where it goes. Add your first transaction to get started.")
        #expect(AppLocalization.string("cashflow.scheduled.day_agenda.summary.empty", locale: locale) == "You can add another planned item directly to this date.")
        #expect(AppLocalization.string("cashflow.asset_change.balance_check", locale: locale) == "Balance check")
        #expect(AppLocalization.string("Salary", locale: locale) == "Salary")
        #expect(AppLocalization.string("Groceries", locale: locale) == "Groceries")
    }

    @Test("Simplified Chinese locale contains release critical Cashflow labels")
    func simplifiedChineseLocaleHasCriticalCashflowTranslations() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(AppLocalization.string("cashflow.accessibility.back", locale: locale) == "返回")
        #expect(AppLocalization.string("cashflow.accessibility.hide_details", locale: locale) == "隐藏详情")
        #expect(AppLocalization.string("cashflow.accessibility.quick_navigation", locale: locale) == "迷你应用快捷导航")
        #expect(AppLocalization.string("cashflow.accessibility.select_period", locale: locale) == "选择周期")
        #expect(AppLocalization.string("cashflow.accessibility.show_details", locale: locale) == "显示详情")
        #expect(AppLocalization.string("cashflow.accessibility.transaction_history", locale: locale) == "交易历史")
        #expect(AppLocalization.string("cashflow.chart.expand", locale: locale) == "展开图表")
        #expect(AppLocalization.string("cashflow.chart.pro.title", locale: locale) == "PRO 可用")
        #expect(AppLocalization.string("cashflow.chart.pro.subtitle", locale: locale) == "升级以解锁现金流趋势")
        #expect(AppLocalization.string("cashflow.common.done", locale: locale) == "完成")
        #expect(AppLocalization.string("cashflow.history.empty.default", locale: locale) == "添加第一笔交易")
        #expect(AppLocalization.string("cashflow.history.empty.title", locale: locale) == "暂无交易")
        #expect(AppLocalization.string("cashflow.history.detail.changes", locale: locale) == "发生了什么变化")
        #expect(AppLocalization.string("cashflow.history.filter.all", locale: locale) == "全部")
        #expect(AppLocalization.string("cashflow.history.cards", locale: locale) == "账户和卡片")
        #expect(AppLocalization.string("cashflow.history.cards.all", locale: locale) == "所有账户和卡片")
        #expect(AppLocalization.string("cashflow.history.title", locale: locale) == "交易记录")
        #expect(AppLocalization.string("cashflow.history.asset_change.quantity", locale: locale) == "数量")
        #expect(AppLocalization.string("cashflow.history.asset_change.price", locale: locale) == "价格")
        #expect(AppLocalization.string("cashflow.history.asset_change.value", locale: locale) == "价值")
        #expect(AppLocalization.string("cashflow.period.range_format", locale: locale) == "%1$@ — %2$@")
        #expect(AppLocalization.string("cashflow.scheduled.day_agenda.empty.add_here", locale: locale) == "添加")
        #expect(AppLocalization.string("cashflow.scheduled.delete_transaction.message", locale: locale) == "该交易将被永久删除。")
        #expect(AppLocalization.string("cashflow.scheduled.delete_transaction.title", locale: locale) == "删除交易？")
        #expect(AppLocalization.string("cashflow.scheduled.overview.empty", locale: locale) == "暂时没有即将到来的计划交易。")
        #expect(AppLocalization.string("cashflow.scheduled.overview.next", locale: locale) == "下一笔")
        #expect(AppLocalization.string("cashflow.scheduled.overview.one_time_prefix", locale: locale) == "单次")
        #expect(AppLocalization.string("cashflow.scheduled.overview.title.expense", locale: locale) == "付款计划")
        #expect(AppLocalization.string("cashflow.scheduled.overview.title.income", locale: locale) == "收入计划")
        #expect(AppLocalization.string("cashflow.scheduled.planner_expenses", locale: locale) == "付款计划")
        #expect(AppLocalization.string("cashflow.scheduled.planner_income", locale: locale) == "收入计划")
        #expect(AppLocalization.string("cashflow.scheduled.display.calendar", locale: locale) == "日历")
        #expect(AppLocalization.string("cashflow.scheduled.display.list", locale: locale) == "列表")
        #expect(AppLocalization.string("cashflow.scheduled.section.one_time", locale: locale) == "单次计划")
        #expect(AppLocalization.string("cashflow.scheduled.section.recurring", locale: locale) == "定期")
        #expect(AppLocalization.string("cashflow.scheduled.search_transaction", locale: locale) == "搜索交易")
        #expect(AppLocalization.string("cashflow.operation.search_category", locale: locale) == "搜索分类")
        #expect(AppLocalization.string("cashflow.operation.new_income", locale: locale) == "添加收入")
        #expect(AppLocalization.string("cashflow.operation.new_transfer", locale: locale) == "新建转账")
        #expect(AppLocalization.string("cashflow.editor.section.selected_income", locale: locale) == "已选收入")
        #expect(AppLocalization.string("cashflow.editor.section.main_info", locale: locale) == "主要信息")
        #expect(AppLocalization.string("cashflow.editor.amount", locale: locale) == "金额")
        #expect(AppLocalization.string("cashflow.editor.currency", locale: locale) == "货币")
        #expect(AppLocalization.string("cashflow.editor.account", locale: locale) == "账户")
        #expect(AppLocalization.string("cashflow.editor.card", locale: locale) == "卡片")
        #expect(AppLocalization.string("cashflow.editor.select_account", locale: locale) == "选择账户")
        #expect(AppLocalization.string("cashflow.editor.select_card", locale: locale) == "选择卡片")
        #expect(AppLocalization.string("cashflow.editor.from_card", locale: locale) == "转出卡")
        #expect(AppLocalization.string("cashflow.editor.to_card", locale: locale) == "转入卡")
        #expect(AppLocalization.string("cashflow.editor.no_available_cards", locale: locale) == "没有可用卡片")
        #expect(AppLocalization.string("cashflow.editor.no_cards_in_currency", locale: locale) == "所选货币下没有可用卡片")
        #expect(AppLocalization.string("cashflow.editor.add_card_in_finances", locale: locale) == "前往 Finances 添加卡片")
        #expect(AppLocalization.string("cashflow.editor.available_format", locale: locale) == "可用：%@ %@")
        #expect(AppLocalization.string("cashflow.editor.insufficient_funds", locale: locale) == "余额不足")
        #expect(AppLocalization.string("cashflow.editor.date", locale: locale) == "日期")
        #expect(AppLocalization.string("cashflow.editor.frequency", locale: locale) == "频率")
        #expect(AppLocalization.string("cashflow.editor.comment", locale: locale) == "备注")
        #expect(AppLocalization.string("cashflow.editor.affect_balance.subtitle.income", locale: locale) == "如果当前余额已经正确，只需要补录所选期间的收入历史，请关闭此开关")
        #expect(AppLocalization.string("cashflow.editor.affect_balance.subtitle.expense", locale: locale) == "如果当前余额已经正确，只需要补录所选期间的支出历史，请关闭此开关")
        #expect(AppLocalization.string("cashflow.editor.new_category", locale: locale) == "新建分类")
        #expect(AppLocalization.string("cashflow.editor.edit_category", locale: locale) == "编辑分类")
        #expect(AppLocalization.string("cashflow.editor.category_name", locale: locale) == "名称")
        #expect(AppLocalization.string("cashflow.editor.enter_name", locale: locale) == "输入名称")
        #expect(AppLocalization.string("cashflow.editor.category_icon", locale: locale) == "图标")
        #expect(AppLocalization.string("cashflow.editor.icon_suggestions", locale: locale) == "推荐图标")
        #expect(AppLocalization.string("cashflow.common.edit", locale: locale) == "编辑")
        #expect(AppLocalization.string("cashflow.category.actions.archive", locale: locale) == "归档")
        #expect(AppLocalization.string("cashflow.category.actions.delete", locale: locale) == "删除")
        #expect(AppLocalization.string("cashflow.category.actions.message", locale: locale) == "请选择此分类的操作。")
        #expect(AppLocalization.string("cashflow.category.actions.operations", locale: locale) == "操作")
        #expect(AppLocalization.string("cashflow.category.settings.title", locale: locale) == "分类设置")
        #expect(AppLocalization.string("cashflow.category.visibility.always", locale: locale) == "始终显示")
        #expect(AppLocalization.string("cashflow.category.visibility.visible", locale: locale) == "在列表中显示")
        #expect(AppLocalization.string("cashflow.category.visibility.hidden", locale: locale) == "已从列表隐藏")
        #expect(AppLocalization.string("cashflow.common.settings", locale: locale) == "设置")
        #expect(AppLocalization.string("cashflow.editor.icon_tab.emoji", locale: locale) == "表情")
        #expect(AppLocalization.string("cashflow.editor.icon_tab.symbols", locale: locale) == "图标")
        #expect(AppLocalization.string("cashflow.editor.icon_type", locale: locale) == "图标类型")
        #expect(AppLocalization.string("cashflow.editor.icon_search_hint", locale: locale) == "搜索图标（例如：汽车、购物车、爱心）")
        #expect(AppLocalization.string("cashflow.quick_action.transfer", locale: locale) == "转账")
        #expect(AppLocalization.string("cashflow.budget.setup.title.expense", locale: locale) == "预算限额")
        #expect(AppLocalization.string("cashflow.budget.plan_button.add_limits", locale: locale) == "添加限额")
        #expect(AppLocalization.string("cashflow.budget.status.exceeded", locale: locale) == "超支")
        #expect(AppLocalization.string("cashflow.budget.badge.near", locale: locale) == "临近")
        #expect(AppLocalization.string("cashflow.stats.asset_value_change", locale: locale) == "资产重估")
        #expect(AppLocalization.string("cashflow.stats.assets_end", locale: locale) == "期末资产")
        #expect(AppLocalization.string("cashflow.stats.assets_start", locale: locale) == "期初资产")
        #expect(AppLocalization.string("cashflow.stats.expenses", locale: locale) == "支出")
        #expect(AppLocalization.string("cashflow.stats.result", locale: locale) == "结果")
        #expect(AppLocalization.string("cashflow.asset_change.balance_check", locale: locale) == "余额校验")
        #expect(AppLocalization.string("cashflow.asset_change.explanation", locale: locale) == "通常包括重估、市场价格变动或未记为收入或支出的资产变动")
        #expect(AppLocalization.string("cashflow.asset_change.formula", locale: locale) == "变化 = （期末资产 - 期初资产）- 收入 + 支出")
        #expect(AppLocalization.string("cashflow.asset_change.formula_title", locale: locale) == "公式")
        #expect(AppLocalization.string("cashflow.asset_change.info_title", locale: locale) == "资产重估如何计算？")
        #expect(AppLocalization.string("cashflow.asset_change.matches", locale: locale) == "余额一致")
        #expect(AppLocalization.string("cashflow.asset_change.matches_detail", locale: locale) == "本期结果与记录的资产变动一致")
        #expect(AppLocalization.string("cashflow.asset_change.mismatch", locale: locale) == "余额需要关注")
        #expect(AppLocalization.string("cashflow.asset_change.mismatch_detail", locale: locale) == "本期结果与记录的资产变动并不完全一致")
        #expect(AppLocalization.string("cashflow.asset_change.subtitle", locale: locale) == "这是在计入所有已记录收入和支出后，期初与期末之间剩余的差额")
        #expect(AppLocalization.string("cashflow.asset_change.substitution", locale: locale) == "计算")
        #expect(AppLocalization.string("finances.account.type.investment", locale: locale) == "资产")
        #expect(AppLocalization.string("finances.dynamics.pro.cta", locale: locale) == "PRO")
    }

    @Test("Planner helper copy stays localized for both locales")
    func plannerHelperCopyIsLocalizedForBothLocales() {
        let english = Locale(identifier: "en_US")
        let russian = Locale(identifier: "ru_RU")

        #expect(AppLocalization.string("cashflow.scheduled.day_agenda.summary.count", locale: english).contains("scheduled item"))
        #expect(AppLocalization.string("cashflow.scheduled.day_agenda.summary.empty", locale: english) == "You can add another planned item directly to this date.")
        #expect(AppLocalization.string("cashflow.scheduled.day_agenda.summary.count", locale: russian).contains("запланирован"))
        #expect(AppLocalization.string("cashflow.scheduled.day_agenda.summary.empty", locale: russian) == "Можно сразу добавить ещё одну запланированную операцию на эту дату.")
    }

    @Test("Period title uses localized quarter format")
    func quarterTitleUsesLocalizedFormat() async {
        let locale = Locale(identifier: "ru_RU")
        let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
            return calendar
        }()

        let date = DateComponents(calendar: calendar, year: 2026, month: 3, day: 9).date!
        let title = await MainActor.run {
            CashflowViewModel.makePeriodHeaderTitle(
                chartPeriod: .specificQuarter,
                selectedMonth: date,
                selectedQuarter: date,
                selectedYear: date,
                customStartDate: date,
                customEndDate: date,
                calendar: calendar,
                locale: locale
            )
        }

        #expect(title == "1 кв. 2026")
    }

    @Test("Custom period title normalizes start and end dates")
    func customTitleNormalizesStartAndEnd() async {
        let locale = Locale(identifier: "ru_RU")
        let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
            return calendar
        }()

        let later = DateComponents(calendar: calendar, year: 2026, month: 3, day: 9).date!
        let earlier = DateComponents(calendar: calendar, year: 2026, month: 2, day: 7).date!

        let title = await MainActor.run {
            CashflowViewModel.makePeriodHeaderTitle(
                chartPeriod: .custom,
                selectedMonth: later,
                selectedQuarter: later,
                selectedYear: later,
                customStartDate: later,
                customEndDate: earlier,
                calendar: calendar,
                locale: locale
            )
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("dMMM y")
        let expected = "\(formatter.string(from: earlier)) — \(formatter.string(from: later))"

        #expect(title == expected)
    }

    @Test("Simplified Chinese locale contains currency picker and hint strings")
    func simplifiedChineseLocaleHasCurrencyPickerTranslations() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(AppLocalization.string("cashflow.display_currency.title", locale: locale) == "显示货币")
        #expect(AppLocalization.string("cashflow.display_currency.hint_title", locale: locale) == "提示")
        #expect(AppLocalization.string("cashflow.display_currency.hint_message", locale: locale) == "基础货币只能在个人资料中更改。这里的货币只影响显示，并会在离开 Cashflow 后重置。")
        #expect(AppLocalization.string("cashflow.display_currency.hint_accessibility", locale: locale) == "显示货币提示")
        #expect(AppLocalization.string("cashflow.display_currency.hide_hint_accessibility", locale: locale) == "隐藏提示")
        #expect(AppLocalization.string("cashflow.common.cancel", locale: locale) == "取消")
        #expect(AppLocalization.string("cashflow.common.ok", locale: locale) == "确定")
        #expect(AppLocalization.string("cashflow.editor.transaction_currency", locale: locale) == "交易货币")
    }

    @Test("zh-Hans locale contains localized Cashflow generic fallback labels")
    func simplifiedChineseLocaleHasCashflowFallbackTranslations() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(AppLocalization.string("Income", locale: locale) == "收入")
        #expect(AppLocalization.string("Expense", locale: locale) == "支出")
        #expect(AppLocalization.string("Transfer", locale: locale) == "转账")
        #expect(AppLocalization.string("Year", locale: locale) == "年")
        #expect(AppLocalization.string("Month", locale: locale) == "月")
        #expect(AppLocalization.string("Week", locale: locale) == "周")
        #expect(AppLocalization.string("Salary", locale: locale) == "工资")
        #expect(AppLocalization.string("Interest", locale: locale) == "利息")
        #expect(AppLocalization.string("Dividends", locale: locale) == "股息")
        #expect(AppLocalization.string("Refunds", locale: locale) == "退款")
        #expect(AppLocalization.string("Sale", locale: locale) == "出售")
        #expect(AppLocalization.string("Asset value adjustment", locale: locale) == "资产价值调整")
        #expect(AppLocalization.string("Account balance adjustment", locale: locale) == "账户余额调整")
        #expect(AppLocalization.string("Debt adjustment", locale: locale) == "债务调整")
    }

    @Test("Income categories localize via app locale without manual ru en branching")
    func incomeCategoriesUseLocalizedStringsForAllSupportedLanguages() {
        #expect(IncomeCategory.salary.localizedDisplayName(locale: Locale(identifier: "ru_RU")) == "Зарплата")
        #expect(IncomeCategory.salary.localizedDisplayName(locale: Locale(identifier: "en_US")) == "Salary")
        #expect(IncomeCategory.salary.localizedDisplayName(locale: Locale(identifier: "zh-Hans")) == "工资")

        #expect(IncomeCategory.interest.localizedDisplayName(locale: Locale(identifier: "ru_RU")) == "Проценты")
        #expect(IncomeCategory.interest.localizedDisplayName(locale: Locale(identifier: "en_US")) == "Interest")
        #expect(IncomeCategory.interest.localizedDisplayName(locale: Locale(identifier: "zh-Hans")) == "利息")
    }

    @Test("Operation sheet pin and budget helper copy is localized for zh-Hans")
    @MainActor
    func operationSheetPinAndBudgetCopyIsLocalizedForSimplifiedChinese() {
        let locale = Locale(identifier: "zh-Hans")
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }
        LanguageManager.shared.setLanguage(.simplifiedChinese)

        #expect(AppLocalization.string("cashflow.category.actions.pin", locale: locale) == "固定")
        #expect(AppLocalization.string("cashflow.category.actions.unpin", locale: locale) == "取消固定")
        #expect(AppLocalization.string("cashflow.category.pinned", locale: locale) == "已固定分类")
        #expect(
            CashflowBudgetLocalization.categoryBudgetLimitLabel(
                for: .expense,
                amount: "12 000"
            ) == "限额 12 000"
        )
        #expect(
            CashflowBudgetLocalization.categoryBudgetLimitLabel(
                for: .income,
                amount: "12 000"
            ) == "计划 12 000"
        )
    }

    @Test("History screen runtime copy uses app locale for zh-Hans")
    @MainActor
    func historyScreenRuntimeCopyUsesAppLocaleForSimplifiedChinese() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }
        LanguageManager.shared.setLanguage(.simplifiedChinese)

        #expect(CashflowHistoryTypeFilter.all.title == "全部")
        #expect(CashflowHistoryTypeFilter.income.title == "收入")
        #expect(CashflowHistoryTypeFilter.expense.title == "支出")
        #expect(CashflowHistoryTypeFilter.transfer.title == "转账")
        #expect(CashflowHistoryTypeFilter.assetBalanceChange.title == "资产重估")
        #expect(CashflowHistoryTypeFilter.accountBalanceCorrection.title == "账户校正")
    }

    @Test("Release critical Cashflow screens avoid raw UI keys and device locale copy")
    func releaseCriticalCashflowSourceGuardsHold() throws {
        let viewSource = try String(contentsOf: sourceURL("millio/UI/Services/Cashflow/CashflowView.swift"), encoding: .utf8)
        let editorSource = try String(contentsOf: sourceURL("millio/UI/Services/Cashflow/CashflowTransactionEditorView.swift"), encoding: .utf8)
        let historySource = try String(contentsOf: sourceURL("millio/UI/Services/Cashflow/CashflowTransactionsHistoryView.swift"), encoding: .utf8)
        let insightsSource = try String(contentsOf: sourceURL("millio/UI/Services/Cashflow/CashflowInsightsChartModels.swift"), encoding: .utf8)
        let transactionSource = try String(contentsOf: sourceURL("millio/UI/Services/Cashflow/CashflowTransaction.swift"), encoding: .utf8)
        let operationSheetsSource = try String(contentsOf: sourceURL("millio/UI/Services/Cashflow/CashflowOperationSheets.swift"), encoding: .utf8)
        let scheduledTransactionsSource = try String(contentsOf: sourceURL("millio/UI/Services/Cashflow/CashflowScheduledTransactionsView.swift"), encoding: .utf8)

        #expect(!viewSource.contains("Text(\"cashflow."))
        #expect(!viewSource.contains(".navigationTitle(\"cashflow."))
        #expect(!viewSource.contains(".accessibilityLabel(Text(\"cashflow."))

        #expect(!editorSource.contains("Text(\"cashflow."))
        #expect(!editorSource.contains(".navigationTitle(\"cashflow."))
        #expect(!editorSource.contains("TextField(\"cashflow."))

        #expect(!historySource.contains("Locale.autoupdatingCurrent"))
        #expect(!historySource.contains("Locale.current"))
        #expect(!historySource.contains("String(localized:"))
        #expect(!insightsSource.contains("locale: .autoupdatingCurrent"))
        #expect(!transactionSource.contains("localizedName(locale:"))
        #expect(!operationSheetsSource.contains("Locale(identifier: \"ru_RU\")"))
        #expect(!operationSheetsSource.contains("TextField(\"cashflow."))
        #expect(!operationSheetsSource.contains(".navigationTitle(\"cashflow."))
        #expect(!operationSheetsSource.contains("\"Лимит "))
        #expect(!operationSheetsSource.contains("\"План "))
        #expect(!operationSheetsSource.contains("\"Pin category\""))
        #expect(!operationSheetsSource.contains("\"Unpin category\""))
        #expect(!operationSheetsSource.contains("\"Pinned category\""))
        #expect(!scheduledTransactionsSource.contains("Text(\"cashflow."))
    }

    private func sourceURL(_ relativePath: String) throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        for _ in 0..<12 {
            let candidate = directory.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }

        throw NSError(
            domain: "CashflowLocalizationRegressionTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate `\(relativePath)` from `#filePath`."]
        )
    }
}
