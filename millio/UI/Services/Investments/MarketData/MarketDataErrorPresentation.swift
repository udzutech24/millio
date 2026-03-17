import Foundation

enum MarketDataIssueCategory: String, Sendable {
    case notFound = "not_found"
    case priceUnavailable = "price_unavailable"
    case providerError = "provider_error"
    case authError = "auth_error"
    case networkError = "network_error"
    case httpError = "http_error"
    case decodeError = "decode_error"
    case clientError = "client_error"
}

enum MarketDataErrorPresentation {
    static func category(for quote: AssetSummary) -> MarketDataIssueCategory? {
        switch quote.resolutionStatus {
        case .fresh, .stale:
            guard let price = quote.price, price > 0 else {
                return .priceUnavailable
            }
            return nil
        case .notFound:
            return .notFound
        case .providerError:
            return .providerError
        }
    }

    static func category(for error: Error) -> MarketDataIssueCategory {
        if let marketError = error as? MarketAPIClientError {
            switch marketError {
            case .unauthorized:
                return .authError
            case .transport:
                return .networkError
            case .backend(let statusCode, _, _):
                return (statusCode == 401 || statusCode == 403) ? .authError : .httpError
            case .decodingFailed:
                return .decodeError
            case .invalidConfiguration, .unconfigured:
                return .clientError
            }
        }

        if let authError = error as? AuthServiceError {
            switch authError {
            case .notAuthenticated,
                 .unauthorized,
                 .forbidden,
                 .unconfigured:
                return .authError
            case .transport:
                return .networkError
            case .backend,
                 .server,
                 .rateLimited,
                 .invalidResponse:
                return .httpError
            case .decodingFailed:
                return .decodeError
            case .invalidConfiguration,
                 .invalidIdentityToken,
                 .unexpectedAuthorizationCredential,
                 .tokenPersistenceFailed:
                return .clientError
            }
        }

        if error is URLError {
            return .networkError
        }

        return .clientError
    }

    static func requestID(for error: Error) -> String? {
        if let marketError = error as? MarketAPIClientError {
            return marketError.requestId
        }

        if let authError = error as? AuthServiceError {
            return authError.requestId
        }

        return nil
    }

    static func message(for category: MarketDataIssueCategory, locale: Locale = .current) -> String {
        switch category {
        case .notFound:
            return FinancesL10n.text(locale: locale, ru: "Тикер не найден", en: "Stock symbol not found")
        case .priceUnavailable:
            return FinancesL10n.text(locale: locale, ru: "Нет текущей цены", en: "Current price unavailable")
        case .providerError:
            return FinancesL10n.text(locale: locale, ru: "Ошибка провайдера котировок", en: "Quote provider error")
        case .authError:
            return FinancesL10n.text(locale: locale, ru: "Ошибка авторизации backend котировок", en: "Quote backend auth error")
        case .networkError:
            return FinancesL10n.text(locale: locale, ru: "Сетевая ошибка загрузки котировки", en: "Network error while loading quote")
        case .httpError:
            return FinancesL10n.text(locale: locale, ru: "HTTP ошибка backend котировок", en: "Quote backend HTTP error")
        case .decodeError:
            return FinancesL10n.text(locale: locale, ru: "Некорректный ответ backend котировок", en: "Invalid quote backend response")
        case .clientError:
            return FinancesL10n.text(locale: locale, ru: "Ошибка клиента котировок", en: "Quote client error")
        }
    }

    static func listLabel(for category: MarketDataIssueCategory, locale: Locale = .current) -> String {
        switch category {
        case .notFound:
            return FinancesL10n.text(locale: locale, ru: "Не найдены тикеры", en: "Missing stock symbols")
        case .priceUnavailable:
            return FinancesL10n.text(locale: locale, ru: "Нет текущей цены", en: "Current price unavailable")
        case .providerError:
            return FinancesL10n.text(locale: locale, ru: "Ошибка провайдера котировок", en: "Quote provider error")
        case .authError:
            return FinancesL10n.text(locale: locale, ru: "Ошибка авторизации backend котировок", en: "Quote backend auth error")
        case .networkError:
            return FinancesL10n.text(locale: locale, ru: "Сетевая ошибка загрузки котировок", en: "Network error while loading quotes")
        case .httpError:
            return FinancesL10n.text(locale: locale, ru: "HTTP ошибка backend котировок", en: "Quote backend HTTP error")
        case .decodeError:
            return FinancesL10n.text(locale: locale, ru: "Некорректный ответ backend котировок", en: "Invalid quote backend response")
        case .clientError:
            return FinancesL10n.text(locale: locale, ru: "Ошибка клиента котировок", en: "Quote client error")
        }
    }
}
