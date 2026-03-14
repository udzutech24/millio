import SwiftUI

struct RateAppBlock: View {
    let canOpenAppStoreReview: Bool
    let onRateInAppStore: () -> Void
    let onSendFeedback: () -> Void

    @State private var rating: Int = 0
    @State private var activePrompt: Prompt?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("profile.rate_app.block.eyebrow")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.brandPrimary.opacity(0.9))
                    .kerning(1.1)
                    .textCase(.uppercase)

                Text("profile.rate_app.block.title")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)

                Text("profile.rate_app.block.subtitle")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                ratingSummary

                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                rating = star
                                activePrompt = star == 5 ? .rateInAppStore : .sendFeedback
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(starBackground(for: star))
                                    .overlay(
                                        Circle()
                                            .stroke(starStroke(for: star), lineWidth: star <= rating ? 1.2 : 0.8)
                                    )
                                    .frame(width: 44, height: 44)

                                Image(systemName: star <= rating ? "star.fill" : "star")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(star <= rating ? Color.white : AppColors.brandPrimary.opacity(0.9))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .scaleEffect(star == rating ? 1.08 : 1.0)
                            .shadow(color: star <= rating ? AppColors.brandPrimary.opacity(0.22) : .clear, radius: 10, y: 6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("profile.rate_app.star"))
                        .accessibilityValue(Text("\(star)"))
                        .accessibilityHint(Text("profile.rate_app.star_hint"))
                    }

                    Spacer(minLength: 0)
                }
            }

            if let activePrompt {
                promptCard(for: activePrompt)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 0.98))
                        )
                    )
            }
        }
    }

    private var ratingSummary: some View {
        HStack(spacing: 10) {
            Image(systemName: rating == 0 ? "sparkles" : "heart.text.square.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.brandPrimary)

            Text(ratingSummaryKey)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            Spacer(minLength: 0)

            if rating > 0 {
                Text("\(rating)/5")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppColors.brandPrimary.opacity(0.24), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            AppColors.accentDarkBlue.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppColors.brandPrimary.opacity(0.16), lineWidth: 1)
        )
    }

    private func promptCard(for prompt: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(prompt.iconBackground)
                        .frame(width: 42, height: 42)

                    Image(systemName: prompt.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(prompt.iconColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(prompt.titleKey)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text(prompt.messageKey(canOpenAppStoreReview: canOpenAppStoreReview))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(prompt.gratitudeKey)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.brandPrimary.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    handlePrimaryAction(for: prompt)
                } label: {
                    Text(prompt.primaryActionTitle(canOpenAppStoreReview: canOpenAppStoreReview))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AppColors.brandPrimary.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(AppColors.brandPrimary.opacity(0.28), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                        activePrompt = nil
                    }
                } label: {
                    Text("profile.rate_app.not_now")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.035),
                            AppColors.accentDarkBlue.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(prompt.borderColor, lineWidth: 1)
                )
        )
        .shadow(color: prompt.shadowColor, radius: 18, y: 12)
    }

    private func handlePrimaryAction(for prompt: Prompt) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            activePrompt = nil
        }

        switch prompt {
        case .rateInAppStore:
            onRateInAppStore()
        case .sendFeedback:
            onSendFeedback()
        }
    }

    private func starBackground(for star: Int) -> some ShapeStyle {
        if star <= rating {
            return LinearGradient(
                colors: [
                    AppColors.brandPrimary.opacity(0.22),
                    AppColors.brandPrimary.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(0.06),
                Color.white.opacity(0.03)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func starStroke(for star: Int) -> Color {
        star <= rating ? AppColors.brandPrimary.opacity(0.32) : Color.white.opacity(0.08)
    }

    private var ratingSummaryKey: LocalizedStringKey {
        switch rating {
        case 5:
            return "profile.rate_app.summary.excellent"
        case 4:
            return "profile.rate_app.summary.good"
        case 1...3:
            return "profile.rate_app.summary.feedback"
        default:
            return "profile.rate_app.summary.idle"
        }
    }
}

private extension RateAppBlock {
    enum Prompt {
        case rateInAppStore
        case sendFeedback

        var iconName: String {
            switch self {
            case .rateInAppStore:
                return "sparkles"
            case .sendFeedback:
                return "bubble.left.and.bubble.right.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .rateInAppStore:
                return Color.white
            case .sendFeedback:
                return AppColors.textPrimary
            }
        }

        var iconBackground: Color {
            switch self {
            case .rateInAppStore:
                return AppColors.brandPrimary.opacity(0.16)
            case .sendFeedback:
                return Color.white.opacity(0.06)
            }
        }

        var borderColor: Color {
            switch self {
            case .rateInAppStore:
                return AppColors.brandPrimary.opacity(0.28)
            case .sendFeedback:
                return Color.white.opacity(0.12)
            }
        }

        var shadowColor: Color {
            switch self {
            case .rateInAppStore:
                return AppColors.brandPrimary.opacity(0.18)
            case .sendFeedback:
                return Color.black.opacity(0.22)
            }
        }

        var titleKey: LocalizedStringKey {
            switch self {
            case .rateInAppStore:
                return "profile.rate_app.dialog.rate.title"
            case .sendFeedback:
                return "profile.rate_app.dialog.feedback.title"
            }
        }

        func messageKey(canOpenAppStoreReview: Bool) -> LocalizedStringKey {
            switch self {
            case .rateInAppStore:
                return canOpenAppStoreReview
                    ? "profile.rate_app.dialog.rate.message.app_store"
                    : "profile.rate_app.dialog.rate.message.in_app"
            case .sendFeedback:
                return "profile.rate_app.dialog.feedback.message"
            }
        }

        var gratitudeKey: LocalizedStringKey {
            switch self {
            case .rateInAppStore:
                return "profile.rate_app.dialog.rate.gratitude"
            case .sendFeedback:
                return "profile.rate_app.dialog.feedback.gratitude"
            }
        }

        func primaryActionTitle(canOpenAppStoreReview: Bool) -> LocalizedStringKey {
            switch self {
            case .rateInAppStore:
                return canOpenAppStoreReview
                    ? "profile.rate_app.dialog.rate.action.app_store"
                    : "profile.rate_app.dialog.rate.action.in_app"
            case .sendFeedback:
                return "profile.rate_app.dialog.feedback.action"
            }
        }
    }
}
