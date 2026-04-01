import Foundation

enum QuickSetupLocalization {
    private static func normalizedFormatArgument(_ argument: any CVarArg) -> any CVarArg {
        switch argument {
        case let value as Int:
            return Int64(value)
        case let value as Int8:
            return Int64(value)
        case let value as Int16:
            return Int64(value)
        case let value as Int32:
            return Int64(value)
        case let value as UInt:
            return UInt64(value)
        case let value as UInt8:
            return UInt64(value)
        case let value as UInt16:
            return UInt64(value)
        case let value as UInt32:
            return UInt64(value)
        default:
            return argument
        }
    }

    static func tr(_ key: String, locale: Locale = AppLocalization.currentAppLocale, fallback: String? = nil) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
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
        let normalizedArguments = arguments.map(normalizedFormatArgument)
        return String(format: template, locale: locale, arguments: normalizedArguments)
    }
}
