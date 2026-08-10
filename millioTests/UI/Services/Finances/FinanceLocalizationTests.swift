//
//  FinanceLocalizationTests.swift
//  millioTests
//

import Testing
import Foundation
@testable import millio

struct FinanceLocalizationTests {
    @Test("Ключи локализации финансового модуля резолвятся в строки, а не остаются ключами")
    func financeLocalizationKeysResolve() {
        let keys = [
            "finances.main.title",
            "finances.dynamics.title",
            "finances.main.refresh_quotes",
            "finances.main.refresh_stocks",
            "finances.group.menu.priority",
            "finances.warning.rate_unavailable",
            "finances.investment.position_subtitle",
            "finances.dynamics.warning.estimated_rate",
            "finances.add_account.nav.new",
            "finances.add_account.section.balance",
            "finances.add_account.total_impact.include",
            "finances.common.add",
            "finances.common.save",
            "finances.common.reset",
            "finances.card.type.debit",
            "finances.investment.category.stocks",
            "finances.credit.payment_mode.next_date",
            "finances.editor.card.new_title",
            "finances.quick_edit.title.amount",
            "finances.display_currency.title.primary",
            "finances.savings_goal.title",
            "finances.dynamics.filter.title",
            "finances.group_editor.nav.new",
            "finances.transaction.note.credit_remaining_edit",
            "finances.settings.title",
            "finances.audit.nav.title",
            "finances.audit.search.placeholder",
            "finances.audit.date_picker.title",
            "finances.chart.axis.total",
            "finances.dynamics.delete_account",
            "finances.dynamics.delete_account.confirm.message",
            "finances.dynamics.delete_account.confirm.title",
            "finances.dynamics.delete_investment",
            "finances.dynamics.delete_investment.confirm.message",
            "finances.dynamics.delete_investment.confirm.title",
            "finances.main.empty_intro.title",
            "finances.main.empty_intro.description",
            "finances.main.empty_intro.add_product",
            "finances.main.empty_intro.open_dynamics",
            "finances.main.empty_intro.dismiss",
        ]

        for key in keys {
            #expect(FinancesL10n.tr(key) != key)
        }
    }

    @Test("Форматируемые строки финансов подставляют динамические значения")
    func financeLocalizationFormatsDynamicValues() {
        let warning = FinancesL10n.format("finances.warning.rate_unavailable", "USD", "RUB")
        #expect(warning.contains("USD"))
        #expect(warning.contains("RUB"))

        let subtitle = FinancesL10n.format(
            "finances.investment.position_subtitle",
            "1.5",
            FinancesL10n.tr("finances.investment.unit.coins"),
            "100",
            "$"
        )
        #expect(subtitle.contains("1.5"))
        #expect(subtitle.contains("100"))
        #expect(subtitle.contains("$"))
    }

    @Test("Release-critical финансовые ключи локализованы для ru en zh-Hans")
    func releaseCriticalFinanceKeysExistForThreeLanguages() {
        let ru = Locale(identifier: "ru_RU")
        let en = Locale(identifier: "en_US")
        let zh = Locale(identifier: "zh-Hans")

        #expect(AppLocalization.string("finances.dynamics.delete_group.confirm.message", locale: ru) == "Это действие удалит группу и все продукты внутри неё. Подтвердите удаление.")
        #expect(AppLocalization.string("finances.dynamics.delete_group.confirm.message", locale: en) == "This will delete the group and every product inside it. Please confirm the deletion.")
        #expect(AppLocalization.string("finances.dynamics.delete_group.confirm.message", locale: zh) == "此操作会删除该分组及其中的所有产品。请确认删除。")

        #expect(AppLocalization.string("finances.group_editor.color.show_palette", locale: ru) == "Выбрать цвет")
        #expect(AppLocalization.string("finances.group_editor.color.show_palette", locale: en) == "Choose color")
        #expect(AppLocalization.string("finances.group_editor.color.show_palette", locale: zh) == "选择颜色")

        #expect(AppLocalization.string("monetization.free_plan.title", locale: ru) == "Ограничение Free-плана")
        #expect(AppLocalization.string("monetization.free_plan.title", locale: en) == "Free plan limit")
        #expect(AppLocalization.string("monetization.free_plan.title", locale: zh) == "Free 方案限制")
    }

