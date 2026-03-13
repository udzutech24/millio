//
//  CashflowLocalizationRegressionTests.swift
//  millioTests
//
//  Created by Codex on 09.03.2026.
//

import Foundation
import Testing
@testable import millio

struct CashflowLocalizationRegressionTests {
    @Test("Russian locale contains localized Cashflow labels")
    func russianLocaleHasCashflowTranslations() {
        let locale = Locale(identifier: "ru_RU")

        #expect(AppLocalization.string("cashflow.stats.assets_start", locale: locale) == "Активы на начало периода")
        #expect(AppLocalization.string("cashflow.stats.assets_end", locale: locale) == "Активы на конец периода")
        #expect(AppLocalization.string("cashflow.stats.expenses", locale: locale) == "Расходы")
        #expect(AppLocalization.string("cashflow.stats.asset_value_change", locale: locale) == "Изменение стоимости активов")
        #expect(AppLocalization.string("cashflow.stats.result", locale: locale) == "Результат")
        #expect(AppLocalization.string("cashflow.quick_action.transfer", locale: locale) == "Перевод")
        #expect(AppLocalization.string("cashflow.chart.expand", locale: locale) == "Развернуть график")
        #expect(AppLocalization.string("cashflow.chart.visible_range", locale: locale) == "Диапазон")
        #expect(AppLocalization.string("cashflow.chart.hint_format", locale: locale).contains("Диапазон"))
        #expect(AppLocalization.string("cashflow.period_selector.title", locale: locale) == "Выбор периода")
        #expect(AppLocalization.string("cashflow.editor.transaction_type", locale: locale) == "Тип операции")
        #expect(AppLocalization.string("cashflow.operation.total", locale: locale) == "Итого")
        #expect(AppLocalization.string("cashflow.scheduled.monthly_badge", locale: locale) == "Ежемесячно")
        #expect(AppLocalization.string("cashflow.scheduled.planner_expenses", locale: locale) == "Планировщик платежей")
        #expect(AppLocalization.string("cashflow.scheduled.display.calendar", locale: locale) == "Календарь")
        #expect(AppLocalization.string("cashflow.scheduled.display.list", locale: locale) == "Список")
        #expect(AppLocalization.string("cashflow.scheduled.create_picker.title", locale: locale) == "Что добавить?")
        #expect(AppLocalization.string("cashflow.scheduled.create_picker.monthly", locale: locale) == "Ежемесячно")
        #expect(AppLocalization.string("cashflow.scheduled.create_picker.one_time", locale: locale) == "Разово")
        #expect(AppLocalization.string("cashflow.scheduled.day_agenda.empty.add_here", locale: locale) == "Добавить")
        #expect(AppLocalization.string("cashflow.editor.category_sheet.title.expense", locale: locale) == "Категории расходов")
        #expect(AppLocalization.string("cashflow.editor.category_sheet.create.expense", locale: locale) == "Создать категорию расходов")

        #expect(AppLocalization.string("Income", locale: locale) == "Доход")
        #expect(AppLocalization.string("Expense", locale: locale) == "Расход")
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
