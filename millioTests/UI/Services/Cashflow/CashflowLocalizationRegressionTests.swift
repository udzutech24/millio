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

    @Test("Legacy Russian system override names are treated as system names after language switch")
    @MainActor
    func legacyRussianSystemOverrideNamesAreLocalized() throws {
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
        #expect(AppLocalization.string("cashflow.chart.empty.banner.open_finances", locale: locale) == "Перейти в Финансы")
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
        #expect(AppLocalization.string("cashflow.main.empty_intro.description", locale: locale) == "Вы в разделе «Кэшфлоу»: здесь видно, откуда приходят деньги, куда уходят и какой итог за период, перейдите в «Финансы», чтобы управлять продуктами и балансами детально")

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
        #expect(AppLocalization.string("cashflow.chart.empty.banner.title", locale: locale) == "Cashflow pulse")
        #expect(AppLocalization.string("cashflow.chart.empty.banner.subtitle", locale: locale) == "When income and expenses appear in the selected period, a trend chart will show up here, start with your first transaction")
        #expect(AppLocalization.string("cashflow.chart.empty.banner.add_action", locale: locale) == "Add transaction")
        #expect(AppLocalization.string("cashflow.chart.empty.banner.open_finances", locale: locale) == "Open Finances")
        #expect(AppLocalization.string("cashflow.stats.income", locale: locale) == "Income")
        #expect(AppLocalization.string("cashflow.category.actions.message", locale: locale) == "Choose an action for this category.")
        #expect(AppLocalization.string("cashflow.category.actions.delete", locale: locale) == "Delete")
        #expect(AppLocalization.string("cashflow.category.visibility.visible", locale: locale) == "Visible in list")
        #expect(AppLocalization.string("cashflow.editor.affect_balance.subtitle.expense", locale: locale) == "Turn off if the current balance is already correct and you only need to backfill expense history for the selected period")
        #expect(AppLocalization.string("cashflow.recurrence.quarterly", locale: locale) == "Every 3 months")
        #expect(AppLocalization.string("cashflow.recurrence.semiannual", locale: locale) == "Every 6 months")
        #expect(AppLocalization.string("cashflow.recurrence.yearly", locale: locale) == "Every year")
        #expect(AppLocalization.string("cashflow.main.empty_intro.description", locale: locale) == "You are in Cashflow: this screen shows where money comes from, where it goes, and period totals, go to Finances to manage products and balances in detail")
        #expect(AppLocalization.string("cashflow.scheduled.day_agenda.summary.empty", locale: locale) == "You can add another planned item directly to this date.")
        #expect(AppLocalization.string("cashflow.asset_change.balance_check", locale: locale) == "Balance check")
        #expect(AppLocalization.string("Salary", locale: locale) == "Salary")
        #expect(AppLocalization.string("Groceries", locale: locale) == "Groceries")
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
}