    @Test("Release-critical Finances screens avoid raw keys and device-locale branching")
    func releaseCriticalFinancesSourceGuardsHold() throws {
        let financesView = try String(contentsOf: sourceURL("millio/UI/Services/Finances/FinancesView.swift"), encoding: .utf8)
        let rowsView = try String(contentsOf: sourceURL("millio/UI/Services/Finances/Rows/FinanceRows.swift"), encoding: .utf8)
        let dynamicsView = try String(contentsOf: sourceURL("millio/UI/Services/Finances/FinanceDynamicsView.swift"), encoding: .utf8)
        let groupEditorView = try String(contentsOf: sourceURL("millio/UI/Services/Finances/Editors/FinanceGroupEditorView.swift"), encoding: .utf8)
        let productPicker = try String(contentsOf: sourceURL("millio/UI/Services/Finances/Editors/FinanceAddAccountProductPicker.swift"), encoding: .utf8)
        let overviewCardView = try String(contentsOf: sourceURL("millio/UI/Services/Finances/Components/FinanceOverviewCardView.swift"), encoding: .utf8)
        let marketDataPresentation = try String(contentsOf: sourceURL("millio/UI/Services/Investments/MarketData/MarketDataErrorPresentation.swift"), encoding: .utf8)
        let stockBulkImportSheet = try String(contentsOf: sourceURL("millio/UI/Services/Finances/Import/StockBulkImportSheet.swift"), encoding: .utf8)
        let financesSheets = try String(contentsOf: sourceURL("millio/UI/Services/Finances/Sheets/FinancesSheets.swift"), encoding: .utf8)

        #expect(!financesView.contains("Text(\"finances."))
        #expect(!financesView.contains("String(localized:"))
        #expect(!rowsView.contains("Text(\"finances."))
        #expect(!dynamicsView.contains("Locale.current"))
        #expect(!groupEditorView.contains("Locale.current"))
        #expect(!productPicker.contains("FinancesL10n.text("))
        #expect(!overviewCardView.contains("FinancesL10n.text("))
        #expect(!overviewCardView.contains("Locale.current"))
        #expect(!marketDataPresentation.contains("FinancesL10n.text("))
        #expect(!marketDataPresentation.contains("Locale.current"))
        #expect(!stockBulkImportSheet.contains("locale: .current"))
        #expect(!stockBulkImportSheet.contains("String(localized: \"finances.mass_import."))
        #expect(!financesSheets.contains("String(localized: \"finances.savings_goal."))
    }

