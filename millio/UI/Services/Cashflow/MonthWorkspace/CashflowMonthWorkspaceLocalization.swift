import Foundation

enum CashflowMonthWorkspaceLocalization {
    private static func value(ru: String, en: String, zh: String) -> String {
        switch LocalizationSupport.effectiveLanguage(for: AppLocalization.currentAppLocale) {
        case Language.russian.rawValue: ru
        case Language.simplifiedChinese.rawValue: zh
        default: en
        }
    }

    static var title: String { value(ru: "Месяц", en: "Month", zh: "月度") }
    static var year: String { value(ru: "Год", en: "Year", zh: "年") }
    static var chooseMonth: String { value(ru: "Выбрать месяц", en: "Choose month", zh: "选择月份") }
    static var wholeMonthHint: String { value(ru: "весь календарный месяц", en: "full calendar month", zh: "整个日历月") }
    static var previousMonth: String { value(ru: "Предыдущий месяц", en: "Previous month", zh: "上个月") }
    static var nextMonth: String { value(ru: "Следующий месяц", en: "Next month", zh: "下个月") }
    static var done: String { value(ru: "Готово", en: "Done", zh: "完成") }
    static var expense: String { value(ru: "Расходы", en: "Expenses", zh: "支出") }
    static var income: String { value(ru: "Доходы", en: "Income", zh: "收入") }
    static var transfer: String { value(ru: "Переводы", en: "Transfers", zh: "转账") }
    static var add: String { value(ru: "Добавить операцию", en: "Add transaction", zh: "添加交易") }
    static var noTransactions: String { value(ru: "Нет операций", en: "No transactions", zh: "无交易") }
    static var emptyHint: String { value(ru: "Добавьте операцию или импортируйте данные.", en: "Add a transaction or import data.", zh: "添加交易或导入数据。") }
    static var importData: String { value(ru: "Импорт", en: "Import", zh: "导入") }
    static var history: String { value(ru: "Вся история", en: "Full history", zh: "全部历史") }
    static var analytics: String { value(ru: "Аналитика и бюджеты", en: "Analytics & budgets", zh: "分析与预算") }
    static var expenseBudget: String { value(ru: "Бюджет расходов", en: "Expense budget", zh: "支出预算") }
    static var incomeBudget: String { value(ru: "План доходов", en: "Income plan", zh: "收入计划") }
    static var manualBulk: String { value(ru: "Ручной пакетный ввод", en: "Manual bulk entry", zh: "手动批量录入") }
    static var statement: String { value(ru: "Банковская выписка", en: "Bank statement", zh: "银行对账单") }
    static var privacy: String { value(ru: "Файл не сохраняется на устройстве после обработки.", en: "The original file is not retained after processing.", zh: "处理后不保留原始文件。") }
    static var unavailable: String { value(ru: "Сервис выписок сейчас недоступен.", en: "The statement service is currently unavailable.", zh: "对账单服务当前不可用。") }
    static var unsupported: String { value(ru: "Формат или шаблон банка не поддерживается.", en: "This bank format or template is unsupported.", zh: "不支持此银行格式或模板。") }
    static var reconciliationFailed: String { value(ru: "Итоги выписки не сходятся.", en: "Statement totals do not reconcile.", zh: "对账单总额无法对平。") }
    static var monthMismatch: String { value(ru: "Период выписки не совпадает с выбранным месяцем.", en: "The statement period does not match the selected month.", zh: "对账单周期与所选月份不匹配。") }
    static var account: String { value(ru: "Счёт", en: "Account", zh: "账户") }
    static var selectAccount: String { value(ru: "Выберите счёт", en: "Select account", zh: "选择账户") }
    static var linkToAccount: String { value(ru: "Привязать к счёту", en: "Link to account", zh: "关联到账户") }
    static var accountBalanceUnchanged: String { value(ru: "Баланс счёта не изменится", en: "The account balance will not change", zh: "账户余额不会变更") }
    static var review: String { value(ru: "Проверка", en: "Review", zh: "审核") }
    static var category: String { value(ru: "Категория", en: "Category", zh: "分类") }
    static var applySelected: String { value(ru: "Импортировать выбранные", en: "Apply selected transactions", zh: "导入所选交易") }
    static var confirmImport: String { value(ru: "Подтвердить импорт", en: "Confirm import", zh: "确认导入") }
    static var confirmImportMessage: String { value(ru: "Операции будут записаны в Cashflow. Это финальное подтверждение.", en: "Transactions will be written to Cashflow. This is the final confirmation.", zh: "交易将写入现金流。这是最终确认。") }
    static var summary: String { value(ru: "Сводка", en: "Summary", zh: "摘要") }
    static var categoryBreakdown: String { value(ru: "По категориям", en: "By category", zh: "按分类") }
    static func transactionCount(_ count: Int) -> String { value(ru: "(count) операций", en: "(count) transactions", zh: "(count) 笔交易") }
    static var totalRows: String { value(ru: "Всего строк", en: "Total rows", zh: "总行数") }
    static var includedRows: String { value(ru: "Включено", en: "Included", zh: "已包含") }
    static var excludedRows: String { value(ru: "Исключено", en: "Excluded", zh: "已排除") }
    static var duplicates: String { value(ru: "Дубли", en: "Duplicates", zh: "重复项") }
    static var transfers: String { value(ru: "Переводы", en: "Transfers", zh: "转账") }
    static var reconciliation: String { value(ru: "Сверка итогов", en: "Reconciliation", zh: "对账") }
    static var reconciliationSuccess: String { value(ru: "Итоги сошлись", en: "Totals reconcile", zh: "总额已对平") }
    static var difference: String { value(ru: "Разница", en: "Difference", zh: "差额") }
    static var excludedDuplicate: String { value(ru: "Исключено: возможный дубль", en: "Excluded: possible duplicate", zh: "已排除：可能重复") }
    static var excludedTransfer: String { value(ru: "Исключено: перевод не влияет на Cashflow", en: "Excluded: transfer does not affect Cashflow", zh: "已排除：转账不影响现金流") }
    static var excludedTechnical: String { value(ru: "Исключено: техническая строка банка", en: "Excluded: bank technical row", zh: "已排除：银行技术行") }
    static var applying: String { value(ru: "Импорт…", en: "Applying transactions…", zh: "正在导入交易…") }
    static var retryFailure: String { value(ru: "Импорт не удался. Повторите.", en: "Import failed. Try again.", zh: "导入失败，请重试。") }
    static var applyFailure: String { value(ru: "Не удалось применить импорт.", en: "Import could not be applied.", zh: "无法应用导入。") }
    static var open: String { value(ru: "Открыт", en: "Open", zh: "已开放") }
    static var closed: String { value(ru: "Закрыт", en: "Closed", zh: "已关闭") }
    static var closeMonth: String { value(ru: "Закрыть месяц", en: "Close month", zh: "关闭月度") }
    static var reopenMonth: String { value(ru: "Переоткрыть месяц", en: "Reopen month", zh: "重新打开月度") }
    static var closeExplanation: String { value(ru: "После закрытия доходы, расходы, переводы и импорт будут заблокированы. История закрытия сохранится.", en: "Closing blocks income, expense, transfer and import changes. The audit history is retained.", zh: "关闭后将阻止收入、支出、转账和导入更改，并保留审计历史。") }
    static var notReady: String { value(ru: "Можно закрыть только завершённый прошлый месяц.", en: "Only a completed past month can be closed.", zh: "只能关闭已完成的过去月度。") }
    static var ready: String { value(ru: "Проверки пройдены", en: "Checks passed", zh: "检查已通过") }
    static var closedExplanation: String { value(ru: "Месяц доступен только для чтения. Переоткройте его, чтобы изменять операции.", en: "This month is read-only. Reopen it to change transactions.", zh: "该月度为只读。重新打开后才能修改交易。") }
    static var confirmClose: String { value(ru: "Подтвердить закрытие", en: "Confirm closing", zh: "确认关闭") }
    static var confirmReopen: String { value(ru: "Подтвердить переоткрытие", en: "Confirm reopening", zh: "确认重新打开") }
    static var cancel: String { value(ru: "Отмена", en: "Cancel", zh: "取消") }
}
