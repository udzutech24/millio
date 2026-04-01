//
//  CashbackLocalization.swift
//  millio
//
//  Centralized localization contract for Cashback surfaces.
//

import Foundation

enum CashbackL10n {
    static var locale: Locale { AppLocalization.currentAppLocale }

    static func text(_ key: String, locale: Locale = AppLocalization.currentAppLocale, fallback: String? = nil) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
    }

    static func formatted(_ key: String, _ arguments: CVarArg..., locale: Locale = AppLocalization.currentAppLocale, fallback: String? = nil) -> String {
        String(format: text(key, locale: locale, fallback: fallback), locale: locale, arguments: arguments)
    }

    static var supportedLocales: [Locale] {
        var seen = Set<String>()
        let locales = LocalizationSupport.userSelectableLanguages.compactMap(\.locale) + [AppLocalization.currentAppLocale]
        return locales.filter { locale in
            seen.insert(locale.identifier).inserted
        }
    }

    static var emptyStateTitle: String { text("cashback.empty.title", fallback: "No cashback this month") }
    static var emptyStateSubtitle: String { text("cashback.empty.subtitle", fallback: "Add cashback categories to get started") }
    static var emptyStateCTA: String { text("cashback.empty.cta", fallback: "Add cashback") }
    static var categoriesSectionTitle: String { text("cashback.section.categories", fallback: "Cashback categories") }
    static var searchPlaceholder: String { text("cashback.search.placeholder", fallback: "Search categories") }
    static var clearSearchAccessibility: String { text("cashback.search.clear.accessibility", fallback: "Clear search") }
    static var searchEmptyTitle: String { text("cashback.search.empty.title", fallback: "Nothing found") }
    static var searchEmptySubtitle: String { text("cashback.search.empty.subtitle", fallback: "Try a different category or card name") }
    static var backAccessibility: String { text("cashback.accessibility.back", fallback: "Back") }
    static var quickNavigationAccessibility: String { text("cashback.accessibility.quick_navigation", fallback: "Quick navigation between mini apps") }
    static var previousMonthAccessibility: String { text("cashback.accessibility.previous_month", fallback: "Previous month") }
    static var nextMonthAccessibility: String { text("cashback.accessibility.next_month", fallback: "Next month") }
    static var closeSearchAccessibility: String { text("cashback.accessibility.close_search", fallback: "Close search") }
    static var openSearchAccessibility: String { text("cashback.accessibility.open_search", fallback: "Search") }
    static var categorySettingsAccessibility: String { text("cashback.accessibility.category_settings", fallback: "Category settings") }
    static var categoryEditAccessibility: String { text("cashback.accessibility.edit_category", fallback: "Edit category") }
    static var favoriteAddAccessibility: String { text("cashback.accessibility.favorite.add", fallback: "Add to favorites") }
    static var favoriteRemoveAccessibility: String { text("cashback.accessibility.favorite.remove", fallback: "Remove from favorites") }
    static var categorySettingsTitle: String { text("cashback.category_settings.title", fallback: "Category settings") }
    static var dismissAccessibility: String { text("cashback.common.dismiss", fallback: "Close") }
    static var pinnedBadge: String { text("cashback.badge.pinned", fallback: "PIN") }
    static var topBadge: String { text("cashback.badge.top", fallback: "TOP") }
    static var unpinAction: String { text("cashback.row.action.unpin", fallback: "Unpin") }
    static var pinAction: String { text("cashback.row.action.pin", fallback: "Pin") }
    static var editAction: String { text("cashback.row.action.edit", fallback: "Edit") }
    static var deleteAction: String { text("cashback.row.action.delete", fallback: "Delete") }
    static var noLinkedCard: String { text("cashback.card.none_linked", fallback: "No linked card") }
    static var newCashbackTitle: String { text("cashback.editor.title.new", fallback: "New cashback") }
    static var editCashbackTitle: String { text("cashback.editor.title.edit", fallback: "Edit cashback") }
    static var importScreenshotTitle: String { text("cashback.import.screenshot.title", fallback: "Import from screenshot") }
    static var paywallTitle: String { text("cashback.paywall.free_plan.title", fallback: "Free plan limit") }
    static var selectCardSectionTitle: String { text("cashback.editor.section.card", fallback: "Select a card") }
    static var selectedBadge: String { text("cashback.badge.selected", fallback: "Selected") }
    static var selectCardCTA: String { text("cashback.card.select", fallback: "Select card") }
    static var selectCardHint: String { text("cashback.card.select.hint", fallback: "Cashback will not be saved without a card") }
    static var categoryPickerSectionTitle: String { text("cashback.editor.section.categories", fallback: "Choose categories") }
    static var importScreenshotCTA: String { text("cashback.import.screenshot.cta", fallback: "Import from screenshot") }
    static var searchCategoriesPlaceholder: String { text("cashback.category.search.placeholder", fallback: "Search categories") }
    static var createCategoryCTA: String { text("cashback.category.create", fallback: "Create category") }
    static var collapseCategoriesCTA: String { text("cashback.category.collapse", fallback: "Collapse") }
    static var showMoreCategoriesCTA: String { text("cashback.category.show_more", fallback: "Show more") }
    static var deleteCategoryTitle: String { text("cashback.category.delete.title", fallback: "Delete category?") }
    static var deleteCategoryMessage: String { text("cashback.category.delete.message", fallback: "Linked cashback entries will be moved to Other.") }
    static var selectedCategoriesTitle: String { text("cashback.editor.section.selected_categories", fallback: "Selected categories") }
    static var selectCategoryHint: String { text("cashback.editor.selected_categories.empty", fallback: "Choose at least one category") }
    static var removeCategoryAccessibility: String { text("cashback.accessibility.remove_category", fallback: "Remove category") }
    static var saveCTA: String { text("cashback.common.save", fallback: "Save") }
    static var categoryEditorTabEmoji: String { text("cashback.category_editor.tab.emoji", fallback: "Emoji") }
    static var categoryEditorTabSymbols: String { text("cashback.category_editor.tab.symbols", fallback: "Icons") }
    static var categoryEditorTitleNew: String { text("cashback.category_editor.title.new", fallback: "New category") }
    static var categoryEditorTitleEdit: String { text("cashback.category_editor.title.edit", fallback: "Category") }
    static var categoryEditorNameTitle: String { text("cashback.category_editor.name.title", fallback: "Name") }
    static var categoryEditorNamePlaceholder: String { text("cashback.category_editor.name.placeholder", fallback: "For example: Coffee shops") }
    static var categoryEditorIconTitle: String { text("cashback.category_editor.icon.title", fallback: "Icon") }
    static var categoryEditorSuggestedIconsTitle: String { text("cashback.category_editor.icon.suggestions", fallback: "Suggested icons") }
    static var categoryEditorIconPickerTitle: String { text("cashback.category_editor.icon.picker_title", fallback: "Icon type") }
    static var categoryEditorIconSearchPlaceholder: String { text("cashback.category_editor.icon.search.placeholder", fallback: "Search icons") }
    static var noCardsTitle: String { text("cashback.card_picker.empty.title", fallback: "No available cards") }
    static func noCardsSubtitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        let financesTitle = localizedFinancesServiceNameForCardPicker(locale: locale)
        return formatted(
            "cashback.card_picker.empty.subtitle",
            financesTitle,
            locale: locale,
            fallback: "Add a card in %@"
        )
    }
    static var cardPickerTitle: String { text("cashback.card_picker.title", fallback: "Card selection") }
    static var doneAccessibility: String { text("cashback.common.done", fallback: "Done") }
    static var cardPickerHeader: String { text("cashback.card_picker.header", fallback: "Select the card for which you configure categories and percentages this month") }
    static var favoriteMarker: String { text("cashback.card.favorite", fallback: "Favorite") }
    static var addCardHintTitle: String { text("cashback.card_recommendation.title", fallback: "Where to add a new card") }
    static var hideRecommendationCTA: String { text("cashback.card_recommendation.hide", fallback: "Hide") }
    static var hideRecommendationAccessibility: String { text("cashback.card_recommendation.hide.accessibility", fallback: "Hide recommendation") }
    static var addCardCTA: String { text("cashback.card_recommendation.add_card", fallback: "Add card") }
    static var addCardAccessibility: String { text("cashback.card_recommendation.add_card.accessibility", fallback: "Open new card creation") }
    static var unnamedCardTitle: String { text("cashback.card.unnamed", fallback: "Untitled card") }
    static var balancePrefix: String { text("cashback.card.detail.balance", fallback: "Balance") }
    static var creditLimitPrefix: String { text("cashback.card.detail.limit", fallback: "Limit") }

    static func cardLimitText(_ limit: Int) -> String {
        formatted("cashback.free_plan.card_limit_format", limit)
    }

    static var subscribeCTA: String {
        text("subscription.button.subscribe", fallback: "Subscribe")
    }

    static var screenshotImportLockedText: String {
        text("cashback.import.screenshot.pro_only", fallback: "Screenshot import is available in PRO")
    }

    static var screenshotImportLoadingText: String {
        text("cashback.import.screenshot.loading", fallback: "Reading screenshot...")
    }

    static func screenshotImportRecognizedText(_ count: Int) -> String {
        formatted("cashback.import.screenshot.recognized_format", count)
    }

    static func paywallCategoryLimitText(_ limit: Int) -> String {
        formatted("monetization.cashback.categories.limit.hard_format", limit)
    }

    static func addCardHintSubtitle(financesTitle: String) -> String {
        formatted("cashback.card_recommendation.subtitle_format", financesTitle)
    }

    private static func localizedFinancesServiceNameForCardPicker(locale: Locale) -> String {
        switch LocalizationSupport.effectiveLanguage(for: locale) {
        case Language.russian.rawValue:
            return "Финансах"
        case Language.simplifiedChinese.rawValue:
            return "财务"
        default:
            return "Finances"
        }
    }
}
