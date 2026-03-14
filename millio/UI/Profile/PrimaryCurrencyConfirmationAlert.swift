//
//  PrimaryCurrencyConfirmationAlert.swift
//  millio
//
//  Created by Assistant on 14.03.2026.
//

import SwiftUI

struct PrimaryCurrencyConfirmationContent: Equatable {
    let locale: Locale
    let pendingCode: String

    var title: String {
        isRussian
            ? "Изменить основную валюту?"
            : "Change primary currency?"
    }

    var message: String {
        AppLocalization.string(
            "profile.primary_currency.change_message",
            locale: locale,
            fallback: isRussian
                ? "Это обновит основную валюту приложения и валюты отображения, которые следуют за основной валютой"
                : "This updates the app primary currency and display currencies that follow the primary currency"
        )
        .trimmingTrailingSentencePeriod()
    }

    var confirmTitle: String {
        let format = AppLocalization.string(
            "profile.primary_currency.change_to_format",
            locale: locale,
            fallback: isRussian ? "Изменить на %@" : "Change to %@"
        )
        return String(format: format, pendingCode)
    }

    var cancelTitle: String {
        AppLocalization.string(
            "finances.common.cancel",
            locale: locale,
            fallback: isRussian ? "Отмена" : "Cancel"
        )
    }

    var badgeTitle: String {
        isRussian ? "Новая основная валюта" : "New primary currency"
    }

    var currencyName: String {
        if isRussian {
            return CurrencySelectionSupport.nameRu(for: pendingCode) ?? pendingCode
        }
        return CurrencySelectionSupport.nameEn(for: pendingCode) ?? pendingCode
    }

    private var isRussian: Bool {
        if #available(iOS 16.0, *),
           let code = locale.language.languageCode?.identifier.lowercased() {
            return code == "ru"
        }

        return locale.identifier
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased() == "ru"
    }
}

struct PrimaryCurrencyConfirmationAlert: View {
    @Binding var isPresented: Bool
    let content: PrimaryCurrencyConfirmationContent
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @State private var isCardVisible = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss(notifyCancel: true)
                }

            alertCard
                .padding(.horizontal, 24)
                .scaleEffect(isCardVisible ? 1 : 0.96)
                .opacity(isCardVisible ? 1 : 0)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isCardVisible = true
            }
        }
    }

    private var alertCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                headerIcon

                currencyBadge

                Text(content.title)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(content.message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                confirmButton
                cancelButton
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .frame(maxWidth: 420)
        .background {
            GlassBackground(
                gradient: AppColors.financesGradient,
                cornerRadius: 28,
                strokeWidth: 1
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 16)
    }

    private var headerIcon: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppColors.brandPrimary.opacity(0.30),
                            AppColors.brandPrimary.opacity(0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 34
                    )
                )
                .frame(width: 64, height: 64)

            Circle()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .frame(width: 50, height: 50)

            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: AppColors.financesGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .padding(.bottom, 2)
    }

    private var currencyBadge: some View {
        HStack(spacing: 12) {
            PrimaryCurrencyFlagIcon(code: content.pendingCode, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(content.badgeTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary.opacity(0.9))

                HStack(spacing: 8) {
                    Text(content.pendingCode)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text(content.currencyName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColors.brandPrimary.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private var confirmButton: some View {
        Button {
            dismiss(notifyCancel: false)
            onConfirm()
        } label: {
            Text(content.confirmTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: AppColors.financesGradient,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .clipShape(Capsule())
                .shadow(color: AppColors.brandPrimary.opacity(0.24), radius: 14, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    private var cancelButton: some View {
        Button {
            dismiss(notifyCancel: true)
        } label: {
            Text(content.cancelTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func dismiss(notifyCancel: Bool) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.92)) {
            isCardVisible = false
        }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            isPresented = false
        }
        if notifyCancel {
            onCancel()
        }
    }
}

private struct PrimaryCurrencyConfirmationAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let content: PrimaryCurrencyConfirmationContent?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    func body(content base: Content) -> some View {
        base
            .overlay {
                if isPresented, let alertContent = content {
                    PrimaryCurrencyConfirmationAlert(
                        isPresented: $isPresented,
                        content: alertContent,
                        onConfirm: onConfirm,
                        onCancel: onCancel
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: isPresented)
    }
}

extension View {
    func primaryCurrencyConfirmationAlert(
        isPresented: Binding<Bool>,
        content: PrimaryCurrencyConfirmationContent?,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(
            PrimaryCurrencyConfirmationAlertModifier(
                isPresented: isPresented,
                content: content,
                onConfirm: onConfirm,
                onCancel: onCancel
            )
        )
    }
}

private extension String {
    func trimmingTrailingSentencePeriod() -> String {
        guard let last else { return self }
        guard [".", "。"].contains(String(last)) else { return self }
        return String(dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct PrimaryCurrencyFlagIcon: View {
    let code: String
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(Color(hex: "141A25"))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                        .stroke(AppColors.brandPrimary.opacity(0.28), lineWidth: 1)
                )

            if let assetName = CurrencyFlags.assetName(for: code) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.42, height: size * 0.42)
            } else {
                let fallbackEmoji = CurrencyFlags.flag(for: code)
                if fallbackEmoji != "🏳️" {
                    Text(fallbackEmoji)
                        .font(.system(size: size * 0.26))
                } else {
                    Image("flag")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: size * 0.34, height: size * 0.34)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
