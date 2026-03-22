import CoreGraphics

struct AuthWelcomeLayoutMetrics: Equatable {
    let horizontalPadding: CGFloat
    let bottomPadding: CGFloat
    let topPadding: CGFloat
    let topSpacerMinLength: CGFloat
    let headerToCardSpacing: CGFloat
    let sectionSpacing: CGFloat
    let headerSpacing: CGFloat
    let heroSpacing: CGFloat
    let actionSpacing: CGFloat

    let badgeHorizontalPadding: CGFloat
    let badgeVerticalPadding: CGFloat
    let badgeIconSize: CGFloat
    let badgeTracking: CGFloat

    let cardCornerRadius: CGFloat
    let cardPaddingTop: CGFloat
    let cardPaddingHorizontal: CGFloat
    let cardPaddingBottom: CGFloat

    let heroTitleScale: CGFloat
    let brandTitleScale: CGFloat
    let subtitleScale: CGFloat

    let primaryButtonHeight: CGFloat
    let secondaryButtonHeight: CGFloat
    let buttonCornerRadius: CGFloat
}

enum AuthWelcomeLayoutPolicy {
    /// Keeps the auth welcome screen on a single page by progressively tightening spacing and typography.
    static func metrics(containerSize: CGSize) -> AuthWelcomeLayoutMetrics {
        let isShortHeight = containerSize.height <= 700
        let isMediumHeight = containerSize.height <= 780
        let isNarrowWidth = containerSize.width <= 350

        if isShortHeight || (isMediumHeight && isNarrowWidth) {
            return AuthWelcomeLayoutMetrics(
                horizontalPadding: 16,
                bottomPadding: 12,
                topPadding: 8,
                topSpacerMinLength: 8,
                headerToCardSpacing: 10,
                sectionSpacing: 16,
                headerSpacing: 10,
                heroSpacing: 10,
                actionSpacing: 10,
                badgeHorizontalPadding: 12,
                badgeVerticalPadding: 8,
                badgeIconSize: 13,
                badgeTracking: 1.2,
                cardCornerRadius: 24,
                cardPaddingTop: 18,
                cardPaddingHorizontal: 18,
                cardPaddingBottom: 16,
                heroTitleScale: 0.78,
                brandTitleScale: 0.9,
                subtitleScale: 0.94,
                primaryButtonHeight: 48,
                secondaryButtonHeight: 46,
                buttonCornerRadius: 14
            )
        }

        if isMediumHeight || isNarrowWidth {
            return AuthWelcomeLayoutMetrics(
                horizontalPadding: 18,
                bottomPadding: 16,
                topPadding: 10,
                topSpacerMinLength: 12,
                headerToCardSpacing: 12,
                sectionSpacing: 20,
                headerSpacing: 12,
                heroSpacing: 12,
                actionSpacing: 12,
                badgeHorizontalPadding: 13,
                badgeVerticalPadding: 9,
                badgeIconSize: 14,
                badgeTracking: 1.4,
                cardCornerRadius: 26,
                cardPaddingTop: 22,
                cardPaddingHorizontal: 20,
                cardPaddingBottom: 18,
                heroTitleScale: 0.9,
                brandTitleScale: 0.95,
                subtitleScale: 0.97,
                primaryButtonHeight: 50,
                secondaryButtonHeight: 48,
                buttonCornerRadius: 14
            )
        }

        return AuthWelcomeLayoutMetrics(
            horizontalPadding: 20,
            bottomPadding: 18,
            topPadding: 12,
            topSpacerMinLength: 20,
            headerToCardSpacing: 12,
            sectionSpacing: 24,
            headerSpacing: 14,
            heroSpacing: 14,
            actionSpacing: 12,
            badgeHorizontalPadding: 14,
            badgeVerticalPadding: 10,
            badgeIconSize: 14,
            badgeTracking: 1.6,
            cardCornerRadius: 28,
            cardPaddingTop: 24,
            cardPaddingHorizontal: 22,
            cardPaddingBottom: 20,
            heroTitleScale: 1,
            brandTitleScale: 1,
            subtitleScale: 1,
            primaryButtonHeight: 52,
            secondaryButtonHeight: 50,
            buttonCornerRadius: 14
        )
    }
}
