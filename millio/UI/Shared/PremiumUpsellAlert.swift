//
//  PremiumUpsellAlert.swift
//  millio
//
//  Created by Assistant on 07.03.2026.
//

import SwiftUI

/// Premium upsell modal styled to match the subscription screen.
struct PremiumUpsellAlert: View {
    @Environment(AppState.self) private var appState
    @Binding var isPresented: Bool

    let titleKey: String
    let message: LocalizedTextResolver
    let onSubscribe: () -> Void
    let onCancel: () -> Void

    private var localizationLocale: Locale {
        AppLocalization.currentAppLocale
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { dismiss(notifyCancel: true) }

            alertCard
                .padding(.horizontal, 26)
                .transition(.scale.combined(with: .opacity))
        }
        .accessibilityAddTraits(.isModal)
    }

    private var alertCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(AppLocalization.string(titleKey, locale: localizationLocale))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message.resolve(in: localizationLocale))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                subscribeButton
                cancelButton
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
        .frame(maxWidth: 420)
        .background {
            GlassBackground(
                gradient: AppColors.premiumGradient,
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

    private var subscribeButton: some View {
        Button {
            dismiss(notifyCancel: false)
            onSubscribe()
        } label: {
            Text(String(localized: "subscription.button.subscribe", locale: localizationLocale))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "2A8CFF"), Color(hex: "4B76FF"), Color(hex: "7D72FF")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .clipShape(Capsule())
                .shadow(color: Color(hex: "2A8CFF").opacity(0.24), radius: 14, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    private var cancelButton: some View {
        Button {
            dismiss(notifyCancel: true)
        } label: {
            Text(String(localized: "finances.common.cancel", locale: localizationLocale))
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
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            isPresented = false
        }
        if notifyCancel {
            onCancel()
        }
    }
}

private struct PremiumUpsellAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let titleKey: String
    let message: LocalizedTextResolver
    let onSubscribe: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    PremiumUpsellAlert(
                        isPresented: $isPresented,
                        titleKey: titleKey,
                        message: message,
                        onSubscribe: onSubscribe,
                        onCancel: onCancel
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: isPresented)
    }
}

extension View {
    func premiumUpsellAlert(
        isPresented: Binding<Bool>,
        titleKey: String,
        message: LocalizedTextResolver,
        onSubscribe: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            PremiumUpsellAlertModifier(
                isPresented: isPresented,
                titleKey: titleKey,
                message: message,
                onSubscribe: onSubscribe,
                onCancel: onCancel
            )
        )
    }

    func premiumUpsellAlert(
        isPresented: Binding<Bool>,
        titleKey: String,
        messageKey: String,
        onSubscribe: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        premiumUpsellAlert(
            isPresented: isPresented,
            titleKey: titleKey,
            message: .key(messageKey),
            onSubscribe: onSubscribe,
            onCancel: onCancel
        )
    }
}
