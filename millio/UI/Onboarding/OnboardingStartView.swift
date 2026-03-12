import SwiftUI

struct OnboardingStartView: View {
    let locale: Locale
    let onStart: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            onboardingBackground

            VStack(alignment: .leading, spacing: 20) {
                Text(OnboardingStartCopy.badge(locale: locale))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.08))
                            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                    )

                VStack(alignment: .leading, spacing: 10) {
                    Text(OnboardingStartCopy.title(locale: locale))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(OnboardingStartCopy.subtitle(locale: locale))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(OnboardingStartCopy.checkpoints(locale: locale), id: \.self) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppColors.brandPrimary)
                            Text(item)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(.white.opacity(0.08), lineWidth: 1)
                        )
                )

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button(action: onStart) {
                        Text(OnboardingStartCopy.primaryAction(locale: locale))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(primaryButtonBackground)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.startQuickSetupButton")

                    Button(action: onSkip) {
                        Text(OnboardingStartCopy.secondaryAction(locale: locale))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(.white.opacity(0.08), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.skipToWorkspaceButton")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            .padding(.bottom, 20)
        }
    }

    private var onboardingBackground: some View {
        ZStack {
            GradientBackground()
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.05, blue: 0.1), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppColors.brandPrimary.opacity(0.2))
                .frame(width: 340, height: 340)
                .blur(radius: 130)
                .offset(x: -120, y: -260)

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 120)
                .offset(x: 160, y: -160)
        }
        .ignoresSafeArea()
    }

    private var primaryButtonBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [AppColors.brandPrimary.opacity(0.34), Color.cyan.opacity(0.2), Color.black.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [AppColors.brandPrimary, Color.cyan.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

#Preview {
    OnboardingStartView(
        locale: Locale(identifier: "ru_RU"),
        onStart: {},
        onSkip: {}
    )
}
