//
//  AppLockScreenView.swift
//  millio
//
//  Created by Александр Сидоркин on 21.02.2026.
//

import SwiftUI

struct AppLockScreenView: View {
    @Environment(AppState.self) private var appState
    let tryBiometricUnlock: () async -> Bool

    @State private var enteredPin = ""
    @State private var errorText: String?
    @State private var isBiometricBusy = false

    private var locale: Locale {
        AppLocalization.currentAppLocale
    }

    var body: some View {
        ZStack {
            GradientBackground()
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.xl) {
                Spacer(minLength: AppSpacing.xxxl)

                Image(systemName: "lock.shield.fill")
                    .font(.millioDisplayLarge)
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.incomeGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text(localized("profile.app_lock.screen.title", fallback: "Enter PIN code"))
                    .font(.millioTitle)
                    .foregroundStyle(AppColors.textPrimary)

                pinDots

                if let errorText {
                    Text(errorText)
                        .font(.millioCalloutRegular)
                        .foregroundStyle(AppColors.error)
                }

                pinPad

                if canUseBiometricButton {
                    Button {
                        Task { await unlockWithBiometrics() }
                    } label: {
                        HStack(spacing: AppSpacing.s) {
                            if isBiometricBusy {
                                ProgressView()
                                    .scaleEffect(0.85)
                            }
                            Text(AppLockBiometricAuth.buttonTitle())
                                .font(.millioSubheadlineMedium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.m)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isBiometricBusy)
                    .padding(.top, AppSpacing.s)
                }

                Spacer(minLength: AppSpacing.xxl)
            }
            .padding(.horizontal, AppSpacing.xxl)
        }
        .task {
            if canUseBiometricButton {
                await unlockWithBiometrics()
            }
        }
    }

    private var canUseBiometricButton: Bool {
        appState.isBiometricUnlockEnabled && AppLockBiometricAuth.canUseBiometrics()
    }

    private var pinDots: some View {
        HStack(spacing: AppSpacing.ml) {
            ForEach(0..<4, id: \.self) { idx in
                Circle()
                    .fill(idx < enteredPin.count ? AppColors.brandPrimary : AppColors.textPrimary.opacity(0.25))
                    .frame(width: 14, height: 14)
            }
        }
        .frame(height: 30)
    }

    private var pinPad: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: AppSpacing.ml), count: 3)
        let values = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

        return LazyVGrid(columns: columns, spacing: AppSpacing.ml) {
            ForEach(values, id: \.self) { value in
                if value.isEmpty {
                    Color.clear
                        .frame(height: 56)
                } else {
                    Button {
                        handleKey(value)
                    } label: {
                        Text(value)
                            .font(.millioTitle2)
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, AppSpacing.s)
    }

    private func handleKey(_ key: String) {
        errorText = nil
        if key == "⌫" {
            guard !enteredPin.isEmpty else { return }
            enteredPin.removeLast()
            return
        }
        guard enteredPin.count < 4, key.allSatisfy(\.isNumber) else { return }
        enteredPin.append(key)
        guard enteredPin.count == 4 else { return }

        if AppLockPinStore.shared.verify(pin: enteredPin) {
            appState.isAppLocked = false
            enteredPin = ""
        } else {
            errorText = localized("profile.app_lock.error.invalid_pin", fallback: "Incorrect PIN")
            enteredPin = ""
        }
    }

    private func unlockWithBiometrics() async {
        guard canUseBiometricButton, !isBiometricBusy else { return }
        isBiometricBusy = true
        defer { isBiometricBusy = false }
        if await tryBiometricUnlock() {
            appState.isAppLocked = false
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
    }
}

#Preview {
    AppLockScreenView(tryBiometricUnlock: { false })
        .environment(AppState())
}
