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
    static func degradedRefreshMessage(locale: Locale = AppLocalization.currentAppLocale) -> String {
        FinancesL10n.tr("finances.market.refresh.degraded_message", locale: locale)
    }

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

    static func message(for category: MarketDataIssueCategory, locale: Locale = AppLocalization.currentAppLocale) -> String {
        switch category {
        case .notFound:
            return FinancesL10n.tr("finances.market.error.not_found", locale: locale)
        case .priceUnavailable:
            return FinancesL10n.tr("finances.market.error.price_unavailable", locale: locale)
        case .providerError:
            return degradedRefreshMessage(locale: locale)
        case .authError:
            return FinancesL10n.tr("finances.market.error.auth", locale: locale)
        case .networkError:
            return degradedRefreshMessage(locale: locale)
        case .httpError:
            return degradedRefreshMessage(locale: locale)
        case .decodeError:
            return degradedRefreshMessage(locale: locale)
        case .clientError:
            return degradedRefreshMessage(locale: locale)
        }
    }

    static func listLabel(for category: MarketDataIssueCategory, locale: Locale = AppLocalization.currentAppLocale) -> String {
        switch category {
        case .notFound:
            return FinancesL10n.tr("finances.market.list.not_found", locale: locale)
        case .priceUnavailable:
            return FinancesL10n.tr("finances.market.list.price_unavailable", locale: locale)
        case .providerError:
            return FinancesL10n.tr("finances.market.list.provider_error", locale: locale)
        case .authError:
            return FinancesL10n.tr("finances.market.list.auth_error", locale: locale)
        case .networkError:
            return FinancesL10n.tr("finances.market.list.network_error", locale: locale)
        case .httpError:
            return FinancesL10n.tr("finances.market.list.http_error", locale: locale)
        case .decodeError:
            return FinancesL10n.tr("finances.market.list.decode_error", locale: locale)
        case .clientError:
            return FinancesL10n.tr("finances.market.list.client_error", locale: locale)
        }
    }
}
