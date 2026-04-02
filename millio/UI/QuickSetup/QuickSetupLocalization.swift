import Foundation

enum QuickSetupLocalization {
    /// Quick setup copy is formatter-heavy and must remain stable across
    /// localized catalogs, including positional placeholders from xcstrings.
    private enum FormatArgument {
        case string(String)
        case integer(Int64)
    }

    private static func normalizedFormatArgument(_ argument: any CVarArg) -> FormatArgument? {
        switch argument {
        case let value as String:
            return .string(value)
        case let value as NSString:
            return .string(value as String)
        case let value as Int:
            return .integer(Int64(value))
        case let value as Int8:
            return .integer(Int64(value))
        case let value as Int16:
            return .integer(Int64(value))
        case let value as Int32:
            return .integer(Int64(value))
        case let value as Int64:
            return .integer(value)
        case let value as UInt:
            return .integer(Int64(clamping: value))
        case let value as UInt8:
            return .integer(Int64(value))
        case let value as UInt16:
            return .integer(Int64(value))
        case let value as UInt32:
            return .integer(Int64(value))
        case let value as UInt64:
            return .integer(Int64(clamping: value))
        case let value as NSNumber:
            return .integer(value.int64Value)
        default:
            return .string(String(describing: argument))
        }
    }

    private static func formattedValue(for argument: FormatArgument, placeholderType: String) -> String? {
        switch (argument, placeholderType) {
        case let (.string(value), "@"):
            return value
        case let (.integer(value), "d"):
            return String(value)
        case let (.integer(value), "ld"):
            return String(value)
        case let (.integer(value), "lld"):
            return String(value)
        case let (.integer(value), "@"):
            return String(value)
        case let (.string(value), "d"),
             let (.string(value), "ld"),
             let (.string(value), "lld"):
            return value
        default:
            return nil
        }
    }

    private static func safeFormat(_ template: String, arguments: [FormatArgument]) -> String {
        guard let regex = try? NSRegularExpression(pattern: "%(?:(\\d+)\\$)?((?:ll)?d|@)") else {
            return template
        }

        let nsTemplate = template as NSString
        let matches = regex.matches(
            in: template,
            range: NSRange(location: 0, length: nsTemplate.length)
        )

        guard !matches.isEmpty else {
            return template
        }

        typealias ReplacementPlan = (range: NSRange, replacement: String)
        var replacementPlans: [ReplacementPlan] = []
        var nextImplicitIndex = 0

        for match in matches {
            let matchedRange = match.range(at: 0)
            guard matchedRange.location != NSNotFound else {
                continue
            }

            let placeholderIndex: Int
            let explicitIndexRange = match.range(at: 1)
            if explicitIndexRange.location != NSNotFound {
                let explicitIndex = nsTemplate.substring(with: explicitIndexRange)
                guard let parsedIndex = Int(explicitIndex), parsedIndex > 0 else {
                    continue
                }
                placeholderIndex = parsedIndex - 1
            } else {
                placeholderIndex = nextImplicitIndex
                nextImplicitIndex += 1
            }

            guard arguments.indices.contains(placeholderIndex) else {
                continue
            }

            let placeholderType = nsTemplate.substring(with: match.range(at: 2))
            guard let replacement = formattedValue(
                for: arguments[placeholderIndex],
                placeholderType: placeholderType
            ) else {
                continue
            }

            replacementPlans.append((range: matchedRange, replacement: replacement))
        }

        let result = NSMutableString(string: template)
        for plan in replacementPlans.reversed() {
            result.replaceCharacters(in: plan.range, with: plan.replacement)
        }

        return result as String
    }

    static func tr(_ key: String, locale: Locale = AppLocalization.currentAppLocale, fallback: String? = nil) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
    }

    static func stepProgress(current: Int, total: Int, locale: Locale = AppLocalization.currentAppLocale) -> String {
        format(
            "quick_setup.step_progress_format",
            locale: locale,
            fallback: "Step %1$lld of %2$lld",
            current,
            total
        )
    }

    static func primaryCurrencyBadge(_ currencyCode: String, locale: Locale = AppLocalization.currentAppLocale) -> String {
        let title = tr("quick_setup.common.primary", locale: locale)
        return "\(title): \(currencyCode)"
    }

    static func favoritesCountBadge(selectedCount: Int, maxCount: Int, locale: Locale = AppLocalization.currentAppLocale) -> String {
        format(
            "quick_setup.badge.favorites_count_format",
            locale: locale,
            fallback: "Favorites: %1$lld/%2$lld",
            selectedCount,
            maxCount
        )
    }

    static func selectedCategoriesCount(_ count: Int, locale: Locale = AppLocalization.currentAppLocale) -> String {
        format(
            "quick_setup.selected_categories_count_format",
            locale: locale,
            fallback: "Selected: %lld",
            count
        )
    }

    static func addedProductsCount(_ count: Int, locale: Locale = AppLocalization.currentAppLocale) -> String {
        format(
            "quick_setup.added_products_count_format",
            locale: locale,
            fallback: "Added: %lld",
            count
        )
    }

    static func format(
        _ key: String,
        locale: Locale = AppLocalization.currentAppLocale,
        fallback: String? = nil,
        _ args: CVarArg...
    ) -> String {
        formatArguments(key, locale: locale, fallback: fallback, arguments: args)
    }

    static func formatArguments(
        _ key: String,
        locale: Locale = AppLocalization.currentAppLocale,
        fallback: String? = nil,
        arguments: [CVarArg]
    ) -> String {
        let template = tr(key, locale: locale, fallback: fallback)
        guard !template.isEmpty, !arguments.isEmpty else {
            return template
        }
        let normalizedArguments = arguments.compactMap(normalizedFormatArgument)
        guard normalizedArguments.count == arguments.count else {
            return template
        }
        return safeFormat(template, arguments: normalizedArguments)
    }
}
