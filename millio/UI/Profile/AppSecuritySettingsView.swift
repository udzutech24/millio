//
//  AppSecuritySettingsView.swift
//  millio
//
//  Created by Александр Сидоркин on 21.02.2026.
//

import SwiftUI

struct AppSecuritySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showCreatePinSheet = false
    @State private var showChangePinSheet = false
    @State private var infoText: String?

    private var locale: Locale {
        AppLocalization.currentAppLocale
    }

    private var biometricsTitle: String {
        AppLockBiometricAuth.settingsTitle()
    }

    private var biometricsAvailable: Bool {
        AppLockBiometricAuth.canUseBiometrics()
    }

    private var hasPin: Bool {
        AppLockPinStore.shared.hasPin()
    }

    var body: some View {
        ZStack {
            GradientBackground()

                ScrollView {
                VStack(spacing: 20) {
                    FinancesSectionHeader(title: localized("profile.security", fallback: "App security"))

                    FinancesGlassCard {
                        VStack(spacing: 0) {
                            Toggle(isOn: Binding(
                                get: { appState.isAppLockEnabled },
                                set: { newValue in
                                    if newValue {
                                        enablePinProtection()
                                    } else {
                                        appState.isAppLockEnabled = false
                                    }
                                }
                            )) {
                                securityRow(
                                    iconSystemName: "lock.fill",
                                    title: localized("profile.security.pin", fallback: "PIN code")
                                )
                            }
                            .tint(AppColors.toggleOnGreen)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .disabled(!hasPin && appState.isAppLockEnabled)

                            FinancesRowDivider()

                            Toggle(isOn: Binding(
                                get: { appState.isBiometricUnlockEnabled },
                                set: { appState.isBiometricUnlockEnabled = $0 }
                            )) {
                                securityRow(iconSystemName: AppLockBiometricAuth.settingsIconSystemName(), title: biometricsTitle)
                            }
                            .tint(AppColors.toggleOnGreen)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .disabled(!appState.isAppLockEnabled || !biometricsAvailable)

                            FinancesRowDivider()

                            Button {
                                showChangePinSheet = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "number")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppColors.textSecondary)
                                        .frame(width: 22, alignment: .leading)
                                    Text(localized("profile.security.change_pin", fallback: "Change PIN code"))
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                            .disabled(!hasPin)
                        }
                    }

                    if let infoText {
                        Text(infoText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(localized("profile.security", fallback: "App security"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCreatePinSheet) {
            AppPinCodeSetupView(mode: .create) {
                appState.isAppLockEnabled = true
                appState.isAppLocked = true
            }
        }
        .sheet(isPresented: $showChangePinSheet) {
            AppPinCodeSetupView(mode: .change, onSaved: {})
        }
        .onAppear {
            if !hasPin, appState.isAppLockEnabled {
                appState.isAppLockEnabled = false
                appState.isBiometricUnlockEnabled = false
            }
            if !biometricsAvailable {
                appState.isBiometricUnlockEnabled = false
                infoText = localized(
                    "profile.security.biometrics_unavailable",
                    fallback: "Biometrics are unavailable on this device."
                )
            } else {
                infoText = nil
            }
        }
    }

    private func enablePinProtection() {
        if hasPin {
            appState.isAppLockEnabled = true
            appState.isAppLocked = true
        } else {
            showCreatePinSheet = true
        }
    }

    private func securityRow(iconSystemName: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconSystemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 22, alignment: .leading)
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func localized(_ key: String, fallback: String) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
    }
}

#Preview {
    NavigationStack {
        AppSecuritySettingsView()
            .environment(AppState())
    }
}
