import Foundation

struct SubscriptionBenefitDescriptor: Identifiable, Equatable {
    let id: String
    let icon: String
    let titleKey: String
    let detailKey: String
}

enum SubscriptionContent {
    static let heroHighlights: [SubscriptionBenefitDescriptor] = [
        .init(
            id: "crypto",
            icon: "bitcoinsign.circle.fill",
            titleKey: "subscription.hero.highlight.crypto.title",
            detailKey: "subscription.hero.highlight.crypto.detail"
        ),
        .init(
            id: "cashback",
            icon: "text.viewfinder",
            titleKey: "subscription.hero.highlight.cashback.title",
            detailKey: "subscription.hero.highlight.cashback.detail"
        ),
        .init(
            id: "charts",
            icon: "chart.bar.fill",
            titleKey: "subscription.hero.highlight.charts.title",
            detailKey: "subscription.hero.highlight.charts.detail"
        )
    ]

    static let benefits: [SubscriptionBenefitDescriptor] = [
        .init(
            id: "crypto_converter",
            icon: "bitcoinsign.circle.fill",
            titleKey: "subscription.features.crypto_converter",
            detailKey: "subscription.features.crypto_converter.detail"
        ),
        .init(
            id: "finance_markets",
            icon: "chart.line.uptrend.xyaxis",
            titleKey: "subscription.features.finance_markets",
            detailKey: "subscription.features.finance_markets.detail"
        ),
        .init(
            id: "tracked_tickers",
            icon: "number.circle.fill",
            titleKey: "subscription.features.unlimited_tickers",
            detailKey: "subscription.features.unlimited_tickers.detail"
        ),
        .init(
            id: "finance_products",
            icon: "tray.full.fill",
            titleKey: "subscription.features.finance_products",
            detailKey: "subscription.features.finance_products.detail"
        ),
        .init(
            id: "finance_charts",
            icon: "chart.bar.fill",
            titleKey: "subscription.features.finance_charts",
            detailKey: "subscription.features.finance_charts.detail"
        ),
        .init(
            id: "cashback_screenshot",
            icon: "text.viewfinder",
            titleKey: "subscription.features.cashback_screenshot",
            detailKey: "subscription.features.cashback_screenshot.detail"
        ),
        .init(
            id: "cashback_categories",
            icon: "list.bullet.rectangle.portrait",
            titleKey: "subscription.features.cashback_categories",
            detailKey: "subscription.features.cashback_categories.detail"
        ),
        .init(
            id: "cashback_cards",
            icon: "creditcard.fill",
            titleKey: "subscription.features.more_cashback_cards",
            detailKey: "subscription.features.more_cashback_cards.detail"
        )
    ]
}
