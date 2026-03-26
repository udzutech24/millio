import Foundation
import SwiftUI

struct SubscriptionBenefitDescriptor: Identifiable, Equatable {
    let id: String
    let icon: String
    let titleKey: String
    let detailKey: String
}

enum SubscriptionContent {
    static let heroHighlights: [SubscriptionBenefitDescriptor] = []

    static let benefits: [SubscriptionBenefitDescriptor] = [
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
            id: "cashflow_expense_screenshot",
            icon: "photo.on.rectangle.angled",
            titleKey: "subscription.features.cashflow_expense_screenshot",
            detailKey: "subscription.features.cashflow_expense_screenshot.detail"
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
        )
    ]
}

/// Политика компоновки экрана подписки.
///
/// Важный инвариант: закреплённый снизу CTA добавляется через `safeAreaInset`, поэтому
/// ScrollView не должен дополнительно резервировать под него отдельную большую "подушку".
/// Иначе нижняя legal-секция визуально проваливается вверх, а между ней и CTA появляется дыра.
enum SubscriptionLayoutPolicy {
    static let horizontalPadding: CGFloat = 20
    static let topContentPadding: CGFloat = 12
    static let contentBottomPadding: CGFloat = BottomPinnedLayoutPolicy.compactContentBottomPadding

    static let ctaHorizontalPadding: CGFloat = 20
    static let ctaTopPadding: CGFloat = 10
    static let ctaBottomPadding: CGFloat = 8

    struct Metrics {
        let topSectionHeight: CGFloat
        let topSectionSpacing: CGFloat
        let sectionSpacing: CGFloat
        let heroHeight: CGFloat
        let heroCornerRadius: CGFloat
        let heroHorizontalPadding: CGFloat
        let heroVerticalPadding: CGFloat
        let heroContentSpacing: CGFloat
        let heroTitleSpacing: CGFloat
        let heroTextSpacing: CGFloat
        let heroArtTopPadding: CGFloat
        let crownGlowSize: CGFloat
        let crownWidth: CGFloat
        let crownHeight: CGFloat
        let eyebrowFontSize: CGFloat
        let heroTitleFontSize: CGFloat
        let heroSubtitleFontSize: CGFloat
        let planSectionSpacing: CGFloat
        let planEyebrowFontSize: CGFloat
        let planSubtitleFontSize: CGFloat
        let planFootnoteFontSize: CGFloat
        let planRowSpacing: CGFloat
        let plansCardPadding: CGFloat
        let planRowInnerSpacing: CGFloat
        let planRowHorizontalPadding: CGFloat
        let planRowVerticalPadding: CGFloat
        let planIndicatorSize: CGFloat
        let planCheckmarkFontSize: CGFloat
        let planTitleFontSize: CGFloat
        let planPriceFontSize: CGFloat
        let planPeriodFontSize: CGFloat
        let benefitsSectionSpacing: CGFloat
        let benefitsTitleFontSize: CGFloat
        let benefitsCardHorizontalPadding: CGFloat
        let benefitsCardVerticalPadding: CGFloat
        let benefitRowSpacing: CGFloat
        let benefitIconSize: CGFloat
        let benefitIconFontSize: CGFloat
        let benefitTitleFontSize: CGFloat
        let benefitDetailFontSize: CGFloat
        let benefitRowVerticalPadding: CGFloat
        let controlsSectionSpacing: CGFloat
        let legalSectionSpacing: CGFloat
        let legalLinkFontSize: CGFloat
        let legalNoteFontSize: CGFloat
        let restoreButtonFontSize: CGFloat
    }

    static func metrics(containerSize: CGSize) -> Metrics {
        let compactHeight = containerSize.height <= 760
        let wideScreen = containerSize.height >= 900
        let topSectionHeight = min(max(containerSize.height * 0.46, 328), 430)
        let heroHeight = min(max(containerSize.height * 0.27, 214), 278)

        return Metrics(
            topSectionHeight: topSectionHeight,
            topSectionSpacing: compactHeight ? 12 : 14,
            sectionSpacing: compactHeight ? 18 : 22,
            heroHeight: heroHeight,
            heroCornerRadius: wideScreen ? 36 : 32,
            heroHorizontalPadding: compactHeight ? 18 : 20,
            heroVerticalPadding: compactHeight ? 14 : 16,
            heroContentSpacing: compactHeight ? 10 : 12,
            heroTitleSpacing: compactHeight ? 10 : 12,
            heroTextSpacing: compactHeight ? 7 : 8,
            heroArtTopPadding: compactHeight ? 0 : 2,
            crownGlowSize: compactHeight ? 84 : 94,
            crownWidth: compactHeight ? 76 : 86,
            crownHeight: compactHeight ? 60 : 68,
            eyebrowFontSize: 11,
            heroTitleFontSize: compactHeight ? 31 : 34,
            heroSubtitleFontSize: compactHeight ? 14 : 15,
            planSectionSpacing: 10,
            planEyebrowFontSize: 13,
            planSubtitleFontSize: 13,
            planFootnoteFontSize: 11,
            planRowSpacing: 8,
            plansCardPadding: compactHeight ? 14 : 16,
            planRowInnerSpacing: compactHeight ? 10 : 12,
            planRowHorizontalPadding: 14,
            planRowVerticalPadding: compactHeight ? 12 : 13,
            planIndicatorSize: compactHeight ? 30 : 32,
            planCheckmarkFontSize: 13,
            planTitleFontSize: compactHeight ? 18 : 19,
            planPriceFontSize: compactHeight ? 19 : 20,
            planPeriodFontSize: 12,
            benefitsSectionSpacing: 10,
            benefitsTitleFontSize: compactHeight ? 22 : 24,
            benefitsCardHorizontalPadding: 16,
            benefitsCardVerticalPadding: compactHeight ? 6 : 8,
            benefitRowSpacing: 12,
            benefitIconSize: compactHeight ? 38 : 40,
            benefitIconFontSize: compactHeight ? 16 : 17,
            benefitTitleFontSize: compactHeight ? 15 : 16,
            benefitDetailFontSize: 12,
            benefitRowVerticalPadding: compactHeight ? 10 : 11,
            controlsSectionSpacing: compactHeight ? 12 : 14,
            legalSectionSpacing: compactHeight ? 12 : 14,
            legalLinkFontSize: 13,
            legalNoteFontSize: 12,
            restoreButtonFontSize: 15
        )
    }

    static func scrollContentBottomPadding(isSubscribed: Bool) -> CGFloat {
        BottomPinnedLayoutPolicy.scrollContentBottomPaddingForSafeAreaInset(
            minimumSpacing: contentBottomPadding
        )
    }
}