    @Test("Compact overview не дублирует saldo, содержит donut и читает канонический snapshot")
    func compactOverviewKeepsSingleBalanceNumber() throws {
        let financesView = try String(
            contentsOf: sourceURL("millio/UI/Services/Finances/FinancesView.swift"),
            encoding: .utf8
        )
        let overviewCardView = try String(
            contentsOf: sourceURL("millio/UI/Services/Finances/Components/FinanceOverviewCardView.swift"),
            encoding: .utf8
        )
        let compactStart = try #require(
            overviewCardView.range(of: "private func assetsLiabilitiesStackedBar")
        )
        let compactEnd = try #require(
            overviewCardView.range(
                of: "private func stackedBarLegend",
                range: compactStart.upperBound..<overviewCardView.endIndex
            )
        )
        let compactOverview = overviewCardView[compactStart.lowerBound..<compactEnd.lowerBound]

        #expect(!compactOverview.contains("finances.overview.chart.saldo"))
        #expect(compactOverview.contains("FinanceBalanceCompositionDonut(presentation: presentation)"))
        #expect(!financesView.contains("heroLedgerPresentation"))
        #expect(overviewCardView.contains("financeViewModel.coreAccountsSnapshot(matching: group)"))
        #expect(!overviewCardView.contains("sortedCoreAccounts(group.accounts ?? [])"))
    }

    @Test("Overview и market-data copy локализованы для ru en zh-Hans")
    func overviewAndMarketKeysExistForThreeLanguages() {
        let ru = Locale(identifier: "ru_RU")
        let en = Locale(identifier: "en_US")
        let zh = Locale(identifier: "zh-Hans")

        #expect(AppLocalization.string("finances.market.refresh.degraded_message", locale: ru) == "Не удалось обновить часть котировок. Показываем последние доступные данные.")
        #expect(AppLocalization.string("finances.market.refresh.degraded_message", locale: en) == "Some quotes could not be refreshed. Showing the latest available data.")
        #expect(AppLocalization.string("finances.market.refresh.degraded_message", locale: zh) == "部分行情未能刷新。正在显示最近可用的数据。")

        #expect(AppLocalization.string("finances.market.list.network_error", locale: ru) == "Сетевая ошибка загрузки котировок")
        #expect(AppLocalization.string("finances.market.list.network_error", locale: en) == "Network error while loading quotes")
        #expect(AppLocalization.string("finances.market.list.network_error", locale: zh) == "加载行情时发生网络错误")

        #expect(AppLocalization.string("finances.overview.nav.title", locale: ru) == "Бухгалтерская раскладка")
        #expect(AppLocalization.string("finances.overview.nav.title", locale: en) == "Ledger overview")
        #expect(AppLocalization.string("finances.overview.nav.title", locale: zh) == "账目总览")

        #expect(AppLocalization.string("finances.overview.ungrouped", locale: ru) == "Без группы")
        #expect(AppLocalization.string("finances.overview.ungrouped", locale: en) == "Ungrouped")
        #expect(AppLocalization.string("finances.overview.ungrouped", locale: zh) == "未分组")
    }

    @Test("DisplayName enum-ов в создании продукта приходят из локализации")
    func addAccountDisplayNamesAreLocalized() {
        #expect(CardType.debit.displayName != "finances.card.type.debit")
        #expect(CardType.credit.displayName != "finances.card.type.credit")
        #expect(InvestmentType.positive.displayName != "finances.investment.type.positive")
        #expect(InvestmentCategory.crypto.displayName != "finances.investment.category.crypto")
        #expect(CreditType.consumer.displayName != "finances.credit.type.consumer")
        #expect(CreditPaymentMode.nextDate.displayName != "finances.credit.payment_mode.next_date")
    }

    @Test("Все ключи finances.* имеют переводы ru/en в Localizable.xcstrings")
    func allFinanceKeysHaveRuAndEnTranslations() throws {
        let strings = try loadFinanceStrings()

        for (key, rawValue) in strings where key.hasPrefix("finances.") {
            let value = try #require(rawValue as? [String: Any], "Invalid entry for key: \(key)")
            let localizations = try #require(value["localizations"] as? [String: Any], "Missing localizations for key: \(key)")
            let en = try #require(localizations["en"] as? [String: Any], "Missing en localization: \(key)")
            let ru = try #require(localizations["ru"] as? [String: Any], "Missing ru localization: \(key)")
            let enUnit = try #require(en["stringUnit"] as? [String: Any], "Missing en stringUnit: \(key)")
            let ruUnit = try #require(ru["stringUnit"] as? [String: Any], "Missing ru stringUnit: \(key)")
            let enValue = try #require(enUnit["value"] as? String, "Missing en value: \(key)")
            let ruValue = try #require(ruUnit["value"] as? String, "Missing ru value: \(key)")
            #expect(!enValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty en value: \(key)")
            #expect(!ruValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Empty ru value: \(key)")
        }
    }

    @Test("Индустриальные формулировки в финансах зафиксированы для ru/en")
    func industrialFinanceCopyMatchesExpectedValues() throws {
        let strings = try loadFinanceStrings()

        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.title",
            locale: "ru",
            equals: "Ваши продукты"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.title",
            locale: "en",
            equals: "Your Products"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.description",
            locale: "ru",
            equals: "Создавайте счета и карты, добавляйте акции, криптовалюту, недвижимость и любые другие продукты в одном удобном интерфейсе"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.description",
            locale: "en",
            equals: "Create accounts and cards, add stocks, crypto, real estate, and any other products in one streamlined interface"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.title",
            locale: "zh-Hans",
            equals: "资产"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.title",
            locale: "zh-Hans",
            equals: "动态"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.title",
            locale: "zh-Hans",
            equals: "您的产品"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.description",
            locale: "zh-Hans",
            equals: "在一个清晰的界面中创建账户和卡片，添加股票、加密货币、房地产以及其他各类资产产品"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.add_product",
            locale: "zh-Hans",
            equals: "添加产品"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.open_dynamics",
            locale: "zh-Hans",
            equals: "打开动态"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.main.empty_intro.dismiss",
            locale: "zh-Hans",
            equals: "隐藏概览"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.title",
            locale: "ru",
            equals: "Параметры финансов"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.title",
            locale: "en",
            equals: "Finance Controls"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.title",
            locale: "zh-Hans",
            equals: "资产设置"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.mass_import.title",
            locale: "zh-Hans",
            equals: "批量导入代码"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.mass_import.subtitle",
            locale: "zh-Hans",
            equals: "从截图或文本导入股票持仓"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.savings_goal.title",
            locale: "zh-Hans",
            equals: "储蓄目标"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.savings_goal.subtitle",
            locale: "zh-Hans",
            equals: "目标金额与完成进度"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.archived_accounts.title",
            locale: "ru",
            equals: "Архивированные счета"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.archived_accounts.subtitle",
            locale: "en",
            equals: "Restore hidden accounts"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.daily_audit.title",
            locale: "zh-Hans",
            equals: "每日余额快照"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.settings.daily_audit.subtitle",
            locale: "zh-Hans",
            equals: "每日对账、调整与检查"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.title",
            locale: "zh-Hans",
            equals: "批量导入股票"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.mode.manual",
            locale: "zh-Hans",
            equals: "手动"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.source.title",
            locale: "zh-Hans",
            equals: "来源"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.group.hint",
            locale: "zh-Hans",
            equals: "选择导入后持仓要保存到的分组"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.include_in_total.hint",
            locale: "zh-Hans",
            equals: "新资产会立即计入总资产余额"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.source.screenshot.hint",
            locale: "zh-Hans",
            equals: "浅色背景上的清晰表格和持仓列表识别效果最好"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.merge_duplicates.hint",
            locale: "zh-Hans",
            equals: "将重复代码合并成一个最终持仓"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.preview_empty",
            locale: "zh-Hans",
            equals: "添加截图或粘贴行内容以生成导入预览"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.common.reset",
            locale: "zh-Hans",
            equals: "重置"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.field_ticker",
            locale: "zh-Hans",
            equals: "代码或交易对"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.field_market",
            locale: "zh-Hans",
            equals: "市场"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.field_quantity",
            locale: "zh-Hans",
            equals: "数量"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.field_buy_price",
            locale: "zh-Hans",
            equals: "买入价"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.mass_import.field_current_price",
            locale: "zh-Hans",
            equals: "当前价"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.common.save",
            locale: "zh-Hans",
            equals: "保存"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.savings_goal.title",
            locale: "zh-Hans",
            equals: "储蓄目标"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.savings_goal.settings_section",
            locale: "zh-Hans",
            equals: "目标设置"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.savings_goal.enabled",
            locale: "zh-Hans",
            equals: "启用储蓄目标"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.savings_goal.amount_section",
            locale: "zh-Hans",
            equals: "目标金额（%@）"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.savings_goal.amount_placeholder",
            locale: "zh-Hans",
            equals: "目标金额"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.audit.nav.title",
            locale: "zh-Hans",
            equals: "每日快照"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.audit.search.placeholder",
            locale: "zh-Hans",
            equals: "搜索账户"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.audit.empty.no_snapshot",
            locale: "zh-Hans",
            equals: "该日期没有已保存的快照"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.audit.empty.select_other_date",
            locale: "zh-Hans",
            equals: "选择其他日期"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.audit.menu.date",
            locale: "zh-Hans",
            equals: "日期"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.audit.menu.edit_mode.start",
            locale: "zh-Hans",
            equals: "编辑模式"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.audit.date_picker.title",
            locale: "zh-Hans",
            equals: "选择日期"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.audit.date_picker.done",
            locale: "zh-Hans",
            equals: "完成"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.audit.save",
            locale: "zh-Hans",
            equals: "保存"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.common.cancel",
            locale: "zh-Hans",
            equals: "取消"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.custom_period.subtitle",
            locale: "zh-Hans",
            equals: "在日历上选择开始和结束日期"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.custom_period.show",
            locale: "zh-Hans",
            equals: "显示"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.empty.products.title",
            locale: "zh-Hans",
            equals: "暂无产品"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.empty.products.subtitle",
            locale: "zh-Hans",
            equals: "创建你的第一个产品"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.filter.title",
            locale: "zh-Hans",
            equals: "筛选"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.filter.search_placeholder",
            locale: "zh-Hans",
            equals: "搜索"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.filter.show_all",
            locale: "zh-Hans",
            equals: "显示全部"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.filter.clear_selection",
            locale: "zh-Hans",
            equals: "清除选择"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.filter.archive_section",
            locale: "zh-Hans",
            equals: "归档"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.filter.show_archived_accounts",
            locale: "zh-Hans",
            equals: "显示已归档账户"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.filter.apply",
            locale: "zh-Hans",
            equals: "应用筛选"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.pro.title",
            locale: "ru",
            equals: "Расширенная графическая аналитика доступна в PRO"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.pro.title",
            locale: "en",
            equals: "Advanced charting is available in PRO"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.pro.title",
            locale: "zh-Hans",
            equals: "高级图表分析功能仅在 PRO 中提供"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.pro.subtitle",
            locale: "ru",
            equals: "Оформите подписку для доступа к расширенной аналитике баланса"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.pro.subtitle",
            locale: "en",
            equals: "Upgrade to access advanced balance analytics"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.pro.subtitle",
            locale: "zh-Hans",
            equals: "开通订阅即可访问更高级的资产余额分析"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.empty.groups.title",
            locale: "zh-Hans",
            equals: "暂无分组"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.view_mode.groups",
            locale: "zh-Hans",
            equals: "分组"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.view_mode.accounts",
            locale: "zh-Hans",
            equals: "账户"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.view_mode.title",
            locale: "zh-Hans",
            equals: "动态视图模式"
        )
        try assertLocalizedValue(
            strings: strings,
            key: "finances.dynamics.period.range",
            locale: "zh-Hans",
            equals: "%1$@ — %2$@"
        )
    }

    private func loadFinanceStrings() throws -> [String: Any] {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let xcstringsURL = repoRootURL
            .appendingPathComponent("millio")
            .appendingPathComponent("Localizable.xcstrings")

        let data = try Data(contentsOf: xcstringsURL)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["strings"] as? [String: Any])
    }

    private func assertLocalizedValue(
        strings: [String: Any],
        key: String,
        locale: String,
        equals expectedValue: String
    ) throws {
        let rawValue = try #require(strings[key] as? [String: Any], "Missing key: \(key)")
        let localizations = try #require(rawValue["localizations"] as? [String: Any], "Missing localizations: \(key)")
        let localeValue = try #require(localizations[locale] as? [String: Any], "Missing locale \(locale): \(key)")
        let stringUnit = try #require(localeValue["stringUnit"] as? [String: Any], "Missing stringUnit: \(key)")
        let value = try #require(stringUnit["value"] as? String, "Missing value: \(key)")
        #expect(value == expectedValue, "Unexpected \(locale) copy for \(key)")
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
            domain: "FinanceLocalizationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate `\(relativePath)` from `#filePath`."]
        )
    }
}
